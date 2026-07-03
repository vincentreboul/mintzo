import XCTest
import AppKit
@testable import MintzoCore

// Tests d'AppearanceService (Système / Clair / Sombre) : persistance,
// application au lancement et à chaud, via un backend espion — jamais le
// NSApp réel en CI.

@MainActor
private final class SpyAppearanceBackend: AppearanceBackend {
    private(set) var appliedNames: [NSAppearance.Name?] = []

    func setAppearance(named name: NSAppearance.Name?) {
        appliedNames.append(name)
    }
}

@MainActor
final class AppearanceServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "eus.mintzo.tests.appearance"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultModeIsSystem() {
        let service = AppearanceService(backend: SpyAppearanceBackend(), defaults: defaults)
        XCTAssertEqual(service.mode, .system, "Défaut usine : suivre le système")
    }

    func testInitReadsPersistedMode() {
        defaults.set("dark", forKey: AppearanceService.defaultsKey)
        let service = AppearanceService(backend: SpyAppearanceBackend(), defaults: defaults)
        XCTAssertEqual(service.mode, .dark)
    }

    func testUnknownPersistedValueFallsBackToSystem() {
        defaults.set("sepia", forKey: AppearanceService.defaultsKey)
        let service = AppearanceService(backend: SpyAppearanceBackend(), defaults: defaults)
        XCTAssertEqual(service.mode, .system)
    }

    func testApplyCurrentModeAtLaunch() {
        defaults.set("light", forKey: AppearanceService.defaultsKey)
        let backend = SpyAppearanceBackend()
        let service = AppearanceService(backend: backend, defaults: defaults)

        service.applyCurrentMode()

        XCTAssertEqual(backend.appliedNames, [.aqua])
    }

    func testSetModePersistsAndAppliesHot() {
        let backend = SpyAppearanceBackend()
        let service = AppearanceService(backend: backend, defaults: defaults)

        service.setMode(.dark)
        XCTAssertEqual(service.mode, .dark)
        XCTAssertEqual(defaults.string(forKey: AppearanceService.defaultsKey), "dark")
        XCTAssertEqual(backend.appliedNames, [.darkAqua])

        // Retour au système : NSApp.appearance = nil (héritage système).
        service.setMode(.system)
        XCTAssertEqual(defaults.string(forKey: AppearanceService.defaultsKey), "system")
        XCTAssertEqual(backend.appliedNames, [.darkAqua, nil])
    }

    func testSetSameModeIsIdempotent() {
        let backend = SpyAppearanceBackend()
        let service = AppearanceService(backend: backend, defaults: defaults)

        service.setMode(.system)

        XCTAssertTrue(backend.appliedNames.isEmpty, "Aucune ré-application inutile")
        XCTAssertNil(defaults.string(forKey: AppearanceService.defaultsKey))
    }

    /// Le backend réel traduit bien les 3 modes (sans toucher NSApp ici :
    /// on vérifie seulement le mapping nom → NSAppearance existant).
    func testAppearanceNamesResolve() {
        XCTAssertNotNil(NSAppearance(named: .aqua))
        XCTAssertNotNil(NSAppearance(named: .darkAqua))
    }
}
