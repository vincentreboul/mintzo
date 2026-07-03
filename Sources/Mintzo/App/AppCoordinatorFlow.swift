import Foundation
import MintzoCore

// Machine d'états de la dictée bout-en-bout — logique PURE (Foundation + MintzoCore,
// pas de SwiftUI/AppKit). Consommée par AppCoordinator qui la relie au HUD, au menu
// bar et aux réglages. Ce fichier est aussi compilé dans MintzoCoreTests (symlink
// Tests/MintzoCoreTests/AppCoordinatorFlow.swift) pour être testé avec des services
// mockés, sans dépendre de la cible app.
//
// Séquence nominale (brief vague intégration, design-language §4) :
// hotkey → modèle présent ? → capture → RMS vers l'UI → stop → transcription →
// correction (optionnelle, timeout borné → texte brut) → post-processing
// déterministe (trim + majuscule initiale) → insertion → historique → succès.
// Invariant : un texte transcrit n'est JAMAIS perdu (au minimum clipboard + historique).

// MARK: - Ports (protocoles sur les services concrets — mocks dans les tests)

/// Capture micro (implémentée par `CaptureService`).
protocol DictationCapturing: Sendable {
    func start() async throws -> AsyncStream<CaptureChunk>
    func stop() async -> [Float]
}

extension CaptureService: DictationCapturing {}

/// Transcription d'échantillons PCM (implémentée par `TranscriptionService`).
protocol DictationTranscribing: Sendable {
    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult
}

extension TranscriptionService: DictationTranscribing {}

/// Passe de correction (implémentée par `CorrectionService`). Ne lève jamais.
protocol DictationCorrecting: Sendable {
    func correct(_ text: String, language: Language) async -> CorrectionResult
}

extension CorrectionService: DictationCorrecting {}

/// Insertion au curseur (implémentée par `InsertionService`).
@MainActor
protocol DictationInserting: AnyObject {
    func insert(_ text: String) async -> InsertionResult
}

extension InsertionService: DictationInserting {}

/// Écriture dans l'historique (implémentée par `HistoryStore`).
protocol DictationHistoryWriting: Sendable {
    @discardableResult
    func insert(_ transcription: Transcription) throws -> Transcription
}

extension HistoryStore: DictationHistoryWriting {}

/// Présence du modèle de transcription pour une langue (adapter sur `ModelManager`).
protocol DictationModelChecking: Sendable {
    func isModelInstalled(for language: Language) async -> Bool
}

/// Détection de langue eu/fr (implémentée par `TranscriptionService` via
/// whisper-tiny). Mock dans les tests.
protocol DictationLanguageDetecting: Sendable {
    /// Modèle de détection prêt sur le disque ? L'implémentation réelle lance
    /// le téléchargement silencieux quand il manque et répond `false` — la
    /// session en cours utilise alors la langue de repli, jamais d'erreur.
    func isDetectionAvailable() async -> Bool
    /// Détecte la langue sur une fenêtre d'échantillons (~3 s, 16 kHz).
    func detect(samples: [Float]) async throws -> LanguageDetection
}

extension TranscriptionService: DictationLanguageDetecting {
    func detect(samples: [Float]) async throws -> LanguageDetection {
        try await detectLanguage(samples: samples)
    }
}

/// Sélection de langue d'une session de dictée (§4.4) : fixe (badge eu/fr)
/// ou auto (badge « a→ » — détection eu/fr, langue de repli si la détection
/// est indisponible ou hésitante).
enum LanguageSelection: Equatable, Sendable {
    case fixed(Language)
    case auto(fallback: Language)

    /// Langue plancher de la session : la langue fixe, ou le repli du mode auto.
    var fallback: Language {
        switch self {
        case .fixed(let language): language
        case .auto(let fallback): fallback
        }
    }

    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }
}

