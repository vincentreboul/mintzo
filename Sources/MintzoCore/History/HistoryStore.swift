import Foundation
import GRDB

/// Store GRDB de l'historique des transcriptions.
///
/// - Persistance : SQLite (`~/Library/Application Support/Mintzo/history.sqlite`
///   via ``standard()``, chemin injectable via ``init(path:)``, mémoire via
///   ``inMemory()`` pour les tests).
/// - Recherche : table virtuelle FTS5 (`texteBrut` + `texteCorrige`),
///   tokenizer unicode61 avec `remove_diacritics 2` — « reunion » matche
///   « réunion », « bilera » matche sans se soucier des accents. Synchronisée
///   par triggers SQL (GRDB `synchronize(withTable:)`), ranking bm25.
public final class HistoryStore: Sendable {

    private let dbQueue: DatabaseQueue

    // MARK: - Initialisation

    /// Injection GRDB directe (tests internes, migrations déjà appliquées ou non).
    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Store sur fichier SQLite au chemin donné.
    public convenience init(path: String) throws {
        try self.init(dbQueue: DatabaseQueue(path: path))
    }

    /// Store en mémoire (tests, previews).
    public static func inMemory() throws -> HistoryStore {
        try HistoryStore(dbQueue: DatabaseQueue())
    }

    /// Store par défaut de l'app : `~/Library/Application Support/Mintzo/history.sqlite`.
    public static func standard() throws -> HistoryStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Mintzo", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try HistoryStore(path: directory.appendingPathComponent("history.sqlite").path)
    }

    // MARK: - Migrations

    /// Interne (pas private) : les tests de migration rejouent `upTo: "v1"`
    /// pour vérifier qu'une base v1 existante passe en v2 sans perte.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: Transcription.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("texteBrut", .text).notNull()
                t.column("texteCorrige", .text)
                t.column("date", .datetime).notNull().indexed()
                t.column("dureeAudio", .double).notNull()
                t.column("langue", .text).notNull()
                t.column("source", .text).notNull()
                t.column("nomFichier", .text)
            }
            // Table FTS5 en contenu externe, synchronisée par triggers.
            // remove_diacritics 2 : diacritiques ignorés à l'indexation ET à la
            // requête (euskara et français matchent sans accents).
            try db.create(virtualTable: "transcription_ft", using: FTS5()) { t in
                t.synchronize(withTable: Transcription.databaseTableName)
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("texteBrut")
                t.column("texteCorrige")
            }
        }
        // v2 — réécoute/relance : chaque entrée peut référencer son WAV
        // conservé. Nullable : les entrées v1 n'ont pas d'audio.
        migrator.registerMigration("v2") { db in
            try db.alter(table: Transcription.databaseTableName) { t in
                t.add(column: "audioPath", .text)
            }
        }
        return migrator
    }

    // MARK: - Écriture

    /// Insère une transcription et retourne la valeur avec son `id` assigné.
    @discardableResult
    public func insert(_ transcription: Transcription) throws -> Transcription {
        try dbQueue.write { db in
            var record = transcription
            try record.insert(db)
            return record
        }
    }

    /// Met à jour le texte corrigé d'une transcription existante.
    public func update(id: Int64, texteCorrige: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcription SET texteCorrige = ? WHERE id = ?",
                arguments: [texteCorrige, id]
            )
        }
    }

    /// Relance (§ réécoute) : remplace EN PLACE les textes et la langue d'une
    /// entrée — date, durée, source et audioPath sont conservés.
    public func update(
        id: Int64,
        texteBrut: String,
        texteCorrige: String?,
        langue: Transcription.Langue
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcription SET texteBrut = ?, texteCorrige = ?, langue = ? WHERE id = ?",
                arguments: [texteBrut, texteCorrige, langue.rawValue, id]
            )
        }
    }

    /// Supprime la transcription d'identifiant donné — et son fichier audio
    /// conservé s'il existe (best effort : un fichier déjà absent ne fait pas
    /// échouer la suppression de l'entrée).
    public func delete(id: Int64) throws {
        let audioPath = try dbQueue.write { db -> String? in
            let path = try String.fetchOne(
                db,
                sql: "SELECT audioPath FROM transcription WHERE id = ?",
                arguments: [id]
            )
            try Transcription.deleteOne(db, key: id)
            return path
        }
        TranscriptionAudioStore.remove(atPath: audioPath)
    }

    /// Vide entièrement l'historique — fichiers audio conservés compris.
    public func deleteAll() throws {
        let audioPaths = try dbQueue.write { db -> [String] in
            let paths = try String.fetchAll(
                db,
                sql: "SELECT audioPath FROM transcription WHERE audioPath IS NOT NULL"
            )
            try Transcription.deleteAll(db)
            return paths
        }
        for path in audioPaths {
            TranscriptionAudioStore.remove(atPath: path)
        }
    }

    // MARK: - Lecture

    /// Toutes les transcriptions, la plus récente d'abord.
    public func fetchAll() throws -> [Transcription] {
        try dbQueue.read { db in
            try Transcription.order(Transcription.Columns.date.desc).fetchAll(db)
        }
    }

    /// Transcription par identifiant.
    public func fetch(id: Int64) throws -> Transcription? {
        try dbQueue.read { db in
            try Transcription.fetchOne(db, key: id)
        }
    }

    /// Observation continue de l'historique (plus récent d'abord).
    ///
    /// Émet la valeur courante immédiatement, puis à chaque changement en base.
    public func observe() -> AsyncThrowingStream<[Transcription], Error> {
        let dbQueue = self.dbQueue
        return AsyncThrowingStream { continuation in
            let task = Task {
                let observation = ValueObservation.tracking { db in
                    try Transcription.order(Transcription.Columns.date.desc).fetchAll(db)
                }
                do {
                    for try await transcriptions in observation.values(in: dbQueue) {
                        continuation.yield(transcriptions)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Recherche plein texte FTS5 (préfixes tolérés, accents ignorés),
    /// classée par pertinence bm25.
    public func search(query: String) throws -> [Transcription] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }
        return try dbQueue.read { db in
            try Transcription.fetchAll(
                db,
                sql: """
                    SELECT transcription.*
                    FROM transcription
                    JOIN transcription_ft
                        ON transcription_ft.rowid = transcription.id
                        AND transcription_ft MATCH ?
                    ORDER BY bm25(transcription_ft)
                    """,
                arguments: [pattern]
            )
        }
    }
}
