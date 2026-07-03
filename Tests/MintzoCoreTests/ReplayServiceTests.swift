import XCTest
@testable import MintzoCore

// Tests de la relance (ReplayService.swift, compilé ici via symlink) avec un
// transcripteur stub : mise à jour EN PLACE, routage de langue, pipeline
// correction + vocabulaire + post-processing, erreurs sobres.

// MARK: - Stubs

/// Transcripteur stub : texte programmable, erreur simulable, langue détectée
/// rapportée quand la demande est « auto » (language nil).
private final class StubTranscriber: DictationTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var _text = "esaldi berria"
    private var _detectedLanguage: String? = "eu"
    private var _error: (any Error)?
    private var _lastLanguage: String??
    private var _lastSampleCount: Int?

    var text: String {
        get { lock.lock(); defer { lock.unlock() }; return _text }
        set { lock.lock(); defer { lock.unlock() }; _text = newValue }
    }
    var detectedLanguage: String? {
        get { lock.lock(); defer { lock.unlock() }; return _detectedLanguage }
        set { lock.lock(); defer { lock.unlock() }; _detectedLanguage = newValue }
    }
    var error: (any Error)? {
        get { lock.lock(); defer { lock.unlock() }; return _error }
        set { lock.lock(); defer { lock.unlock() }; _error = newValue }
    }
    /// Langue reçue au dernier appel (nil externe = jamais appelé).
    var lastLanguage: String?? { lock.lock(); defer { lock.unlock() }; return _lastLanguage }
    var lastSampleCount: Int? { lock.lock(); defer { lock.unlock() }; return _lastSampleCount }

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        let (error, text, detected) = consume(language: language, sampleCount: samples.count)
        if let error { throw error }
        return TranscriptionResult(
            text: text,
            language: language ?? detected,
            modelID: "whisper-stub",
            audioDuration: Double(samples.count) / 16_000,
            processingDuration: 0.01
        )
    }

    // NSLock est interdit dans un contexte async (Swift 6) : section
    // critique dans un helper SYNCHRONE (même pattern que MockDetector).
    private func consume(language: String?, sampleCount: Int) -> ((any Error)?, String, String?) {
        lock.lock(); defer { lock.unlock() }
        _lastLanguage = language
        _lastSampleCount = sampleCount
        return (_error, _text, _detectedLanguage)
    }
}

private struct StubCorrector: DictationCorrecting {
    var transform: @Sendable (String) -> String

    func correct(_ text: String, language: Language) async -> CorrectionResult {
        CorrectionResult(text: transform(text), outcome: .corrected)
    }
}

// MARK: - Harnais

@MainActor
private struct ReplayHarness {
    let transcriber = StubTranscriber()
    let history: HistoryStore
    let service: ReplayService

    init() throws {
        history = try HistoryStore.inMemory()
        service = ReplayService(transcriber: transcriber, history: history)
        // Décodage stub par défaut : une seconde de « signal » — les tests
        // qui veulent l'échec du décodage le remplacent.
        service.decode = { _ in Array(repeating: 0.1, count: 16_000) }
    }

    /// Entrée d'historique avec audio conservé, insérée en base.
    func insertEntry(
        texteBrut: String = "testu zaharra",
        texteCorrige: String? = "Testu zaharra, zuzendua.",
        langue: Transcription.Langue = .eu,
        audioPath: String? = "/tmp/mintzo-replay-test/session.wav"
    ) throws -> Transcription {
        try history.insert(Transcription(
            texteBrut: texteBrut,
            texteCorrige: texteCorrige,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            dureeAudio: 12,
            langue: langue,
            source: .dictee,
            audioPath: audioPath
        ))
    }
}

// MARK: - Tests

@MainActor
final class ReplayServiceTests: XCTestCase {

    // MARK: Mise à jour en place

    func testReplayRewritesEntryInPlaceAndKeepsIdentity() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.text = "  esaldi berria eta hobea  "

        let result = await harness.service.replay(entry, language: .basque)
        let updated = try XCTUnwrap(try? result.get())

        // Mêmes conventions que la dictée : texteBrut = sortie moteur trimée,
        // texteCorrige = texte final s'il diffère (ici la majuscule initiale
        // du post-processing déterministe).
        XCTAssertEqual(updated.texteBrut, "esaldi berria eta hobea")
        XCTAssertEqual(updated.texteCorrige, "Esaldi berria eta hobea")
        XCTAssertEqual(updated.langue, .eu)
        // Identité conservée : id, date, durée, source, audio.
        XCTAssertEqual(updated.id, entry.id)
        XCTAssertEqual(updated.date, entry.date)
        XCTAssertEqual(updated.dureeAudio, entry.dureeAudio)
        XCTAssertEqual(updated.source, entry.source)
        XCTAssertEqual(updated.audioPath, entry.audioPath)