/// Adapter réel : modèle préféré de la langue (eu → whisper-eu, fr → whisper-fr).
/// `allowAnyInstalledModel` (DEBUG, env `MINTZO_ALLOW_FALLBACK_MODEL=1`) accepte
/// n'importe quel modèle installé — smoke test manuel avec whisper-tiny sans
/// télécharger 3 Go ; `TranscriptionService` fait alors son repli catalogue.
struct WhisperModelAvailability: DictationModelChecking {
    let manager: ModelManager
    var allowAnyInstalledModel = false

    func isModelInstalled(for language: Language) async -> Bool {
        if allowAnyInstalledModel {
            return await !manager.installedModels().isEmpty
        }
        let preferred = switch language {
        case .basque: ModelCatalog.whisperEU
        case .french: ModelCatalog.whisperFR
        }
        return await manager.isInstalled(preferred)
    }
}

// MARK: - Flow

/// Orchestrateur d'une session de dictée. `@MainActor` : tout l'état est sérialisé
/// sur le main actor, les services lourds (capture, whisper, LLM) tournent sur
/// leurs propres acteurs et on ne fait qu'`await` leurs résultats.
@MainActor
final class DictationFlow {

    /// Phase UI-visible de la session (le HUD s'aligne dessus).
    enum Phase: Equatable, Sendable {
        case idle
        case listening
        case transcribing
        case correcting
    }

    /// Raison d'échec d'une session — l'appelant la traduit en microcopy §9.2.
    enum Failure: Equatable, Sendable {
        /// Le modèle de la langue demandée n'est pas installé (« eredua falta da »).
        case modelMissing(Language)
        /// Permission micro absente ou refusée.
        case microphonePermissionDenied
        /// La capture n'a pas démarré (device, convertisseur, engine).
        case captureFailed
        /// La transcription a échoué (message technique du moteur).
        case transcriptionFailed(String)
    }

    /// Événement terminal d'une session.
    enum Outcome: Equatable, Sendable {
        /// Texte collé au curseur (et historisé).
        case inserted
        /// Texte sur le clipboard seulement (mode choisi ou repli) — historisé aussi.
        case clipboardOnly
        /// Session annulée (Échap, tap trop bref, transcription vide) — rien à garder.
        case cancelled
        case failed(Failure)
    }

    // MARK: Dépendances

    private let capture: any DictationCapturing
    private let transcriber: any DictationTranscribing
    private let inserter: any DictationInserting
    private let history: any DictationHistoryWriting
    private let models: any DictationModelChecking
    private let detector: any DictationLanguageDetecting

    // MARK: Configuration (closures : lues en direct, suivent les réglages)

    /// Correcteur du moment, `nil` = correction désactivée.
    var makeCorrector: @MainActor () -> (any DictationCorrecting)? = { nil }
    /// `true` = insertion au curseur ; `false` = clipboard seul (réglage).
    var autoInsertEnabled: @MainActor () -> Bool = { true }
    /// Écriture clipboard du mode « clipboard seul » (NSPasteboard en prod, spy en test).
    var writeClipboard: @MainActor (String) -> Void = { _ in }
    /// Budget maximal de la passe de correction — au-delà : texte brut (brief : 10 s).
    var correctionTimeout: Duration = .seconds(10)
    /// En deçà (~0,25 s à 16 kHz), la session est un raté de hotkey : annulation propre.
    var minimumSampleCount = 4_000
    /// Fenêtre d'analyse du mode auto : ~3 premières secondes (16 kHz).
    var detectionWindowSampleCount = 48_000
    /// Confiance eu/fr renormalisée minimale — en deçà, langue de repli.
    var detectionConfidenceThreshold: Float = 0.65

    // MARK: Sorties observées par le coordinator

    var onPhaseChange: (@MainActor (Phase) -> Void)?
    /// Niveau RMS (0…1) d'une fenêtre ~66 ms — alimente la waveform du HUD.
    var onLevel: (@MainActor (Float) -> Void)?
    var onOutcome: (@MainActor (Outcome) -> Void)?
    /// Mode auto : langue détectée avec confiance suffisante PENDANT l'écoute —
    /// le badge « a→ » bascule sur elle en Gorri (§4.2/§4.4).
    var onLanguageDetected: (@MainActor (Language) -> Void)?

