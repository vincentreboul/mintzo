import XCTest
@testable import MintzoCore

/// Bout-en-bout RÉEL de la réécoute/relance, sans mock moteur :
///
/// 1. dictée (harnais : capture mock qui rend les échantillons de la fixture
///    française, moteur whisper RÉEL ggml-tiny) → `DictationFlow` écrit le
///    WAV conservé et historise l'entrée avec son `audioPath` ;
/// 2. le WAV sur disque est re-décodable (même chemin que la relance) ;
/// 3. relance « euskara » via `ReplayService` (vrai moteur, vrai store sur
///    disque) → textes remplacés EN PLACE, langue eu, identité conservée.
///
/// Tout est isolé en répertoires temporaires — AUCUN contact avec ~/Library.
/// Modèle absent → skip (lancer scripts/download-test-model.sh).
@MainActor
final class ReplayEndToEndTests: XCTestCase {

    // MARK: - Fixtures

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MintzoCoreTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // racine du repo

    private static let modelURL = repoRoot
        .appendingPathComponent("Models")
        .appendingPathComponent("ggml-tiny.bin")

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-replay-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    // MARK: - Adaptateurs réels/minimaux

    /// Transcripteur RÉEL sur ggml-tiny — même contrat que TranscriptionService
    /// (le service complet exige un ModelManager pointé sur ~/Library, interdit ici).
    private final class TinyTranscriber: DictationTranscribing, @unchecked Sendable {
        private let engine: WhisperEngine

        init(modelPath: URL) throws {
            engine = try WhisperEngine(modelPath: modelPath)
        }

        func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
            let text = try await engine.transcribe(samples: samples, language: language)
            return TranscriptionResult(
                text: text,
                language: language,
                modelID: "ggml-tiny",
                audioDuration: Double(samples.count) / 16_000,
                processingDuration: 0
            )
        }
    }

    /// Capture harnais : rend les échantillons injectés au stop.
    private final class HarnessCapture: DictationCapturing, @unchecked Sendable {
        private let samples: [Float]
        private let lock = NSLock()
        private var continuation: AsyncStream<CaptureChunk>.Continuation?

        init(samples: [Float]) { self.samples = samples }

        func start() async throws -> AsyncStream<CaptureChunk> {
            let (stream, continuation) = AsyncStream.makeStream(of: CaptureChunk.self)
            store(continuation)
            return stream
        }

        func stop() async -> [Float] {
            store(nil)
            return samples
        }

        // NSLock interdit en contexte async (Swift 6) : helper synchrone.
        private func store(_ new: AsyncStream<CaptureChunk>.Continuation?) {
            lock.lock(); defer { lock.unlock() }
            continuation?.finish()
            continuation = new
        }
    }

    @MainActor
    private final class SpyInserter: DictationInserting {
        private(set) var insertedTexts: [String] = []
        func insert(_ text: String) async -> InsertionResult {
            insertedTexts.append(text)
            return .inserted
        }
    }

    private struct AlwaysInstalled: DictationModelChecking {
        func isModelInstalled(for language: Language) async -> Bool { true }
    }

    private struct NoDetection: DictationLanguageDetecting {
        func isDetectionAvailable() async -> Bool { false }
        func detect(samples: [Float]) async throws -> LanguageDetection {
            throw TranscriptionServiceError.noModelInstalled(language: "tiny")
        }
    }

    // MARK: - Scénario

    func testDictationPersistsWavThenReplayInBasqueUpdatesEntryInPlace() async throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else {
            throw XCTSkip(
                "Modèle absent (\(Self.modelURL.path)) — lancer scripts/download-test-model.sh"
            )
        }

        // Fixture audio réelle (français, ~3,5 s, déjà 16 kHz mono).
        let bundle = Bundle(for: Self.self)
        let wavURL = try XCTUnwrap(
            bundle.url(forResource: "bonjour-16k", withExtension: "wav"),
            "Fixture bonjour-16k.wav absente du bundle de test"
        )
        let fixtureSamples = try AudioFileDecoder.decode(url: wavURL)
        XCTAssertGreaterThan(fixtureSamples.count, 16_000)

        // Stores RÉELS, sur disque, isolés dans le répertoire temporaire.
        let history = try HistoryStore(path: workDirectory.appendingPathComponent("history.sqlite").path)
        let audioStore = TranscriptionAudioStore(
            directory: workDirectory.appendingPathComponent("Audio", isDirectory: true)
        )
        let transcriber = try TinyTranscriber(modelPath: Self.modelURL)
        let inserter = SpyInserter()

        // ── 1. Dictée harnais : capture mock → moteur réel → WAV + historique.
        let flow = DictationFlow(
            capture: HarnessCapture(samples: fixtureSamples),
            transcriber: transcriber,
            inserter: inserter,
            history: history,
            models: AlwaysInstalled(),
            detector: NoDetection()
        )
        flow.persistAudio = { samples in
            (try? audioStore.write(samples: samples))?.path
        }
        var outcomes: [DictationFlow.Outcome] = []
        flow.onOutcome = { outcomes.append($0) }

        flow.handle(.pressBegan, selection: .fixed(.french))
        try await waitUntil("écoute démarrée") { flow.phase == .listening }
        flow.handle(.pressEnded, selection: .fixed(.french))
        try await waitUntil("outcome émis", timeout: 120) { !outcomes.isEmpty }

        XCTAssertEqual(outcomes, [.inserted])
        let entry = try XCTUnwrap(try history.fetchAll().first, "l'entrée doit être historisée")
        let entryID = try XCTUnwrap(entry.id)
        XCTAssertEqual(entry.langue, .fr)
        XCTAssertFalse(entry.texteBrut.isEmpty)
        print("E2E-REPLAY 1/3 dictée [fr] → « \(entry.texteAffiche) »")

        // ── 2. WAV conservé : présent sur disque, intègre, re-décodable.
        let audioPath = try XCTUnwrap(entry.audioPath, "l'entrée doit référencer son WAV")
        XCTAssertTrue(audioPath.hasPrefix(workDirectory.path), "audio isolé dans le répertoire injecté")
        let persisted = try AudioFileDecoder.decode(url: URL(fileURLWithPath: audioPath))
        XCTAssertEqual(persisted.count, fixtureSamples.count,
                       "le WAV conservé contient la session complète")
        print("E2E-REPLAY 2/3 wav conservé → \(audioPath) (\(persisted.count) échantillons)")

        // ── 3. Relance « euskara » : vrai moteur, entrée mise à jour en place.
        let replay = ReplayService(transcriber: transcriber, history: history)
        let result = await replay.replay(entry, language: .basque)
        let updated = try XCTUnwrap(try? result.get(), "la relance doit aboutir")

        XCTAssertEqual(updated.id, entryID)
        XCTAssertEqual(updated.langue, .eu)
        XCTAssertFalse(updated.texteBrut.isEmpty)
        XCTAssertEqual(updated.audioPath, audioPath, "l'audio reste réécoutable après relance")

        let stored = try XCTUnwrap(history.fetch(id: entryID))
        XCTAssertEqual(stored.texteBrut, updated.texteBrut, "la base est mise à jour en place")
        XCTAssertEqual(stored.langue, .eu)
        XCTAssertEqual(stored.date.timeIntervalSince1970,
                       entry.date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try history.fetchAll().count, 1, "aucune entrée dupliquée")
        print("E2E-REPLAY 3/3 relance [eu] → « \(stored.texteAffiche) »")
    }

    private func waitUntil(
        _ label: String,
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timeout en attendant : \(label)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
