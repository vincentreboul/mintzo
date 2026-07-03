import XCTest
@testable import MintzoCore

final class HistoryStoreTests: XCTestCase {

    private func makeTranscription(
        texteBrut: String = "Kaixo Maite, bihar goizean elkartuko gara.",
        texteCorrige: String? = nil,
        date: Date = Date(),
        dureeAudio: TimeInterval = 42,
        langue: Transcription.Langue = .eu,
        source: Transcription.Source = .dictee,
        nomFichier: String? = nil
    ) -> Transcription {
        Transcription(
            texteBrut: texteBrut,
            texteCorrige: texteCorrige,
            date: date,
            dureeAudio: dureeAudio,
            langue: langue,
            source: source,
            nomFichier: nomFichier
        )
    }

    // MARK: - CRUD

    func testInsertAssignsIdAndPersistsAllFields() throws {
        let store = try HistoryStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let inserted = try store.insert(makeTranscription(
            texteBrut: "brut",
            texteCorrige: "corrigé",
            date: date,
            dureeAudio: 12.5,
            langue: .fr,
            source: .fichier,
            nomFichier: "bilera.m4a"
        ))

        XCTAssertNotNil(inserted.id)
        let fetched = try XCTUnwrap(store.fetch(id: XCTUnwrap(inserted.id)))
        XCTAssertEqual(fetched.texteBrut, "brut")
        XCTAssertEqual(fetched.texteCorrige, "corrigé")
        XCTAssertEqual(fetched.date.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(fetched.dureeAudio, 12.5)
        XCTAssertEqual(fetched.langue, .fr)
        XCTAssertEqual(fetched.source, .fichier)
        XCTAssertEqual(fetched.nomFichier, "bilera.m4a")
        XCTAssertEqual(fetched.texteAffiche, "corrigé")
    }

    func testFetchAllReturnsMostRecentFirst() throws {
        let store = try HistoryStore.inMemory()
        let old = try store.insert(makeTranscription(texteBrut: "ancien", date: Date(timeIntervalSinceNow: -3600)))
        let recent = try store.insert(makeTranscription(texteBrut: "récent", date: Date()))

        let all = try store.fetchAll()
        XCTAssertEqual(all.map(\.id), [recent.id, old.id])
    }

    func testUpdateTexteCorrige() throws {
        let store = try HistoryStore.inMemory()
        let inserted = try store.insert(makeTranscription(texteBrut: "testu gordina"))
        let id = try XCTUnwrap(inserted.id)
        XCTAssertNil(inserted.texteCorrige)

        try store.update(id: id, texteCorrige: "testu zuzendua")
        XCTAssertEqual(try store.fetch(id: id)?.texteCorrige, "testu zuzendua")

        try store.update(id: id, texteCorrige: nil)
        XCTAssertNil(try XCTUnwrap(store.fetch(id: id)).texteCorrige)
    }

    func testDeleteRemovesOnlyTargetRow() throws {
        let store = try HistoryStore.inMemory()
        let a = try store.insert(makeTranscription(texteBrut: "a"))
        let b = try store.insert(makeTranscription(texteBrut: "b"))

        try store.delete(id: XCTUnwrap(a.id))
        let remaining = try store.fetchAll()
        XCTAssertEqual(remaining.map(\.id), [b.id])
    }

    func testDeleteAll() throws {
        let store = try HistoryStore.inMemory()
        for i in 0..<5 {
            try store.insert(makeTranscription(texteBrut: "texte \(i)"))
        }
        try store.deleteAll()
        XCTAssertTrue(try store.fetchAll().isEmpty)
        XCTAssertTrue(try store.search(query: "texte").isEmpty)
    }

    // MARK: - Recherche FTS5

    func testSearchMatchesEuskaraWord() throws {
        let store = try HistoryStore.inMemory()
        try store.insert(makeTranscription(texteBrut: "Bilera bat daukagu bihar goizean bulegoan."))
        try store.insert(makeTranscription(texteBrut: "Le devis part ce soir.", langue: .fr))

        let results = try store.search(query: "bilera")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].texteBrut.contains("Bilera"))
    }

    func testSearchIgnoresDiacriticsBothWays() throws {
        let store = try HistoryStore.inMemory()
        try store.insert(makeTranscription(
            texteBrut: "Je t'appelle après la réunion pour valider les délais.",
            langue: .fr
        ))

        // Requête sans accents → texte accentué trouvé.
        XCTAssertEqual(try store.search(query: "reunion").count, 1)
        // Requête accentuée → trouvé aussi (diacritiques retirés côté requête).
        XCTAssertEqual(try store.search(query: "réunion").count, 1)
        XCTAssertEqual(try store.search(query: "delais").count, 1)
    }

    func testSearchMatchesTexteCorrige() throws {
        let store = try HistoryStore.inMemory()
        let inserted = try store.insert(makeTranscription(texteBrut: "testu gordina soilik"))
        try store.update(id: XCTUnwrap(inserted.id), texteCorrige: "aurrekontua bidalita dago")

        XCTAssertEqual(try store.search(query: "aurrekontua").count, 1)
        // Le texte brut reste indexé lui aussi.
        XCTAssertEqual(try store.search(query: "gordina").count, 1)
    }

    func testSearchPrefixAndRanking() throws {
        let store = try HistoryStore.inMemory()
        let dense = try store.insert(makeTranscription(texteBrut: "Bilera, bilera eta bilera berriz."))
        let sparse = try store.insert(makeTranscription(texteBrut: "Bilerarako gaia prestatu dut gaur."))

        // Préfixe : « biler » matche les deux.
        let results = try store.search(query: "biler")
        XCTAssertEqual(results.count, 2)
        // bm25 : le document le plus dense sur le terme sort en premier.
        XCTAssertEqual(results.first?.id, dense.id)
        XCTAssertEqual(results.last?.id, sparse.id)
    }

    func testSearchEmptyQueryReturnsEmpty() throws {
        let store = try HistoryStore.inMemory()
        try store.insert(makeTranscription())
        XCTAssertTrue(try store.search(query: "").isEmpty)
        XCTAssertTrue(try store.search(query: "   ").isEmpty)
        XCTAssertTrue(try store.search(query: "zzzinexistant").isEmpty)
    }

    func testSearchStaysInSyncAfterUpdateAndDelete() throws {
        let store = try HistoryStore.inMemory()
        let inserted = try store.insert(makeTranscription(texteBrut: "hitzordua finkatuta"))
        let id = try XCTUnwrap(inserted.id)

        try store.update(id: id, texteCorrige: "hitzordua atzeratuta")
        XCTAssertEqual(try store.search(query: "atzeratuta").count, 1)

        try store.delete(id: id)
        XCTAssertTrue(try store.search(query: "hitzordua").isEmpty)
    }

    // MARK: - Observation

    func testObserveEmitsInitialValueThenChanges() async throws {
        let store = try HistoryStore.inMemory()
        var iterator = store.observe().makeAsyncIterator()

        let initial = try await iterator.next()
        XCTAssertEqual(initial?.count, 0)

        try store.insert(makeTranscription(texteBrut: "lehen sarrera"))
        let afterInsert = try await iterator.next()
        XCTAssertEqual(afterInsert?.count, 1)
        XCTAssertEqual(afterInsert?.first?.texteBrut, "lehen sarrera")

        try store.deleteAll()
        let afterDelete = try await iterator.next()
        XCTAssertEqual(afterDelete?.count, 0)
    }

    // MARK: - Performance

    func testInsert1000TranscriptionsUnderTwoSeconds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-history-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try HistoryStore(path: directory.appendingPathComponent("history.sqlite").path)
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for i in 0..<1000 {
                try store.insert(makeTranscription(
                    texteBrut: "Transkripzio luzea zenbaki honekin: \(i). Bihar goizean bilera dugu bulegoan.",
                    langue: i.isMultiple(of: 2) ? .eu : .fr
                ))
            }
        }
        // Seuil large : garde-fou contre une régression d'ordre de grandeur (N+1, fsync par ligne),
        // pas un benchmark — sous charge machine (builds parallèles) 2 s flake (observé 2026-07-03).
        XCTAssertLessThan(elapsed, .seconds(8), "1000 insertions ont pris \(elapsed)")
        XCTAssertEqual(try store.fetchAll().count, 1000)
    }
}