    // MARK: État

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    private var sessionSelection: LanguageSelection = .fixed(.basque)
    private var startupTask: Task<Void, Never>?
    private var chunkTask: Task<Void, Never>?
    /// Fin de session en cours (stop → transcription → correction → insertion) —
    /// annulable par la croix / Échap tant que rien n'est inséré.
    private var completionTask: Task<Void, Never>?
    /// Stop/annulation arrivés pendant le démarrage asynchrone de la capture.
    private var stopRequestedDuringStartup = false
    private var cancelRequestedDuringStartup = false
    /// Mode auto : échantillons des premières secondes (fenêtre de détection).
    private var detectionSamples: [Float] = []
    private var detectionTask: Task<Void, Never>?
    /// Verdict retenu pour la session (confiance ≥ seuil), sinon nil.
    private var sessionDetection: LanguageDetection?
    /// Modèle de détection prêt au démarrage de CETTE session.
    private var detectionAvailableForSession = false

    init(
        capture: any DictationCapturing,
        transcriber: any DictationTranscribing,
        inserter: any DictationInserting,
        history: any DictationHistoryWriting,
        models: any DictationModelChecking,
        detector: any DictationLanguageDetecting
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.inserter = inserter
        self.history = history
        self.models = models
        self.detector = detector
    }

    // MARK: Entrées

    /// Point d'entrée des événements hotkey (push-to-talk et toggle confondus).
    /// `selection` = état du badge HUD au moment de l'événement ; au stop elle
    /// fait foi (l'utilisateur peut corriger la langue en cours de dictée, §4.4).
    func handle(_ event: HotkeyEvent, selection: LanguageSelection) {
        switch event {
        case .pressBegan:
            beginSession(selection: selection)
        case .pressEnded:
            sessionSelection = selection
            endSession()
        case .toggled:
            switch phase {
            case .idle:
                beginSession(selection: selection)
            case .listening:
                sessionSelection = selection
                endSession()
            case .transcribing, .correcting:
                break // session déjà en traitement
            }
        }
    }

    /// Croix / Échap : abort propre de la session, quel que soit l'état actif.
    /// Écoute : échantillons jetés. Transcription / correction : la tâche de
    /// fin de session est annulée AVANT toute insertion — les moteurs
    /// (whisper, llama) reçoivent l'annulation par propagation, leur résultat
    /// éventuel meurt dans son coin. Aucun texte inséré, rien d'historisé.
    func cancel() {
        if startupTask != nil {
            cancelRequestedDuringStartup = true
            return
        }
        switch phase {
        case .listening:
            chunkTask?.cancel()
            chunkTask = nil
            detectionTask?.cancel()
            detectionTask = nil
            phase = .idle
            let capture = self.capture
            Task { _ = await capture.stop() } // vide la session côté capture, résultat jeté
            onOutcome?(.cancelled)
        case .transcribing, .correcting:
            completionTask?.cancel()
            completionTask = nil
            detectionTask?.cancel()
            detectionTask = nil
            phase = .idle
            onOutcome?(.cancelled)
        case .idle:
            break
        }
    }

    // MARK: Démarrage

    private func beginSession(selection: LanguageSelection) {
        guard phase == .idle, startupTask == nil else { return }
        stopRequestedDuringStartup = false
        cancelRequestedDuringStartup = false
        sessionSelection = selection
        sessionDetection = nil
        detectionSamples = []
        detectionTask?.cancel()
        detectionTask = nil
        startupTask = Task { [weak self] in
            await self?.runStartup(selection: selection)
            self?.startupTask = nil
            self?.resolveRequestsReceivedDuringStartup()
        }
    }

