import XCTest
@testable import MintzoCore

/// CRUD + persistance JSON du dictionnaire personnalisé.
@MainActor
final class VocabularyStoreTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-vocab-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("vocabulary.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    // MARK: - Mots

    func testAddWordTrimsAndPersists() throws {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.addWord("  Bitwip  "))
        XCTAssertEqual(store.words, ["Bitwip"])

        // Le JSON est écrit immédiatement et contient le mot.
        let data = try Data(contentsOf: fileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("Bitwip"))
    }

    func testAddWordRejectsEmptyAndBlank() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertFalse(store.addWord(""))
        XCTAssertFalse(store.addWord("   "))
        XCTAssertTrue(store.words.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "Aucune mutation : rien ne doit être écrit")
    }

    func testAddWordRejectsCaseInsensitiveDuplicate() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.addWord("Maite"))
        XCTAssertFalse(store.addWord("maite"))
        XCTAssertFalse(store.addWord("MAITE "))
        XCTAssertEqual(store.words, ["Maite"])
    }

    func testRemoveWordPersists() {
        let store = VocabularyStore(fileURL: fileURL)
        store.addWord("Bitwip")
        store.addWord("Donostia")
        store.removeWord("Bitwip")
        XCTAssertEqual(store.words, ["Donostia"])

        let reloaded = VocabularyStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.words, ["Donostia"])
    }

    // MARK: - Remplacements

    func testAddReplacementTrimsAndPersists() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.addReplacement(heard: " mine tso ", replacement: " Mintzo "))
        XCTAssertEqual(store.replacements.count, 1)
        XCTAssertEqual(store.replacements[0].heard, "mine tso")
        XCTAssertEqual(store.replacements[0].replacement, "Mintzo")
    }

    func testAddReplacementRejectsEmptySides() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertFalse(store.addReplacement(heard: "", replacement: "Mintzo"),
                       "« entendu » vide interdit")
        XCTAssertFalse(store.addReplacement(heard: "mine tso", replacement: "  "),
                       "cible vide interdite — un remplacement ne doit jamais effacer du texte")
        XCTAssertTrue(store.replacements.isEmpty)
    }

    func testAddReplacementRejectsDuplicateHeard() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.addReplacement(heard: "mine tso", replacement: "Mintzo"))
        XCTAssertFalse(store.addReplacement(heard: "Mine Tso", replacement: "Autre"))
        XCTAssertEqual(store.replacements.count, 1)
    }

    func testRemoveReplacementByID() {
        let store = VocabularyStore(fileURL: fileURL)
        store.addReplacement(heard: "mine tso", replacement: "Mintzo")
        store.addReplacement(heard: "bite ouipe", replacement: "Bitwip")
        let id = store.replacements[0].id
        store.removeReplacement(id: id)
        XCTAssertEqual(store.replacements.map(\.heard), ["bite ouipe"])

        let reloaded = VocabularyStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.replacements.map(\.heard), ["bite ouipe"])
    }

    // MARK: - Persistance (rechargement, robustesse)

    func testFullRoundTripAcrossInstances() {
        let store = VocabularyStore(fileURL: fileURL)
        store.addWord("Bitwip")
        store.addWord("Maite")
        store.addReplacement(heard: "mine tso", replacement: "Mintzo")

        let reloaded = VocabularyStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.words, ["Bitwip", "Maite"])
        XCTAssertEqual(reloaded.replacements.map(\.heard), ["mine tso"])
        XCTAssertEqual(reloaded.replacements.map(\.replacement), ["Mintzo"])
        XCTAssertEqual(reloaded.replacements.map(\.id), store.replacements.map(\.id),
                       "Les identifiants doivent survivre au rechargement")
    }

    func testMissingFileStartsEmpty() {
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.words.isEmpty)
        XCTAssertTrue(store.replacements.isEmpty)
    }

    func testCorruptedFileStartsEmptyWithoutCrash() throws {
        try Data("{pas du json".utf8).write(to: fileURL)
        let store = VocabularyStore(fileURL: fileURL)
        XCTAssertTrue(store.words.isEmpty)
        XCTAssertTrue(store.replacements.isEmpty)
        // Et le store reste fonctionnel (une mutation réécrit un fichier sain).
        XCTAssertTrue(store.addWord("Bitwip"))
        XCTAssertEqual(VocabularyStore(fileURL: fileURL).words, ["Bitwip"])
    }
}
