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

    func emit(rms: Float) {
        continuation?.yield(CaptureChunk(samples: [], rms: rms))
    }
}

@MainActor
private final class MockTranscriber: DictationTranscribing {
    var textToReturn = "kaixo mundua"
    var errorToThrow: (any Error)?
    private(set) var lastLanguage: String??
    private(set) var lastSampleCount: Int?

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        lastLanguage = language
        lastSampleCount = samples.count
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
    func isModelInstalled(for language: Language) async -> Bool { installed }
}

// MARK: - Harnais

@MainActor
private struct FlowHarness {
    let capture = MockCapture()
    let transcriber = MockTranscriber()
    let inserter = MockInserter()
    let history = MockHistory()
    let flow: DictationFlow

    private final class EventLog {
        var outcomes: [DictationFlow.Outcome] = []
        var phases: [DictationFlow.Phase] = []
    }
    private let log = EventLog()

    var outcomes: [DictationFlow.Outcome] { log.outcomes }
    var phases: [DictationFlow.Phase] { log.phases }

    init(modelsInstalled: Bool = true) {
        flow = DictationFlow(
            capture: capture,
            transcriber: transcriber,
            inserter: inserter,
            history: history,
            models: MockModels(installed: modelsInstalled)
        )
        let log = self.log
        flow.onOutcome = { log.outcomes.append($0) }
        flow.onPhaseChange = { log.phases.append($0) }
    }

    /// Dictée complète : press → écoute effective → release → outcome.
    func runFullSession(language: Language = .basque) async throws {
        flow.handle(.pressBegan, language: language)
        try await waitUntil("écoute démarrée") { flow.phase == .listening }
        flow.handle(.pressEnded, language: language)
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

        harness.flow.handle(.pressBegan, language: .basque)
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, language: .french)
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(harness.history.records.first?.langue, .fr)
    }

    func testRMSChunksAreForwardedWhileListening() async throws {
        let harness = FlowHarness()
        var levels: [Float] = []
        harness.flow.onLevel = { levels.append($0) }

        harness.flow.handle(.pressBegan, language: .basque)
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.capture.emit(rms: 0.25)
        harness.capture.emit(rms: 0.5)
        try await harness.waitUntil("niveaux reçus") { levels.count == 2 }

        XCTAssertEqual(levels, [0.25, 0.5])
        harness.flow.handle(.pressEnded, language: .basque)
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }
    }

    // MARK: Modèle manquant

    func testMissingModelFailsBeforeOpeningMicrophone() async throws {
        let harness = FlowHarness(modelsInstalled: false)

        harness.flow.handle(.pressBegan, language: .basque)
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

    // MARK: Erreurs capture

    func testCaptureStartFailureEndsSessionWithError() async throws {
        let harness = FlowHarness()
        harness.capture.startError = CaptureError.engineStartFailed("boom")

        harness.flow.handle(.pressBegan, language: .basque)
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.failed(.captureFailed)])
        XCTAssertEqual(harness.flow.phase, .idle)
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
    }

    func testMicrophonePermissionDeniedIsDistinguished() async throws {
        let harness = FlowHarness()
        harness.capture.startError = CaptureError.permissionDenied

        harness.flow.handle(.pressBegan, language: .basque)
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

        harness.flow.handle(.pressBegan, language: .basque)
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.cancel()
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }
        try await harness.waitUntil("capture arrêtée") { harness.capture.stopCallCount == 1 }

        XCTAssertEqual(harness.outcomes, [.cancelled])
        XCTAssertTrue(harness.inserter.insertedTexts.isEmpty)
        XCTAssertTrue(harness.history.records.isEmpty)
        XCTAssertEqual(harness.flow.phase, .idle)
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

        harness.flow.handle(.toggled, language: .basque)
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.toggled, language: .basque)
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes, [.inserted])
    }

    func testEventsDuringProcessingAreIgnored() async throws {
        let harness = FlowHarness()
        harness.transcriber.textToReturn = "kaixo"
        harness.flow.makeCorrector = { MockCorrector(output: "kaixo", delay: .milliseconds(200)) }

        harness.flow.handle(.pressBegan, language: .basque)
        try await harness.waitUntil("écoute démarrée") { harness.flow.phase == .listening }
        harness.flow.handle(.pressEnded, language: .basque)
        try await harness.waitUntil("correction en cours") { harness.flow.phase == .correcting }
        // Pendant le traitement : press/toggle ignorés, pas de deuxième session.
        harness.flow.handle(.pressBegan, language: .basque)
        harness.flow.handle(.toggled, language: .basque)
        try await harness.waitUntil("outcome émis") { !harness.outcomes.isEmpty }

        XCTAssertEqual(harness.outcomes.count, 1)
        XCTAssertEqual(harness.capture.startCallCount, 1)
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