    private func runStartup(selection: LanguageSelection) async {
        // Mode auto : détection dispo ? (Absente : téléchargement silencieux
        // lancé par l'implémentation, la session utilisera la langue de repli.)
        detectionAvailableForSession = selection.isAuto
            ? await detector.isDetectionAvailable()
            : false

        // Modèle plancher absent (langue fixe, ou repli du mode auto) →
        // erreur AVANT d'ouvrir le micro (§9.2).
        guard await models.isModelInstalled(for: selection.fallback) else {
            onOutcome?(.failed(.modelMissing(selection.fallback)))
            return
        }
        if cancelRequestedDuringStartup || stopRequestedDuringStartup { return }

        let stream: AsyncStream<CaptureChunk>
        do {
            stream = try await capture.start()
        } catch CaptureError.permissionDenied {
            onOutcome?(.failed(.microphonePermissionDenied))
            return
        } catch {
            onOutcome?(.failed(.captureFailed))
            return
        }

        phase = .listening
        chunkTask = Task { [weak self] in
            for await chunk in stream {
                guard !Task.isCancelled else { return }
                self?.onLevel?(chunk.rms)
                self?.accumulateForDetection(chunk)
            }
        }
    }

    // MARK: Détection live (mode auto, §4.4)

    /// Accumule les premières secondes puis lance UNE détection : le badge
    /// « a→ » bascule sur la langue détectée pendant que l'utilisateur parle.
    private func accumulateForDetection(_ chunk: CaptureChunk) {
        guard sessionSelection.isAuto, detectionAvailableForSession,
              detectionTask == nil else { return }
        detectionSamples.append(contentsOf: chunk.samples)
        guard detectionSamples.count >= detectionWindowSampleCount else { return }
        launchDetection(on: detectionSamples)
        detectionSamples = [] // fenêtre transmise — rien d'autre à retenir
    }

    private func launchDetection(on samples: [Float]) {
        guard detectionTask == nil else { return }
        let detector = self.detector
        detectionTask = Task { [weak self] in
            let detection = try? await detector.detect(samples: samples)
            guard !Task.isCancelled else { return }
            self?.applyDetection(detection)
        }
    }

    private func applyDetection(_ detection: LanguageDetection?) {
        guard sessionSelection.isAuto, phase == .listening || phase == .transcribing,
              let detection,
              detection.confidence >= detectionConfidenceThreshold,
              let language = Language(rawValue: detection.language) else { return }
        sessionDetection = detection
        // Feedback badge seulement pendant l'écoute — après le stop, le verdict
        // sert au routage, le HUD est déjà passé en « Transkribatzen… ».
        if phase == .listening {
            onLanguageDetected?(language)
        }
    }

    /// Un stop/Échap reçu pendant le démarrage est appliqué dès la capture prête.
    private func resolveRequestsReceivedDuringStartup() {
        if cancelRequestedDuringStartup {
            cancelRequestedDuringStartup = false
            stopRequestedDuringStartup = false
            cancel()
        } else if stopRequestedDuringStartup {
            stopRequestedDuringStartup = false
            endSession()
        }
    }

    // MARK: Fin de session (stop → transcription → correction → insertion → historique)

    private func endSession() {
        if startupTask != nil {
            stopRequestedDuringStartup = true
            return
        }
        guard phase == .listening else { return }
        phase = .transcribing
        chunkTask?.cancel()
        chunkTask = nil
        completionTask = Task { [weak self] in
            await self?.runCompletion()
            self?.completionTask = nil
        }
    }

    private func runCompletion() async {
        let samples = await capture.stop()
        // Session annulée (croix / Échap) pendant un await : `cancel()` a déjà
        // posé phase = .idle et émis `.cancelled` — tout résultat est jeté ici.
        guard !Task.isCancelled else { return }

        // Tap raté / micro à peine ouvert : annulation silencieuse, pas d'erreur.
        guard samples.count >= minimumSampleCount else {
            finish(.cancelled)
            return
        }

        // Langue effective de la session : fixe, détectée, ou repli. Elle fait
        // foi pour la transcription, la correction ET l'historique (§4.4).
        let language = await resolveSessionLanguage(samples: samples)
        guard !Task.isCancelled else { return }

        let result: TranscriptionResult
        do {
            result = try await transcriber.transcribe(samples: samples, language: language.rawValue)
        } catch {
            guard !Task.isCancelled else { return }
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            finish(.failed(.transcriptionFailed(detail)))
            return
        }
        guard !Task.isCancelled else { return }

        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            // Silence transcrit : rien à insérer, rien à historiser — pas un succès menteur.
            finish(.cancelled)
            return
        }

