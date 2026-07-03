import XCTest
@testable import MintzoCore

/// Tests de `ModelManager` : download réel du tiny (~75 Mo, réseau requis),
/// rejet de checksum falsifié, inventaire.
final class ModelManagerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-modelmanager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Download RÉEL de ggml-tiny (~75 Mo) : progress émis et croissant,
    /// checksum vérifié, installation atomique, puis suppression.
    func testDownloadsTinyForRealWithProgressChecksumAndRemove() async throws {
        let manager = ModelManager(modelsDirectory: tempDirectory)
        let tiny = ModelCatalog.whisperTiny

        var initial = await manager.installedModels()
        XCTAssertTrue(initial.isEmpty, "Répertoire vierge attendu")

        var progressEvents: [DownloadProgress] = []
        for try await progress in manager.download(tiny) {
            progressEvents.append(progress)
        }

        // Progression : non vide, monotone croissante, aboutit à la taille totale.
        XCTAssertFalse(progressEvents.isEmpty, "Aucun événement de progression émis")
        let received = progressEvents.map(\.bytesReceived)
        XCTAssertEqual(received, received.sorted(), "Progression non monotone")
        let last = try XCTUnwrap(progressEvents.last)
        XCTAssertEqual(last.bytesReceived, tiny.sizeBytes, "Le dernier événement doit couvrir tout le fichier")
        XCTAssertEqual(last.fraction, 1.0, accuracy: 0.001)

        // Installé et visible dans l'inventaire.
        let installed = await manager.installedModels()
        XCTAssertEqual(installed.map(\.id), [tiny.id])
        let maybeLocalURL = await manager.localURL(for: tiny)
        let localURL = try XCTUnwrap(maybeLocalURL)
        let size = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64
        XCTAssertEqual(size, tiny.sizeBytes)

        // Aucun fichier de staging résiduel.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "Staging résiduel : \(leftovers)")

        // Suppression.
        try await manager.remove(tiny)
        initial = await manager.installedModels()
        XCTAssertTrue(initial.isEmpty, "Le modèle doit disparaître de l'inventaire")
        let localAfterRemove = await manager.localURL(for: tiny)
        XCTAssertNil(localAfterRemove)
    }

    /// Un download dont le SHA256 ne correspond pas au catalogue doit être
    /// rejeté avec `.checksumMismatch` et ne laisser AUCUN fichier derrière lui.
    /// (Fichier source local via URL file:// — même pipeline, sans re-télécharger 75 Mo.)
    func testRejectsFalsifiedChecksumAndCleansUp() async throws {
        let payload = tempDirectory.appendingPathComponent("payload.bin")
        try Data((0..<2048).map { UInt8($0 % 251) }).write(to: payload)

        let modelsDir = tempDirectory.appendingPathComponent("models", isDirectory: true)
        let manager = ModelManager(modelsDirectory: modelsDir)

        let falsified = WhisperModel(
            id: "test-falsified",
            displayName: "Checksum falsifié",
            downloadURL: payload,
            sizeBytes: 2048,
            sha256: String(repeating: "deadbeef", count: 8), // 64 hex chars, forcément faux
            role: .testing
        )

        var thrownError: Error?
        do {
            for try await _ in manager.download(falsified) {}
            XCTFail("Le download aurait dû échouer sur le checksum")
        } catch {
            thrownError = error
        }

        guard case .checksumMismatch(let modelID, let expected, let actual)? =
                thrownError as? ModelManagerError else {
            return XCTFail("Attendu .checksumMismatch, obtenu : \(String(describing: thrownError))")
        }
        XCTAssertEqual(modelID, "test-falsified")
        XCTAssertEqual(expected, falsified.sha256)
        XCTAssertEqual(actual.count, 64, "SHA256 hex attendu")

        // Nettoyage total : ni modèle installé, ni staging résiduel.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path)) ?? []
        XCTAssertTrue(contents.isEmpty, "Le répertoire modèles doit être vide, contient : \(contents)")
        let installed = await manager.installedModels()
        XCTAssertTrue(installed.isEmpty)
    }

    /// Inventaire sur répertoire vierge : rien d'installé, localURL nil,
    /// expectedLocalURL pointe dans le répertoire configuré.
    func testInventoryOnEmptyDirectory() async {
        let manager = ModelManager(modelsDirectory: tempDirectory)

        let installed = await manager.installedModels()
        XCTAssertTrue(installed.isEmpty)

        let local = await manager.localURL(for: ModelCatalog.whisperFR)
        XCTAssertNil(local)

        let expected = manager.expectedLocalURL(for: ModelCatalog.whisperFR)
        XCTAssertEqual(expected.lastPathComponent, "whisper-fr.bin")
        XCTAssertEqual(expected.deletingLastPathComponent().path, tempDirectory.path)
    }

    /// Un fichier tronqué (mauvaise taille) ne compte PAS comme installé.
    func testTruncatedFileIsNotConsideredInstalled() async throws {
        let manager = ModelManager(modelsDirectory: tempDirectory)
        let tiny = ModelCatalog.whisperTiny
        let target = manager.expectedLocalURL(for: tiny)
        try Data("tronqué".utf8).write(to: target)

        let isInstalled = await manager.isInstalled(tiny)
        XCTAssertFalse(isInstalled, "Un fichier à la mauvaise taille ne doit pas passer pour installé")
    }
}
