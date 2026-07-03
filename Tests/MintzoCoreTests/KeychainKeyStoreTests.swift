import XCTest
@testable import MintzoCore

/// CRUD Keychain sur un service de TEST dédié, nettoyé après chaque cas —
/// jamais le service de production « eus.mintzo.anthropic-key ».
final class KeychainKeyStoreTests: XCTestCase {

    private let store = KeychainKeyStore(
        service: "eus.mintzo.tests.anthropic-key",
        account: "anthropic-test"
    )

    override func setUpWithError() throws {
        // Environnement headless sans trousseau déverrouillé (CI) : skip honnête.
        do {
            try store.set("probe")
        } catch {
            throw XCTSkip("Trousseau indisponible dans cet environnement : \(error)")
        }
        try store.delete()
    }

    override func tearDownWithError() throws {
        try store.delete()
    }

    func testMissingKeyThrowsNotFound() {
        XCTAssertThrowsError(try store.apiKey()) { error in
            XCTAssertEqual(error as? KeychainKeyStoreError, .notFound)
        }
        XCTAssertNil(store.storedKey())
    }

    func testSetThenReadRoundTrips() throws {
        try store.set("sk-ant-test-0123456789")
        XCTAssertEqual(try store.apiKey(), "sk-ant-test-0123456789")
        XCTAssertEqual(store.storedKey(), "sk-ant-test-0123456789")
    }

    func testSetOverwritesExistingKey() throws {
        try store.set("ancienne")
        try store.set("nouvelle")
        XCTAssertEqual(try store.apiKey(), "nouvelle")
    }

    func testDeleteRemovesKeyAndIsIdempotent() throws {
        try store.set("à-supprimer")
        try store.delete()
        XCTAssertThrowsError(try store.apiKey()) { error in
            XCTAssertEqual(error as? KeychainKeyStoreError, .notFound)
        }
        // Deuxième suppression : silencieuse.
        XCTAssertNoThrow(try store.delete())
    }

    func testSettingEmptyKeyDeletes() throws {
        try store.set("quelque-chose")
        try store.set("")
        XCTAssertThrowsError(try store.apiKey()) { error in
            XCTAssertEqual(error as? KeychainKeyStoreError, .notFound)
        }
    }

    func testUnicodeKeySurvivesRoundTrip() throws {
        let key = "sk-ant-éüñ-测试-gakoa"
        try store.set(key)
        XCTAssertEqual(try store.apiKey(), key)
    }

    func testIsolatedFromOtherServiceAndAccount() throws {
        let other = KeychainKeyStore(
            service: "eus.mintzo.tests.anthropic-key.autre",
            account: "anthropic-test"
        )
        defer { try? other.delete() }
        try store.set("clé-principale")
        try other.set("clé-autre")
        XCTAssertEqual(try store.apiKey(), "clé-principale")
        XCTAssertEqual(try other.apiKey(), "clé-autre")
        try other.delete()
        XCTAssertEqual(try store.apiKey(), "clé-principale", "la suppression d'un service ne touche pas l'autre")
    }
}
