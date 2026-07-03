import XCTest
@testable import MintzoCore

// Tests de la machine d'états de dictée (AppCoordinatorFlow.swift, compilé ici
// via symlink) avec tous les services mockés : nominal, modèle manquant,
// timeout de correction → texte brut, erreur capture, annulation, clipboard.

// MARK: - Mocks

@MainActor
private final class MockCapture: DictationCapturing {
    var startError: (any Error)?
    var samplesToReturn: [Float] = Array(repeating: 0.1, count: 16_000)
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var continuation: AsyncStream<CaptureChunk>.Continuation?

    func start() async throws -> AsyncStream<CaptureChunk> {
        startCallCount += 1
        if let startError { throw startError }
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureChunk.self)
        self.continuation = continuation
        return stream
    }

    func stop() async -> [Float] {
        stopCallCount += 1
        continuation?.finish()
        continuation = nil
        return samplesToReturn
    }

    func emit(rms: Float, samples: [Float] = []) {
        continuation?.yield(CaptureChunk(samples: samples, rms: rms))
    }
}

@MainActor
private final class MockTranscriber: DictationTranscribing {
    var textToReturn = "kaixo mundua"
    var errorToThrow: (any Error)?
    /// Transcription artificiellement lente — tient la phase `.transcribing`
    /// le temps de tester l'annulation par la croix / Échap.
    var delay: Duration = .zero
    private(set) var lastLanguage: String??
    private(set) var lastSampleCount: Int?

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        lastLanguage = language
        lastSampleCount = samples.count
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let errorToThrow { throw errorToThrow }
        return TranscriptionResult(
            text: textToReturn,
            language: language,
            modelID: "whisper-test",
            audioDuration: Double(samples.count) / 16_000,
            processingDuration: 0.01
        )
    }
}

/// Correcteur mock : réponse immédiate ou artificiellement lente (test du timeout).
private struct MockCorrector: DictationCorrecting {
    var output: String
    var delay: Duration = .zero

    func correct(_ text: String, language: Language) async -> CorrectionResult {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return CorrectionResult(text: output, outcome: .corrected)
    }
}

@MainActor
private final class MockInserter: DictationInserting {
    var resultToReturn: InsertionResult = .inserted
    private(set) var insertedTexts: [String] = []

    func insert(_ text: String) async -> InsertionResult {
        insertedTexts.append(text)
        return resultToReturn
    }
}

/// Non isolé : le protocole exige un témoin synchrone (comme `HistoryStore`).
private final class MockHistory: DictationHistoryWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [Transcription] = []
    var records: [Transcription] {
        lock.lock(); defer { lock.unlock() }
        return _records
    }

    @discardableResult
    func insert(_ transcription: Transcription) throws -> Transcription {
        lock.lock(); defer { lock.unlock() }
        var record = transcription
        record.id = Int64(_records.count + 1)
        _records.append(record)
        return record
    }
}

private struct MockModels: DictationModelChecking {
    var installed = true
    /// Langues dont le modèle est absent (prioritaire sur `installed`).
    var missingLanguages: Set<Language> = []

    func isModelInstalled(for language: Language) async -> Bool {
        if missingLanguages.contains(language) { return false }
        return installed
    }
}

