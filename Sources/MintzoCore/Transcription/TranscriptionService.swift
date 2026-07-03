import Foundation

/// Erreurs du service de transcription.
public enum TranscriptionServiceError: Error, LocalizedError, Sendable {
    /// Aucun modèle installé ne peut traiter cette demande.
    case noModelInstalled(language: String?)
    /// Le modèle est installé mais son chargement a échoué.
    case modelLoadFailed(modelID: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .noModelInstalled(let language):
            let lang = language.map { " pour la langue « \($0) »" } ?? ""
            return "Aucun modèle Whisper installé\(lang) — télécharger un modèle d'abord"
        case .modelLoadFailed(let modelID, let detail):
            return "Chargement du modèle \(modelID) échoué : \(detail)"
        }
    }
}

/// Résultat d'une transcription.
public struct TranscriptionResult: Sendable, Equatable {
    /// Texte transcrit (segments concaténés, sans timestamps).
    public let text: String
    /// Langue demandée (`nil` = auto-détection whisper).
    public let language: String?
    /// Identifiant du modèle effectivement utilisé.
    public let modelID: String
    /// Durée de l'audio transcrit, en secondes.
    public let audioDuration: TimeInterval
    /// Temps de calcul de la transcription (hors décodage/chargement), en secondes.
    public let processingDuration: TimeInterval
}

/// Phase du pipeline en cours — étapes réelles, pas de pourcentage estimé
/// (whisper.cpp peut fournir une progression fine mais `WhisperEngine`
/// ne l'expose pas encore).
public enum TranscriptionPhase: Sendable, Equatable {
    case decodingAudio
    case loadingModel(modelID: String)
    case transcribing(modelID: String)
}

/// Événements du cycle de vie d'un fichier en file de transcription.
public enum TranscriptionJobEvent: Sendable {
    /// Enfilé ; `position` = nombre de jobs devant celui-ci (0 = traité dès que possible).
    case queued(position: Int)
    /// Le worker a pris le job.
    case started
    /// Avancement par phases réelles du pipeline.
    case progress(TranscriptionPhase)
    /// Terminé avec succès.
    case done(TranscriptionResult)
    /// Échoué (erreur décodage, modèle absent, transcription).
    case failed(String)
}

