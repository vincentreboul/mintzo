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

    // MARK: Sorties observées par le coordinator

    var onPhaseChange: (@MainActor (Phase) -> Void)?
    /// Niveau RMS (0…1) d'une fenêtre ~66 ms — alimente la waveform du HUD.
    var onLevel: (@MainActor (Float) -> Void)?
    var onOutcome: (@MainActor (Outcome) -> Void)?

    // MARK: État

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    private var sessionLanguage: Language = .basque
    private var startupTask: Task<Void, Never>?
    private var chunkTask: Task<Void, Never>?
    /// Stop/annulation arrivés pendant le démarrage asynchrone de la capture.
    private var stopRequestedDuringStartup = false
    private var cancelRequestedDuringStartup = false

    init(
        capture: any DictationCapturing,
        transcriber: any DictationTranscribing,
        inserter: any DictationInserting,
        history: any DictationHistoryWriting,
        models: any DictationModelChecking
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.inserter = inserter
        self.history = history
        self.models = models
    }

    // MARK: Entrées

    /// Point d'entrée des événements hotkey (push-to-talk et toggle confondus).
    /// `language` = langue du badge HUD au moment de l'événement ; au stop elle
    /// fait foi (l'utilisateur peut corriger la langue en cours de dictée, §4.4).
    func handle(_ event: HotkeyEvent, language: Language) {
        switch event {
        case .pressBegan:
            beginSession(language: language)
        case .pressEnded:
            sessionLanguage = language
            endSession()
        case .toggled:
            switch phase {
            case .idle:
                beginSession(language: language)
            case .listening:
                sessionLanguage = language
                endSession()
            case .transcribing, .correcting:
                break // session déjà en traitement
            }
        }
    }

    /// Échap pendant l'écoute : abort propre, échantillons jetés, HUD refermé.
    func cancel() {
        if startupTask != nil {
            cancelRequestedDuringStartup = true
            return
        }
        guard phase == .listening else { return }
        chunkTask?.cancel()
        chunkTask = nil
        phase = .idle
        let capture = self.capture
        Task { _ = await capture.stop() } // vide la session côté capture, résultat jeté
        onOutcome?(.cancelled)
    }

    // MARK: Démarrage

    private func beginSession(language: Language) {
        guard phase == .idle, startupTask == nil else { return }
        stopRequestedDuringStartup = false
        cancelRequestedDuringStartup = false
        sessionLanguage = language
        startupTask = Task { [weak self] in
            await self?.runStartup(language: language)
            self?.startupTask = nil
            self?.resolveRequestsReceivedDuringStartup()
        }
    }

    private func runStartup(language: Language) async {
        // Modèle de la langue courante absent → erreur AVANT d'ouvrir le micro (§9.2).
        guard await models.isModelInstalled(for: language) else {
            onOutcome?(.failed(.modelMissing(language)))
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
            }
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
        Task { [weak self] in
            await self?.runCompletion()
        }
    }

    private func runCompletion() async {
        let samples = await capture.stop()
        let language = sessionLanguage

        // Tap raté / micro à peine ouvert : annulation silencieuse, pas d'erreur.
        guard samples.count >= minimumSampleCount else {
            finish(.cancelled)
            return
        }

        let result: TranscriptionResult
        do {
            result = try await transcriber.transcribe(samples: samples, language: language.rawValue)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            finish(.failed(.transcriptionFailed(detail)))
            return
        }

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

    private func finish(_ outcome: Outcome) {
        phase = .idle
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