/// Détecteur mock : verdict programmable, indisponibilité simulable.
private final class MockDetector: DictationLanguageDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _available = true
    private var _detection: LanguageDetection?
    private var _error: (any Error)?
    private var _detectCallCount = 0
    private var _availabilityCallCount = 0

    var available: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _available }
        set { lock.lock(); defer { lock.unlock() }; _available = newValue }
    }
    var detection: LanguageDetection? {
        get { lock.lock(); defer { lock.unlock() }; return _detection }
        set { lock.lock(); defer { lock.unlock() }; _detection = newValue }
    }
    var error: (any Error)? {
        get { lock.lock(); defer { lock.unlock() }; return _error }
        set { lock.lock(); defer { lock.unlock() }; _error = newValue }
    }
    var detectCallCount: Int { lock.lock(); defer { lock.unlock() }; return _detectCallCount }
    var availabilityCallCount: Int { lock.lock(); defer { lock.unlock() }; return _availabilityCallCount }

    func isDetectionAvailable() async -> Bool {
        consumeAvailability()
    }

    func detect(samples: [Float]) async throws -> LanguageDetection {
        let (error, detection) = consumeVerdict()
        if let error { throw error }
        guard let detection else {
            throw TranscriptionServiceError.noModelInstalled(language: "tiny")
        }
        return detection
    }

    // NSLock est interdit dans un contexte async (Swift 6) : sections
    // critiques dans des helpers SYNCHRONES.
    private func consumeAvailability() -> Bool {
        lock.lock(); defer { lock.unlock() }
        _availabilityCallCount += 1
        return _available
    }

    private func consumeVerdict() -> ((any Error)?, LanguageDetection?) {
        lock.lock(); defer { lock.unlock() }
        _detectCallCount += 1
        return (_error, _detection)
    }
}

// MARK: - Harnais

@MainActor
private struct FlowHarness {
    let capture = MockCapture()
    let transcriber = MockTranscriber()
    let inserter = MockInserter()
    let history = MockHistory()
    let detector = MockDetector()
    let flow: DictationFlow

    private final class EventLog {
        var outcomes: [DictationFlow.Outcome] = []
        var phases: [DictationFlow.Phase] = []
        var detectedLanguages: [Language] = []
    }
    private let log = EventLog()

    var outcomes: [DictationFlow.Outcome] { log.outcomes }
    var phases: [DictationFlow.Phase] { log.phases }
    var detectedLanguages: [Language] { log.detectedLanguages }

    init(modelsInstalled: Bool = true, missingLanguages: Set<Language> = []) {
        flow = DictationFlow(
            capture: capture,
            transcriber: transcriber,
            inserter: inserter,
            history: history,
            models: MockModels(installed: modelsInstalled, missingLanguages: missingLanguages),
            detector: detector
        )
        let log = self.log
        flow.onOutcome = { log.outcomes.append($0) }
        flow.onPhaseChange = { log.phases.append($0) }
        flow.onLanguageDetected = { log.detectedLanguages.append($0) }
    }

    /// Dictée complète : press → écoute effective → release → outcome.
    func runFullSession(language: Language = .basque) async throws {
        try await runFullSession(selection: .fixed(language))
    }

    func runFullSession(selection: LanguageSelection) async throws {
        flow.handle(.pressBegan, selection: selection)
        try await waitUntil("écoute démarrée") { flow.phase == .listening }
        flow.handle(.pressEnded, selection: selection)
        try await waitUntil("outcome émis") { !outcomes.isEmpty }
    }

    func waitUntil(
        _ label: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timeout en attendant : \(label)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Tests

@MainActor
final class AppCoordinatorFlowTests: XCTestCase {

    // MARK: Dictée nominale

    func testNominalDictationInsertsPostProcessedTextAndRecordsHistory() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "  kaixo mundua  "

        try await harness.runFullSession(language: .basque)

        XCTAssertEqual(harness.outcomes, [.inserted])
        // Post-processing déterministe : trim + majuscule initiale.
        XCTAssertEqual(harness.inserter.insertedTexts, ["Kaixo mundua"])
        // Correction désactivée par défaut : jamais de phase correcting.
        XCTAssertEqual(harness.phases, [.listening, .transcribing, .idle])
        XCTAssertEqual(harness.transcriber.lastLanguage, "eu")

        let records = harness.history.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.texteBrut, "kaixo mundua")
        XCTAssertEqual(records.first?.texteCorrige, "Kaixo mundua")
        XCTAssertEqual(records.first?.langue, .eu)
        XCTAssertEqual(records.first?.source, .dictee)
        XCTAssertEqual(records.first?.dureeAudio ?? 0, 1.0, accuracy: 0.001)
    }

    func testFrenchSessionPassesLanguageThrough() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "bonjour"