        // La BASE est mise à jour en place — pas seulement la valeur rendue.
        let stored = try XCTUnwrap(harness.history.fetch(id: XCTUnwrap(entry.id)))
        XCTAssertEqual(stored.texteBrut, "esaldi berria eta hobea")
        XCTAssertEqual(stored.texteCorrige, "Esaldi berria eta hobea")
        XCTAssertEqual(stored.audioPath, entry.audioPath)
        XCTAssertEqual(try harness.history.fetchAll().count, 1, "aucune entrée dupliquée")
    }

    func testReplayWithNothingToCorrectStoresNilCorrige() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        // Sortie moteur déjà propre : le texte final EST le brut → corrigé nil.
        harness.transcriber.text = "Esaldi garbia."

        let result = await harness.service.replay(entry, language: .basque)
        let updated = try XCTUnwrap(try? result.get())

        XCTAssertEqual(updated.texteBrut, "Esaldi garbia.")
        XCTAssertNil(updated.texteCorrige)
        XCTAssertNil(try XCTUnwrap(harness.history.fetch(id: XCTUnwrap(entry.id))).texteCorrige)
    }

    func testReplayWithCorrectorStoresBothRawAndCorrected() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.text = "kaixo mundua"
        harness.service.makeCorrector = { StubCorrector(transform: { "\($0), zuzenduta" }) }

        let result = await harness.service.replay(entry, language: .basque)
        let updated = try XCTUnwrap(try? result.get())

        XCTAssertEqual(updated.texteBrut, "kaixo mundua")
        XCTAssertEqual(updated.texteCorrige, "Kaixo mundua, zuzenduta")
        let stored = try XCTUnwrap(harness.history.fetch(id: XCTUnwrap(entry.id)))
        XCTAssertEqual(stored.texteCorrige, "Kaixo mundua, zuzenduta")
    }

    func testReplayAppliesVocabularyPostPassAfterCorrection() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.text = "bidali mezua bit huip taldeari"
        harness.service.vocabularyReplacements = {
            [VocabularyReplacement(heard: "bit huip", replacement: "Bitwip")]
        }

        let result = await harness.service.replay(entry, language: .basque)
        let updated = try XCTUnwrap(try? result.get())

        XCTAssertEqual(updated.texteCorrige, "Bidali mezua Bitwip taldeari")
        XCTAssertEqual(updated.texteBrut, "bidali mezua bit huip taldeari")
    }

    // MARK: Routage de langue

    func testReplayFixedFrenchPassesLanguageAndUpdatesTag() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry(langue: .eu)
        harness.transcriber.text = "le devis part ce soir"

        let result = await harness.service.replay(entry, language: .french)
        let updated = try XCTUnwrap(try? result.get())

        XCTAssertEqual(harness.transcriber.lastLanguage, "fr")
        XCTAssertEqual(updated.langue, .fr)
        XCTAssertEqual(try harness.history.fetch(id: XCTUnwrap(entry.id))?.langue, .fr)
    }

    func testReplayAutoUsesDetectedLanguage() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry(langue: .eu)
        harness.transcriber.text = "bonjour tout le monde"
        harness.transcriber.detectedLanguage = "fr"

        let result = await harness.service.replay(entry, language: nil)
        let updated = try XCTUnwrap(try? result.get())

        // Auto : la demande part sans langue, le service détecte.
        XCTAssertEqual(harness.transcriber.lastLanguage, .some(nil))
        XCTAssertEqual(updated.langue, .fr)
    }

    func testReplayAutoWithoutDetectionKeepsEntryLanguage() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry(langue: .fr)
        harness.transcriber.detectedLanguage = nil

        let result = await harness.service.replay(entry, language: nil)
        let updated = try XCTUnwrap(try? result.get())

        XCTAssertEqual(updated.langue, .fr, "sans verdict, l'entrée garde sa langue")
    }

    // MARK: Erreurs sobres — l'entrée n'est JAMAIS modifiée sur échec

    private func assertEntryUntouched(
        _ harness: ReplayHarness, _ entry: Transcription,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let stored = try XCTUnwrap(harness.history.fetch(id: XCTUnwrap(entry.id)))
        XCTAssertEqual(stored, entry, "l'entrée ne doit pas bouger sur échec", file: file, line: line)
    }

    func testReplayWithoutAudioFailsWithNoAudio() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry(audioPath: nil)

        let result = await harness.service.replay(entry, language: nil)

        XCTAssertEqual(result, .failure(.noAudio))
        try assertEntryUntouched(harness, entry)
    }

    func testReplayUnreadableAudioFailsWithAudioUnreadable() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.service.decode = { url in
            throw AudioDecodingError.fileNotFound(path: url.path)
        }

        let result = await harness.service.replay(entry, language: .basque)

        XCTAssertEqual(result, .failure(.audioUnreadable))
        try assertEntryUntouched(harness, entry)
    }

    func testReplayModelMissingFailsSoberly() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.error = TranscriptionServiceError.noModelInstalled(language: "eu")

        let result = await harness.service.replay(entry, language: .basque)

        XCTAssertEqual(result, .failure(.modelMissing))
        try assertEntryUntouched(harness, entry)
    }

    func testReplayEngineErrorFailsWithTranscriptionFailed() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.error = TranscriptionServiceError.modelLoadFailed(
            modelID: "whisper-eu", detail: "corrompu"
        )

        let result = await harness.service.replay(entry, language: .basque)

        XCTAssertEqual(result, .failure(.transcriptionFailed))
        try assertEntryUntouched(harness, entry)
    }

    func testReplayEmptyTranscriptFailsWithNoText() async throws {
        let harness = try ReplayHarness()
        let entry = try harness.insertEntry()
        harness.transcriber.text = "   \n  "

        let result = await harness.service.replay(entry, language: .basque)

        XCTAssertEqual(result, .failure(.noText))
        try assertEntryUntouched(harness, entry)
    }
}