        var finalText = raw
        if let corrector = makeCorrector() {
            phase = .correcting
            finalText = await Self.correct(
                raw, language: language, corrector: corrector, timeout: correctionTimeout
            )
        }
        finalText = Self.postProcess(finalText)
        // Dernier point de contrôle AVANT l'insertion : une session annulée
        // n'insère JAMAIS de texte (et n'historise rien).
        guard !Task.isCancelled else { return }

        let outcome: Outcome
        if autoInsertEnabled() {
            switch await inserter.insert(finalText) {
            case .inserted:
                outcome = .inserted
            case .clipboardOnly:
                outcome = .clipboardOnly
            case .nothingToInsert:
                finish(.cancelled)
                return
            }
        } else {
            writeClipboard(finalText)
            outcome = .clipboardOnly
        }

        // Historique APRÈS l'insertion (ordre du brief). Un échec d'écriture ne fait
        // pas échouer la session : le texte est déjà livré (curseur ou clipboard).
        let record = Transcription(
            texteBrut: raw,
            texteCorrige: finalText != raw ? finalText : nil,
            dureeAudio: result.audioDuration,
            langue: language == .basque ? .eu : .fr,
            source: .dictee
        )
        do {
            try history.insert(record)
        } catch {
            NSLog("Mintzo: écriture historique échouée — %@", error.localizedDescription)
        }

        finish(outcome)
    }

    /// Verdict de langue au stop (mode auto) : détection live si elle a rendu,
    /// sinon tentative unique sur l'audio complet (session plus courte que la
    /// fenêtre), sinon langue de repli. Le modèle de la langue détectée doit
    /// être présent — sinon repli, jamais d'erreur en fin de session.
    private func resolveSessionLanguage(samples: [Float]) async -> Language {
        switch sessionSelection {
        case .fixed(let language):
            return language
        case .auto(let fallback):
            if let task = detectionTask {
                await task.value // verdict de la détection live (rapide : tiny)
            }
            // Pas de verdict live (session courte, bascule vers auto AU stop,
            // ou tiny téléchargé PENDANT la session) : disponibilité re-sondée
            // puis tentative unique sur l'audio complet.
            if sessionDetection == nil, await detector.isDetectionAvailable() {
                let window = Array(samples.prefix(detectionWindowSampleCount))
                applyDetection(try? await detector.detect(samples: window))
            }
            guard let detection = sessionDetection,
                  let detected = Language(rawValue: detection.language) else {
                NSLog("Mintzo: détection eu/fr indisponible ou hésitante — repli « %@ »",
                      fallback.rawValue)
                return fallback
            }
            guard await models.isModelInstalled(for: detected) else {
                NSLog("Mintzo: modèle absent pour la langue détectée « %@ » — repli « %@ »",
                      detected.rawValue, fallback.rawValue)
                return fallback
            }
            return detected
        }
    }

    private func finish(_ outcome: Outcome) {
        phase = .idle
        detectionTask = nil
        onOutcome?(outcome)
    }

    // MARK: Correction bornée

    /// Course correction vs timeout : le premier arrivé gagne. Si le moteur ignore
    /// l'annulation (llama.cpp en pleine génération), on n'attend PAS sa fin —
    /// le texte brut part tout de suite, la tâche orpheline meurt dans son coin.
    static func correct(
        _ text: String,
        language: Language,
        corrector: any DictationCorrecting,
        timeout: Duration
    ) async -> String {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let work = Task {
            let result = await corrector.correct(text, language: language)
            continuation.yield(result.text)
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            continuation.yield(text)
        }
        var iterator = stream.makeAsyncIterator()
        let winner = await iterator.next() ?? text
        work.cancel()
        timer.cancel()
        continuation.finish()
        return winner
    }

    // MARK: Post-processing déterministe

    /// Trim + majuscule initiale — la seule transformation hors moteur, assumée
    /// et prévisible (pas de « nettoyage » heuristique).
    static func postProcess(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLowercase else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}