        try await harness.runFullSession(language: .french)

        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(harness.history.records.first?.langue, .fr)
    }

    func testLanguageSwitchedMidSessionUsesStopTimeLanguage() async throws {
        // Badge cyclé pendant la dictée (§4.4) : la langue au STOP fait foi.
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "bonjour"

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.french))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(harness.history.records.first?.langue, .fr)
    }

    func testRMSChunksAreForwardedWhileListening() async throws {
        let harness = FlowHarness()
        var levels: [Float] = []
        harness.flow.onLevel = { levels.append($0) }

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.capture.emit(rms: 0.25)
        harness.capture.emit(rms: 0.5)
        try await harness.waitUntil("niveaux reçus") { levels.count == 2 }

        XCTAssertEqual(levels, [0.25, 0.5])
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }
    }

    // MARK: Modèle manquant

    func testMissingModelFailsBeforeOpeningMicrophone() async throws {
        let harness = FlowHarness(modelsInstalled: false)

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.failed(.modelMissing(.basque))])
        XCTAssertEqual(harness.capture.startCallCount, 0, "le micro ne doit jamais s'ouvrir")
        XCTAssertEqual(harness.flow.phase, .idle)
        XCTAssertTrue(harness.history.records.isEmpty)
    }

    // MARK: Correction

    func testCorrectionAppliedWhenEngineAnswersInTime() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "kaixo mundua"
        harness.flow.makeCorrector = { MockCorrector(output: "kaixo, mundua.") }

        try await harness.runFullSession()

        XCTAssertEqual(harness.inserter.insertedTexts, ["Kaixo, mundua."])
        XCTAssertEqual(harness.phases, [.listening, .transcribing, .correcting, .idle])
        XCTAssertEqual(harness.history.records.first?.texteBrut, "kaixo mundua")
        XCTAssertEqual(harness.history.records.first?.texteCorrige, "Kaixo, mundua.")
    }

    func testCorrectionTimeoutFallsBackToRawText() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "kaixo mundua"
        // Correcteur qui « pense » 60 s : le budget de 50 ms doit gagner.
        harness.flow.makeCorrector = { MockCorrector(output: "JAMAIS UTILISÉ", delay: .seconds(60)) }
        harness.flow.correctionTimeout = .milliseconds(50)

        try await harness.runFullSession()

        XCTAssertEqual(harness.outcomes, [.inserted])
        XCTAssertEqual(harness.inserter.insertedTexts, ["Kaixo mundua"], "timeout → texte brut post-processé")
        XCTAssertTrue(harness.phases.contains(.correcting))
    }

    // MARK: Dictionnaire (post-pass remplacements)

    func testVocabularyReplacementsApplyWithoutCorrection() async throws {
        // Exemple du design : « mine tso » → « Mintzo », correction désactivée.
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "gaur mine tso probatu dut"
        harness.flow.vocabularyReplacements = {
            [VocabularyReplacement(heard: "mine tso", replacement: "Mintzo")]
        }

        try await harness.runFullSession()

        XCTAssertEqual(harness.inserter.insertedTexts, ["Gaur Mintzo probatu dut"])
        // L'historique garde le brut moteur ET le texte livré.
        XCTAssertEqual(harness.history.records.first?.texteBrut, "gaur mine tso probatu dut")
        XCTAssertEqual(harness.history.records.first?.texteCorrige, "Gaur Mintzo probatu dut")
    }

    func testVocabularyReplacementsApplyAfterCorrection() async throws {
        // Ordre du design : correction PUIS remplacements — la règle matche
        // la sortie du correcteur, pas le brut.
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "gaur mine tso probatu dut"
        harness.flow.makeCorrector = { MockCorrector(output: "Gaur mine tso probatu dut.") }
        harness.flow.vocabularyReplacements = {
            [VocabularyReplacement(heard: "mine tso", replacement: "Mintzo")]
        }

        try await harness.runFullSession()

        XCTAssertEqual(harness.inserter.insertedTexts, ["Gaur Mintzo probatu dut."])
    }

    // MARK: Erreurs capture

    func testCaptureStartFailureEndsSessionWithError() async throws {
        let harness = FlowHarness()
        harness.capture.startError = CaptureError.engineStartFailed("boom")

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.failed(.captureFailed)])
        XCTAssertEqual(harness.flow.phase, .idle)
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
    }

    func testMicrophonePermissionDeniedIsDistinguished() async throws {
        let harness = FlowHarness()
        harness.capture.startError = CaptureError.permissionDenied

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.failed(.microphonePermissionDenied)])
    }

    func testTranscriptionFailureReportsDetail() async throws {
        let harness = FlowHarness()
        harness.transcriber.errorToThrow = TranscriptionServiceError.noModelInstalled(language: "eu")

        try await harness.runFullSession()

        guard case .failed(.transcriptionFailed(let detail))? = harness.outcomes.first else {
            return XCTFail("outcome attendu : failed(transcriptionFailed), reçu \(harness.outcomes)")
        }
        XCTAssertTrue(detail.contains("eu"))
        XCTAssertTrue(harness.history.records.isEmpty)
    }

    // MARK: Annulation

    func testEscapeDuringListeningAbortsCleanly() async throws {
        let harness = FlowHarness()

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.cancel()
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }
        try await harness.waitUntil("capture arrêtée") { harness.capture.stopCallCount == 1 }

        XCTAssertEqual(harness.outcomes, [.cancelled])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
        XCTAssertEqual(harness.flow.phase, .idle)
    }

    /// Croix / Échap PENDANT la transcription (retour client) : abort propre,
    /// aucun texte inséré, rien d'historisé, aucun outcome parasite quand le
    /// moteur finit dans son coin.
    func testCancelDuringTranscriptionInsertsNothing() async throws {
        let harness = FlowHarness()
        harness.transcriber.delay = .milliseconds(400)

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("transcription en cours") { harness.flow.phase == .transcribing }

        harness.flow.cancel()

        XCTAssertEqual(harness.flow.phase, .idle, "Sortie immédiate, pas d'attente du moteur")
        XCTAssertEqual(harness.outcomes, [.cancelled])
        // Le moteur mocké termine sa course (400 ms) : son résultat est jeté.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
        XCTAssertEqual(harness.outcomes, [.cancelled], "Aucun outcome après l'annulation")
    }

    /// Croix / Échap PENDANT la correction : le texte brut existe déjà mais ne
    /// doit NI être inséré NI être historisé.
    func testCancelDuringCorrectionInsertsNothing() async throws {
        let harness = FlowHarness()
        harness.flow.makeCorrector = { MockCorrector(output: "zuzenduta", delay: .milliseconds(400)) }

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("correction en cours") { harness.flow.phase == .correcting }

        harness.flow.cancel()

        XCTAssertEqual(harness.flow.phase, .idle)
        XCTAssertEqual(harness.outcomes, [.cancelled])
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
        XCTAssertEqual(harness.outcomes, [.cancelled], "Aucun outcome après l'annulation")
    }

    /// Une nouvelle dictée reste possible immédiatement après une annulation
    /// en cours de traitement (pas d'état fantôme).
    func testNewSessionAfterCancelDuringProcessing() async throws {
        let harness = FlowHarness()
        harness.transcriber.delay = .milliseconds(300)

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("transcription en cours") { harness.flow.phase == .transcribing }
        harness.flow.cancel()

        harness.transcriber.delay = .zero
        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("2e écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("2e outcome émis") { harness.outcomes.count == 2 }

        XCTAssertEqual(harness.outcomes, [.cancelled, .inserted])
        XCTAssertEqual(harness.inserter.insertedTexts, ["Kaixo mundua"])
        XCTAssertEqual(harness.history.records.count, 1)
    }

    func testTooShortSessionIsCancelledNotFailed() async throws {
        let harness = FlowHarness()
        harness.capture.samplesToReturn = Array(repeating: 0, count: 100) // < 0,25 s

        try await harness.runFullSession()

        XCTAssertEqual(harness.outcomes, [.cancelled])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
    }

    func testEmptyTranscriptionIsCancelledNotInserted() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "   "

        try await harness.runFullSession()

        XCTAssertEqual(harness.outcomes, [.cancelled])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
    }

    // MARK: Toggle et double événements

    func testToggleStartsThenStopsSession() async throws {
        let harness = FlowHarness()

        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.inserted])
    }

    /// Mode appui simple : Échap / croix annulent une session ouverte au
    /// toggle (inchangé), et l'appui SUIVANT rouvre une session propre.
    func testToggleSessionCancelledThenRestartsCleanly() async throws {
        let harness = FlowHarness()

        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.cancel()
        try await harness.waitUntil("annulation émise") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.cancelled])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertEqual(harness.flow.phase, .idle)

        // Nouveau cycle toggle complet après l'annulation.
        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("écoute redémarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("outcome final") { harness.outcomes.count == 2 }

        XCTAssertEqual(harness.outcomes, [.cancelled, .inserted])
    }

    func testEventsDuringProcessingAreIgnored() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "kaixo"
        harness.flow.makeCorrector = { MockCorrector(output: "kaixo", delay: .milliseconds(200)) }

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .fixed(.basque))
        try await harness.waitUntil("correction en cours") { harness.flow.phase == .correcting }
        // Pendant le traitement : press/toggle ignorés, pas de deuxième session.
        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        harness.flow.handle(.toggled, selection: .fixed(.basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes.count, 1)
        XCTAssertEqual(harness.capture.startCallCount, 1)
    }

    // MARK: Mode auto (§4.4 — détection eu/fr)

    func testAutoSessionDetectsLanguageLiveAndRoutesTranscription() async throws {
        // 3 s de flux micro accumulées → détection « fr » sûre → badge notifié
        // PENDANT l'écoute, transcription et historique routés sur fr.
        let harness = FlowHarness()
        harness.detector.detection = LanguageDetection(language: "fr", confidence: 0.92)
        harness.transcriber.textToReturn = "bonjour tout le monde"

        harness.flow.handle(.pressBegan, selection: .auto(fallback: .basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        // Fenêtre de détection remplie en 3 chunks (16 000 échantillons chacun).
        for _ in 0..<3 {
            harness.capture.emit(rms: 0.3, samples: Array(repeating: 0.1, count: 16_000))
        }
        try await harness.waitUntil("langue détectée pendant l'écoute") {
            !harness.detectedLanguages.isEmpty
        }
        XCTAssertEqual(harness.detectedLanguages, [.french], "badge « a→ » → fr en Gorri")

        harness.flow.handle(.pressEnded, selection: .auto(fallback: .basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.inserted])
        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(harness.history.records.first?.langue, .fr,
                       "l'historique enregistre la langue DÉTECTÉE")
        XCTAssertEqual(harness.detector.detectCallCount, 1, "une seule détection par session")
    }

    func testAutoSessionShorterThanWindowDetectsAtStop() async throws {
        // Session plus courte que la fenêtre de 3 s : pas de verdict live —
        // tentative unique sur l'audio complet au stop.
        let harness = FlowHarness()
        harness.detector.detection = LanguageDetection(language: "eu", confidence: 0.88)
        harness.transcriber.textToReturn = "egun on"

        try await harness.runFullSession(selection: .auto(fallback: .french))

        XCTAssertEqual(harness.transcriber.lastLanguage, "eu")
        XCTAssertEqual(harness.history.records.first?.langue, .eu)
        XCTAssertEqual(harness.detector.detectCallCount, 1)
        XCTAssertTrue(harness.detectedLanguages.isEmpty,
                      "pas de feedback badge après le stop (HUD déjà en transcription)")
    }

    func testAutoLowConfidenceFallsBackToUserDefaultLanguage() async throws {
        // Détection hésitante (< seuil) → langue de repli de l'utilisateur.
        let harness = FlowHarness()
        harness.detector.detection = LanguageDetection(language: "fr", confidence: 0.51)

        try await harness.runFullSession(selection: .auto(fallback: .basque))

        XCTAssertEqual(harness.outcomes, [.inserted], "jamais d'erreur pour une hésitation")
        XCTAssertEqual(harness.transcriber.lastLanguage, "eu")
        XCTAssertEqual(harness.history.records.first?.langue, .eu)
        XCTAssertTrue(harness.detectedLanguages.isEmpty, "verdict hésitant : badge inchangé")
    }

    func testAutoDetectionUnavailableFallsBackWithoutBlocking() async throws {
        // Modèle de détection absent (téléchargement silencieux côté service) :
        // la session continue sur la langue de repli, aucune erreur.
        let harness = FlowHarness()
        harness.detector.available = false
        harness.detector.detection = LanguageDetection(language: "fr", confidence: 0.99)

        try await harness.runFullSession(selection: .auto(fallback: .basque))

        XCTAssertEqual(harness.outcomes, [.inserted])
        XCTAssertEqual(harness.transcriber.lastLanguage, "eu")
        XCTAssertEqual(harness.detector.detectCallCount, 0,
                       "détection jamais tentée sans modèle")
        XCTAssertEqual(harness.detector.availabilityCallCount, 2,
                       "disponibilité sondée au démarrage ET re-sondée au stop (download éventuel fini)")
    }

    func testAutoDetectedLanguageWithMissingModelFallsBack() async throws {
        // fr détecté mais whisper-fr absent du disque → repli eu, jamais
        // d'erreur en fin de session (le modèle plancher a été vérifié avant).
        let harness = FlowHarness(missingLanguages: [.french])
        harness.detector.detection = LanguageDetection(language: "fr", confidence: 0.95)

        try await harness.runFullSession(selection: .auto(fallback: .basque))

        XCTAssertEqual(harness.outcomes, [.inserted])
        XCTAssertEqual(harness.transcriber.lastLanguage, "eu")
        XCTAssertEqual(harness.history.records.first?.langue, .eu)
    }

    func testAutoFallbackModelMissingFailsBeforeOpeningMicrophone() async throws {
        // Le modèle PLANCHER (repli) manque : erreur avant le micro, comme en
        // langue fixe — le mode auto n'ouvre jamais le micro à l'aveugle.
        let harness = FlowHarness(missingLanguages: [.basque])

        harness.flow.handle(.pressBegan, selection: .auto(fallback: .basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.failed(.modelMissing(.basque))])
        XCTAssertEqual(harness.capture.startCallCount, 0)
    }

    func testStopTimeSelectionSwitchedToAutoTriggersDetection() async throws {
        // Badge cyclé vers auto EN COURS de dictée : la sélection au STOP fait
        // foi (même règle que eu↔fr) — détection au stop, routage détecté.
        let harness = FlowHarness()
        harness.detector.detection = LanguageDetection(language: "fr", confidence: 0.9)
        harness.transcriber.textToReturn = "bonjour"

        harness.flow.handle(.pressBegan, selection: .fixed(.basque))
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, selection: .auto(fallback: .basque))
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(harness.history.records.first?.langue, .fr)
    }

    // MARK: Insertion dégradée / clipboard

    func testClipboardOnlyFallbackStillRecordsHistory() async throws {
        let harness = FlowHarness()
        harness.inserter.resultToReturn = .clipboardOnly(reason: .secureInputActive)

        try await harness.runFullSession()

        XCTAssertEqual(harness.outcomes, [.clipboardOnly])
        XCTAssertEqual(harness.history.records.count, 1, "le texte ne doit jamais être perdu")
    }

    func testManualClipboardModeSkipsInsertion() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "kaixo mundua"
        harness.flow.autoInsertEnabled = { false }
        var clipboard: [String] = []
        harness.flow.writeClipboard = { clipboard.append($0) }

        try await harness.runFullSession()

        XCTAssertEqual(harness.outcomes, [.clipboardOnly])
        XCTAssertEqual(clipboard, ["Kaixo mundua"])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertEqual(harness.history.records.count, 1)
    }

    // MARK: Post-processing

    func testPostProcessTrimsAndCapitalizes() {
        XCTAssertEqual(DictationFlow.postProcess("  egun on  "), "Egun on")
        XCTAssertEqual(DictationFlow.postProcess("Déjà majuscule"), "Déjà majuscule")
        XCTAssertEqual(DictationFlow.postProcess("état des lieux"), "État des lieux")
        XCTAssertEqual(DictationFlow.postProcess(""), "")
        XCTAssertEqual(DictationFlow.postProcess("1 heure"), "1 heure")
    }
}
