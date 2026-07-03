import XCTest
@testable import MintzoCore

/// Tests bout-en-bout de `TranscriptionService` avec ggml-tiny :
/// transcription des deux fixtures (wav natif 16 kHz + Ogg Opus), sélection de
/// modèle avec repli, file FIFO, déchargement mémoire.
final class TranscriptionServiceTests: XCTestCase {

    /// Racine du repo, dérivée du chemin de ce fichier source.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let tinySourceURL = repoRoot
        .appendingPathComponent("Models")
        .appendingPathComponent("ggml-tiny.bin")

    private var tempDirectory: URL!
    private var manager: ModelManager!
    private var service: TranscriptionService!

    /// Installe ggml-tiny (déjà téléchargé par scripts/download-test-model.sh)
    /// dans un répertoire modèles éphémère, sous le nom attendu par le catalogue.
    override func setUpWithError() throws {
        guard FileManager.default.fileExists(atPath: Self.tinySourceURL.path) else {
            throw XCTSkip(
                "Modèle absent (\(Self.tinySourceURL.path)) — lancer scripts/download-test-model.sh"
            )
        }
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-transcription-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.tinySourceURL,
            to: tempDirectory.appendingPathComponent(ModelCatalog.whisperTiny.fileName)
        )
        manager = ModelManager(modelsDirectory: tempDirectory)
        service = TranscriptionService(modelManager: manager)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: ext),
            "Fixture \(name).\(ext) absente du bundle de test"
        )
    }

    // MARK: - Bout-en-bout

    /// WAV français → texte non vide, métadonnées cohérentes, repli fr → tiny.
    func testTranscribesWavEndToEnd() async throws {
        let samples = try AudioFileDecoder.decode(url: fixtureURL("bonjour-16k", "wav"))
        let result = try await service.transcribe(samples: samples, language: "fr")

        print("TRANSCRIPTION [wav/fr/\(result.modelID)] → « \(result.text) »")
        XCTAssertFalse(result.text.isEmpty, "Texte vide")
        XCTAssertEqual(result.modelID, ModelCatalog.whisperTiny.id,
                       "whisper-fr absent : repli attendu sur le seul modèle installé")
        XCTAssertEqual(result.language, "fr")
        XCTAssertEqual(result.audioDuration, 3.52, accuracy: 0.1)
        XCTAssertGreaterThan(result.processingDuration, 0)
    }

    /// Ogg Opus (vocal type WhatsApp) → texte non vide.
    func testTranscribesOpusEndToEnd() async throws {
        let samples = try AudioFileDecoder.decode(url: fixtureURL("phrase-fr", "opus"))
        let result = try await service.transcribe(samples: samples, language: "fr")

        print("TRANSCRIPTION [opus/fr/\(result.modelID)] → « \(result.text) »")
        XCTAssertFalse(result.text.isEmpty, "Texte vide")
        XCTAssertEqual(result.audioDuration, 5.81, accuracy: 0.3)
    }

    /// Service câblé avec un dictionnaire non vide : l'amorce whisper est
    /// construite et transmise (initial_prompt réel sur tiny) — transcription
    /// aboutie, non vide, sans erreur.
    @MainActor
    func testTranscribesWithVocabularyWords() async throws {
        let vocabDir = tempDirectory.appendingPathComponent("vocab", isDirectory: true)
        try FileManager.default.createDirectory(at: vocabDir, withIntermediateDirectories: true)
        let store = VocabularyStore(fileURL: vocabDir.appendingPathComponent("vocabulary.json"))
        store.addWord("Bitwip")
        store.addWord("Maite")
        store.addWord("Donostia")
        let vocabService = TranscriptionService(modelManager: manager, vocabulary: store)

        let samples = try AudioFileDecoder.decode(url: fixtureURL("bonjour-16k", "wav"))
        let result = try await vocabService.transcribe(samples: samples, language: "fr")

        print("TRANSCRIPTION [wav/fr + vocabulaire] → « \(result.text) »")
        XCTAssertFalse(result.text.isEmpty, "Texte vide avec amorce de dictionnaire")
    }

    /// Langue « eu » sans whisper-eu installé → repli sur modèle présent, pas d'erreur.
    func testBasqueFallsBackToInstalledModel() async throws {
        let samples = try AudioFileDecoder.decode(url: fixtureURL("bonjour-16k", "wav"))
        let result = try await service.transcribe(samples: samples, language: "eu")
        XCTAssertEqual(result.modelID, ModelCatalog.whisperTiny.id)
    }

    /// Aucun modèle installé → erreur typée .noModelInstalled.
    func testNoModelInstalledThrowsTypedError() async throws {
        let emptyDir = tempDirectory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let bareService = TranscriptionService(modelManager: ModelManager(modelsDirectory: emptyDir))

        do {
            _ = try await bareService.transcribe(samples: [Float](repeating: 0, count: 16_000), language: "fr")
            XCTFail("Une erreur .noModelInstalled était attendue")
        } catch let error as TranscriptionServiceError {
            guard case .noModelInstalled(let language) = error else {
                return XCTFail("Attendu .noModelInstalled, obtenu : \(error)")
            }
            XCTAssertEqual(language, "fr")
        }
    }

    /// unloadAll() libère le moteur ; la transcription suivante recharge et aboutit.
    func testUnloadAllThenLazyReload() async throws {
        let samples = try AudioFileDecoder.decode(url: fixtureURL("bonjour-16k", "wav"))

        let first = try await service.transcribe(samples: samples, language: "fr")
        XCTAssertFalse(first.text.isEmpty)

        await service.unloadAll()

        let second = try await service.transcribe(samples: samples, language: "fr")
        XCTAssertFalse(second.text.isEmpty)
        XCTAssertEqual(first.text, second.text, "Même audio + même modèle ⇒ même texte")
    }

    // MARK: - File FIFO

    /// Deux fichiers enfilés : chaque flux livre queued → started → progress…
    /// → done dans l'ordre, le second est bien positionné DERRIÈRE le premier,
    /// et les deux textes sont non vides.
    func testQueueProcessesTwoFilesInOrder() async throws {
        let wav = try fixtureURL("bonjour-16k", "wav")
        let opus = try fixtureURL("phrase-fr", "opus")

        let stream1 = await service.enqueue(url: wav, language: "fr")
        let stream2 = await service.enqueue(url: opus, language: "fr")

        // Collecte séquentielle : AsyncStream bufferise les événements émis
        // pendant qu'on ne consomme pas — aucun événement perdu.
        let events1 = await collect(stream1)
        let events2 = await collect(stream2)

        try assertOrderedLifecycle(events1, label: "job1")
        try assertOrderedLifecycle(events2, label: "job2")

        // FIFO : job1 en tête, job2 derrière exactement un job.
        guard case .queued(let position1) = events1[0],
              case .queued(let position2) = events2[0] else {
            return XCTFail("Premier événement de chaque flux ≠ .queued")
        }
        XCTAssertEqual(position1, 0, "job1 doit être traité en premier")
        XCTAssertEqual(position2, 1, "job2 doit avoir exactement job1 devant lui")

        // Les deux transcriptions aboutissent avec du texte.
        let text1 = try XCTUnwrap(doneText(events1))
        let text2 = try XCTUnwrap(doneText(events2))
        print("FIFO job1 → « \(text1) »")
        print("FIFO job2 → « \(text2) »")
        XCTAssertFalse(text1.isEmpty)
        XCTAssertFalse(text2.isEmpty)
    }

    /// Fichier illisible en file → .failed avec message parlant, flux terminé proprement.
    func testQueueEmitsFailedForBogusFile() async throws {
        let bogus = tempDirectory.appendingPathComponent("bogus.xyz")
        try Data("pas de l'audio".utf8).write(to: bogus)

        let events = await collect(service.enqueue(url: bogus, language: "fr"))

        guard case .failed(let message)? = events.last else {
            return XCTFail("Dernier événement attendu .failed, obtenu : \(events)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: - Helpers

    private func collect(_ stream: AsyncStream<TranscriptionJobEvent>) async -> [TranscriptionJobEvent] {
        var events: [TranscriptionJobEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    /// Vérifie la séquence queued → started → (progress)* → done.
    private func assertOrderedLifecycle(
        _ events: [TranscriptionJobEvent],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var signature: [String] = []
        for event in events {
            switch event {
            case .queued: signature.append("queued")
            case .started: signature.append("started")
            case .progress: signature.append("progress")
            case .done: signature.append("done")
            case .failed(let message): XCTFail("\(label) a échoué : \(message)", file: file, line: line)
            }
        }
        XCTAssertEqual(signature.first, "queued", "\(label) : doit commencer par queued", file: file, line: line)
        XCTAssertEqual(signature.last, "done", "\(label) : doit finir par done", file: file, line: line)
        let startedIndex = try XCTUnwrap(signature.firstIndex(of: "started"), file: file, line: line)
        XCTAssertEqual(startedIndex, 1, "\(label) : started juste après queued", file: file, line: line)
        XCTAssertTrue(signature.contains("progress"), "\(label) : au moins une phase de progression", file: file, line: line)
    }

    private func doneText(_ events: [TranscriptionJobEvent]) -> String? {
        for event in events {
            if case .done(let result) = event { return result.text }
        }
        return nil
    }
}