/// Orchestrateur de transcription : sélection du modèle selon la langue,
/// chargement paresseux (un seul gros modèle en RAM à la fois), et file FIFO
/// de fichiers audio.
///
/// Politique modèle : `eu` → whisper-eu, `fr` → whisper-fr ; si le modèle
/// préféré n'est pas installé, repli sur le premier modèle installé
/// (ordre catalogue). Les modèles Whisper étant multilingues, un repli reste
/// fonctionnel — la qualité est simplement moindre.
public actor TranscriptionService {

    private let modelManager: ModelManager

    /// Dictionnaire personnalisé (optionnel) : ses MOTS deviennent l'amorce
    /// whisper (`initial_prompt`) de chaque transcription — dictée ET fichiers
    /// passent par `transcribe(samples:language:)`, l'injection couvre les deux.
    private let vocabulary: VocabularyStore?

    /// Moteur chargé (au plus un — un grand modèle = 1,6 à 3,1 Go de RAM).
    private var loadedEngine: (modelID: String, engine: WhisperEngine)?

    /// Moteur de DÉTECTION de langue (whisper-tiny, ~75 Mo) — chargé à la
    /// demande puis RÉSIDENT : sa petite taille autorise la cohabitation avec
    /// le gros modèle, et la détection doit rester quasi instantanée (§4.4).
    private var detectionEngine: WhisperEngine?
    /// Téléchargement silencieux de whisper-tiny en cours (un seul à la fois).
    private var detectionModelDownload: Task<Void, Never>?

    /// File FIFO des fichiers à transcrire.
    private var pendingJobs: [Job] = []
    private var isProcessing = false
    /// 1 si le worker a dépilé un job qu'il traite encore, 0 sinon —
    /// évite le double comptage dans le calcul de position.
    private var inFlightCount = 0

    private struct Job {
        let url: URL
        let language: String?
        let continuation: AsyncStream<TranscriptionJobEvent>.Continuation
    }

    public init(modelManager: ModelManager, vocabulary: VocabularyStore? = nil) {
        self.modelManager = modelManager
        self.vocabulary = vocabulary
    }

    // MARK: - Sélection et chargement du modèle

    /// Modèle préféré pour une langue donnée.
    private static func preferredModel(for language: String?) -> WhisperModel? {
        switch language {
        case "eu": return ModelCatalog.whisperEU
        case "fr": return ModelCatalog.whisperFR
        default: return nil
        }
    }

    /// Choisit le modèle : préféré pour la langue s'il est installé, sinon
    /// premier modèle installé (ordre catalogue).
    private func selectModel(for language: String?) async throws -> WhisperModel {
        if let preferred = Self.preferredModel(for: language),
           await modelManager.isInstalled(preferred) {
            return preferred
        }
        let installed = await modelManager.installedModels()
        guard let fallback = installed.first else {
            throw TranscriptionServiceError.noModelInstalled(language: language)
        }
        return fallback
    }

    /// Charge le moteur du modèle demandé (paresseux). Si un autre modèle est
    /// en RAM, il est libéré AVANT le chargement — jamais deux gros modèles
    /// simultanément.
    private func engine(for model: WhisperModel) async throws -> WhisperEngine {
        if let loaded = loadedEngine, loaded.modelID == model.id {
            return loaded.engine
        }
        loadedEngine = nil // libère l'ancien moteur (whisper_free via deinit)

        guard let modelURL = await modelManager.localURL(for: model) else {
            throw TranscriptionServiceError.noModelInstalled(language: nil)
        }
        do {
            // Init détaché : le chargement (jusqu'à ~3 Go) ne bloque pas l'acteur.
            let engine = try await Task.detached(priority: .userInitiated) {
                try WhisperEngine(modelPath: modelURL)
            }.value
            loadedEngine = (model.id, engine)
            return engine
        } catch {
            throw TranscriptionServiceError.modelLoadFailed(
                modelID: model.id, detail: error.localizedDescription
            )
        }
    }

    /// Décharge tout moteur en RAM (whisper_free). Le prochain `transcribe`
    /// rechargera paresseusement.
    public func unloadAll() {
        loadedEngine = nil
        detectionEngine = nil
    }

    // MARK: - Détection de langue (mode auto, §4.4)

    /// Fenêtre d'analyse : les ~3 premières secondes de la session (16 kHz).
    public static let detectionWindowSampleCount = 48_000
    /// Langues candidates du produit — la décision est restreinte à eu vs fr.
    public static let detectionCandidates = ["eu", "fr"]
    /// Sous ce seuil (probabilité renormalisée eu/fr), la détection est jugée
    /// hésitante : l'appelant retombe sur la langue par défaut de l'utilisateur.
    public static let detectionConfidenceThreshold: Float = 0.65

    /// `true` si le modèle de détection (whisper-tiny) est prêt sur le disque.
    /// Absent : lance AUSSI son téléchargement silencieux (75 Mo, un seul à la
    /// fois) — le mode auto s'auto-répare au premier besoin, sans jamais
    /// bloquer la session en cours (décision client / §4.4).
    public func isDetectionAvailable() async -> Bool {
        if await modelManager.isInstalled(ModelCatalog.whisperTiny) { return true }
        kickDetectionModelDownload()
        return false
    }

    /// Détecte eu vs fr sur les premières secondes des échantillons fournis.
    ///
    /// Modèle absent → lance UN téléchargement silencieux (75 Mo) en arrière-
    /// plan et lève `noModelInstalled` : l'appelant retombe sur sa langue de
    /// repli pour CETTE session, les suivantes profiteront du modèle. Jamais
    /// d'erreur bloquante (§4.4 / décision client).
    public func detectLanguage(samples: [Float]) async throws -> LanguageDetection {
        guard await isDetectionAvailable() else {
            // isDetectionAvailable a déjà lancé le téléchargement silencieux.
            throw TranscriptionServiceError.noModelInstalled(
                language: ModelCatalog.whisperTiny.id
            )
        }
        let engine = try await detectionEngine()
        let window = Array(samples.prefix(Self.detectionWindowSampleCount))
        return try await engine.detectLanguage(samples: window, among: Self.detectionCandidates)
    }

    /// Charge (paresseusement) le moteur tiny résident.
    private func detectionEngine() async throws -> WhisperEngine {
        if let detectionEngine { return detectionEngine }
        guard let url = await modelManager.localURL(for: ModelCatalog.whisperTiny) else {
            throw TranscriptionServiceError.noModelInstalled(
                language: ModelCatalog.whisperTiny.id
            )
        }
        do {
            let engine = try await Task.detached(priority: .userInitiated) {
                try WhisperEngine(modelPath: url)
            }.value
            detectionEngine = engine
            return engine
        } catch {
            throw TranscriptionServiceError.modelLoadFailed(
                modelID: ModelCatalog.whisperTiny.id, detail: error.localizedDescription
            )
        }
    }

    /// Téléchargement silencieux de whisper-tiny — au plus un à la fois,
    /// résultat au log uniquement (pas d'UI imposée : calme, §1).
    private func kickDetectionModelDownload() {
        guard detectionModelDownload == nil else { return }
        let manager = modelManager
        detectionModelDownload = Task { [weak self] in
            do {
                for try await _ in manager.download(ModelCatalog.whisperTiny) {}
                NSLog("Mintzo: modèle de détection %@ téléchargé (auto prêt)",
                      ModelCatalog.whisperTiny.id)
            } catch {
                NSLog("Mintzo: téléchargement du modèle de détection échoué — %@",
                      error.localizedDescription)
            }
            await self?.clearDetectionModelDownload()
        }
    }

    private func clearDetectionModelDownload() {
        detectionModelDownload = nil
    }

    // MARK: - Transcription directe

    /// Transcrit des échantillons PCM float32 mono 16 kHz.
    ///
    /// `language` nil = mode auto : détection eu/fr sur les ~3 premières
    /// secondes (whisper-tiny), puis routage vers le modèle de la langue
    /// détectée. Détection indisponible ou hésitante → comportement
    /// historique (premier modèle installé, auto-détection whisper interne).
    public func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        var effectiveLanguage = language
        if language == nil,
           let detection = try? await detectLanguage(samples: samples),
           detection.confidence >= Self.detectionConfidenceThreshold {
            effectiveLanguage = detection.language
        }

        let model = try await selectModel(for: effectiveLanguage)
        let engine = try await engine(for: model)

        // Amorce du dictionnaire : mots joints, tronqués par mots entiers
        // (~800 caractères — voir VocabularyPrompt). Lue au moment de la
        // transcription : les réglages en cours de session sont suivis.
        var initialPrompt: String?
        if let vocabulary {
            initialPrompt = VocabularyPrompt.whisperPrompt(words: await vocabulary.words)
        }

        let started = ContinuousClock.now
        let text = try await engine.transcribe(
            samples: samples, language: effectiveLanguage, initialPrompt: initialPrompt
        )
        let elapsed = started.duration(to: .now)

        return TranscriptionResult(
            text: text,
            language: effectiveLanguage,
            modelID: model.id,
            audioDuration: Double(samples.count) / AudioFileDecoder.targetSampleRate,
            processingDuration: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        )
    }

    // MARK: - File FIFO de fichiers

    /// Enfile un fichier audio à transcrire. Retourne le flux d'événements de
    /// CE job : `queued` → `started` → `progress`… → `done` ou `failed`.
    /// Les jobs sont traités strictement dans l'ordre d'arrivée, un à la fois.
    public func enqueue(url: URL, language: String?) -> AsyncStream<TranscriptionJobEvent> {
        let (stream, continuation) = AsyncStream<TranscriptionJobEvent>.makeStream()

        let position = pendingJobs.count + inFlightCount
        continuation.yield(.queued(position: position))

        pendingJobs.append(Job(url: url, language: language, continuation: continuation))
        startWorkerIfIdle()

        return stream
    }

    private func startWorkerIfIdle() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { await self.drainQueue() }
    }

    /// Worker unique : dépile et traite les jobs en série (FIFO strict).
    private func drainQueue() async {
        while !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            inFlightCount = 1
            defer { inFlightCount = 0 }
            job.continuation.yield(.started)
            do {
                job.continuation.yield(.progress(.decodingAudio))
                let url = job.url
                // Décodage détaché : ne bloque pas l'acteur (enqueue reste réactif).
                let samples = try await Task.detached(priority: .userInitiated) {
                    try AudioFileDecoder.decode(url: url)
                }.value

                let model = try await selectModel(for: job.language)
                if loadedEngine?.modelID != model.id {
                    job.continuation.yield(.progress(.loadingModel(modelID: model.id)))
                }
                job.continuation.yield(.progress(.transcribing(modelID: model.id)))

                let result = try await transcribe(samples: samples, language: job.language)
                job.continuation.yield(.done(result))
            } catch {
                let description = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                job.continuation.yield(.failed(description))
            }
            job.continuation.finish()
        }
        isProcessing = false
    }
}
