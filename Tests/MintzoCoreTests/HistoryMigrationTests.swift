import XCTest
import GRDB
@testable import MintzoCore

/// Migration v1 → v2 (colonne `audioPath`) et cycle de vie des fichiers audio
/// liés aux entrées (suppression unitaire / totale).
final class HistoryMigrationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-history-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private var databasePath: String {
        directory.appendingPathComponent("history.sqlite").path
    }

    /// Base v1 réelle : le migrateur de production arrêté à "v1", puis des
    /// lignes insérées avec le schéma v1 (sans audioPath).
    private func makeV1Database() throws {
        let queue = try DatabaseQueue(path: databasePath)
        var migrator = HistoryStore.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO transcription
                        (texteBrut, texteCorrige, date, dureeAudio, langue, source, nomFichier)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["kaixo mundua", "Kaixo, mundua.", Date(timeIntervalSince1970: 1_750_000_000),
                            42.0, "eu", "dictee", nil]
            )
            try db.execute(
                sql: """
                    INSERT INTO transcription
                        (texteBrut, texteCorrige, date, dureeAudio, langue, source, nomFichier)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["le devis part ce soir", nil, Date(timeIntervalSince1970: 1_750_000_100),
                            31.0, "fr", "fichier", "bilera.m4a"]
            )
        }
    }

    // MARK: - Migration v1 → v2

    func testOpeningV1DatabaseMigratesToV2WithoutLoss() throws {
        try makeV1Database()

        // Ouverture normale : le migrateur applique v2 sur la base existante.
        let store = try HistoryStore(path: databasePath)
        let all = try store.fetchAll()

        XCTAssertEqual(all.count, 2)
        let fichier = try XCTUnwrap(all.first) // plus récent d'abord
        XCTAssertEqual(fichier.texteBrut, "le devis part ce soir")
        XCTAssertEqual(fichier.langue, .fr)
        XCTAssertEqual(fichier.source, .fichier)
        XCTAssertEqual(fichier.nomFichier, "bilera.m4a")
        XCTAssertNil(fichier.audioPath, "une entrée v1 n'a pas d'audio")

        let dictee = try XCTUnwrap(all.last)
        XCTAssertEqual(dictee.texteBrut, "kaixo mundua")
        XCTAssertEqual(dictee.texteCorrige, "Kaixo, mundua.")
        XCTAssertEqual(dictee.dureeAudio, 42.0)
        XCTAssertNil(dictee.audioPath)
    }

    func testV2KeepsSearchWorkingOnV1Rows() throws {
        try makeV1Database()
        let store = try HistoryStore(path: databasePath)
        // La table FTS v1 (triggers) doit survivre à l'ALTER TABLE de v2.
        XCTAssertEqual(try store.search(query: "kaixo").count, 1)
        XCTAssertEqual(try store.search(query: "devis").count, 1)
    }

    func testV2AcceptsInsertWithAudioPathAndRoundTrips() throws {
        try makeV1Database()
        let store = try HistoryStore(path: databasePath)

        let inserted = try store.insert(Transcription(
            texteBrut: "audio gordeta",
            dureeAudio: 3,
            langue: .eu,
            source: .dictee,
            audioPath: "/tmp/mintzo-test/abc.wav"
        ))
        let fetched = try XCTUnwrap(store.fetch(id: XCTUnwrap(inserted.id)))
        XCTAssertEqual(fetched.audioPath, "/tmp/mintzo-test/abc.wav")
    }

    func testMigrationIsIdempotentAcrossReopens() throws {
        try makeV1Database()
        _ = try HistoryStore(path: databasePath)
        // Réouverture : les migrations déjà appliquées ne rejouent pas.
        let store = try HistoryStore(path: databasePath)
        XCTAssertEqual(try store.fetchAll().count, 2)
    }

    // MARK: - Relance : mise à jour en place

    func testReplayUpdateRewritesTextsAndLanguageInPlace() throws {
        let store = try HistoryStore(path: databasePath)
        let inserted = try store.insert(Transcription(
            texteBrut: "testu zaharra",
            texteCorrige: "Testu zaharra.",
            dureeAudio: 12,
            langue: .eu,
            source: .dictee,
            audioPath: "/tmp/a.wav"
        ))
        let id = try XCTUnwrap(inserted.id)

        try store.update(id: id, texteBrut: "nouveau texte", texteCorrige: "Nouveau texte.", langue: .fr)

        let updated = try XCTUnwrap(store.fetch(id: id))
        XCTAssertEqual(updated.texteBrut, "nouveau texte")
        XCTAssertEqual(updated.texteCorrige, "Nouveau texte.")
        XCTAssertEqual(updated.langue, .fr)
        // Conservés : date, durée, source, audio.
        XCTAssertEqual(updated.date.timeIntervalSince1970,
                       inserted.date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(updated.dureeAudio, 12)
        XCTAssertEqual(updated.source, .dictee)
        XCTAssertEqual(updated.audioPath, "/tmp/a.wav")
        // L'index FTS suit la relance.
        XCTAssertEqual(try store.search(query: "nouveau").count, 1)
        XCTAssertTrue(try store.search(query: "zaharra").isEmpty)
    }

    // MARK: - Suppression : les fichiers audio suivent les entrées

    private func makeAudioFile(_ name: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try TranscriptionAudioStore.wavData(samples: [0.1, 0.2, 0.3]).write(to: url)
        return url.path
    }

    private func insertEntry(_ store: HistoryStore, texte: String, audioPath: String?) throws -> Int64 {
        let inserted = try store.insert(Transcription(
            texteBrut: texte, dureeAudio: 1, langue: .eu, source: .dictee, audioPath: audioPath
        ))
        return try XCTUnwrap(inserted.id)
    }

    func testDeleteRemovesEntryAndItsAudioFileOnly() throws {
        let store = try HistoryStore(path: databasePath)
        let keptAudio = try makeAudioFile("kept.wav")
        let deletedAudio = try makeAudioFile("deleted.wav")
        let deletedID = try insertEntry(store, texte: "ezabatzeko", audioPath: deletedAudio)
        let keptID = try insertEntry(store, texte: "gordetzeko", audioPath: keptAudio)

        try store.delete(id: deletedID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedAudio),
                       "l'audio de l'entrée supprimée doit disparaître")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptAudio),
                      "l'audio des autres entrées ne doit pas être touché")
        XCTAssertEqual(try store.fetchAll().map(\.id), [keptID])
    }

    func testDeleteEntryWithoutAudioOrWithMissingFileSucceeds() throws {
        let store = try HistoryStore(path: databasePath)
        let noAudioID = try insertEntry(store, texte: "audio gabe", audioPath: nil)
        let ghostID = try insertEntry(
            store, texte: "audio galduta",
            audioPath: directory.appendingPathComponent("deja-absent.wav").path
        )

        XCTAssertNoThrow(try store.delete(id: noAudioID))
        XCTAssertNoThrow(try store.delete(id: ghostID))
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testDeleteAllRemovesEveryAudioFile() throws {
        let store = try HistoryStore(path: databasePath)
        let paths = try (0..<3).map { try makeAudioFile("all-\($0).wav") }
        for (index, path) in paths.enumerated() {
            _ = try insertEntry(store, texte: "sarrera \(index)", audioPath: path)
        }
        _ = try insertEntry(store, texte: "audio gabe", audioPath: nil)

        try store.deleteAll()

        XCTAssertTrue(try store.fetchAll().isEmpty)
        for path in paths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), "\(path) doit être supprimé")
        }
    }
}
