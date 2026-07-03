import AppKit
import XCTest
@testable import MintzoCore

/// Tests de l'AppPresenceService avec backend mocké — le vrai
/// `NSApp.setActivationPolicy` (WindowServer) n'est jamais appelé.
@MainActor
final class AppPresenceServiceTests: XCTestCase {

    /// Backend simulé : journal des politiques demandées + compteur d'activations.
    private final class BackendMock: AppPresenceBackend {
        var dockVisibleCalls: [Bool] = []
        var activateCalls = 0

        func setDockVisible(_ visible: Bool) { dockVisibleCalls.append(visible) }
        func activateApp() { activateCalls += 1 }
    }

    private static let suiteName = "eus.mintzo.tests.presence"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func makeService(_ backend: BackendMock = BackendMock()) -> AppPresenceService {
        AppPresenceService(backend: backend, defaults: defaults)
    }

    // MARK: - Lecture d'état

    func testDefaultModeIsBoth() {
        // Défaut usine (clé absente) : barre de menus ET Dock — retour client.
        XCTAssertEqual(makeService().mode, .both)
    }

    func testInvalidPersistedValueFallsBackToBoth() {
        defaults.set("banana", forKey: AppPresenceService.defaultsKey)
        XCTAssertEqual(makeService().mode, .both)
    }

    func testPersistedPreferenceIsRespectedOverFactoryDefault() {
        // Une préférence ENREGISTRÉE prime toujours sur le défaut usine.
        for mode in AppPresenceMode.allCases {
            defaults.set(mode.rawValue, forKey: AppPresenceService.defaultsKey)
            XCTAssertEqual(makeService().mode, mode, "préférence persistée \(mode)")
        }
    }

    func testVisibilityMatrix() {
        let cases: [(AppPresenceMode, Bool, Bool)] = [
            (.menuBar, true, false),
            (.dock, false, true),
            (.both, true, true),
        ]
        for (mode, menuBar, dock) in cases {
            let service = makeService()
            service.setMode(mode)
            XCTAssertEqual(service.isMenuBarVisible, menuBar, "menu bar — mode \(mode)")
            XCTAssertEqual(service.isDockVisible, dock, "dock — mode \(mode)")
        }
    }

    // MARK: - Persistance

    func testSetModePersistsAcrossInstances() {
        // .menuBar ≠ défaut usine (.both) : prouve une vraie écriture disque.
        makeService().setMode(.menuBar)
        XCTAssertEqual(makeService().mode, .menuBar, "le mode doit survivre à un relancement")
    }

    func testSetModeWritesRawValue() {
        makeService().setMode(.dock)
        XCTAssertEqual(defaults.string(forKey: AppPresenceService.defaultsKey), "dock")
    }

    // MARK: - Application de la politique

    func testApplyCurrentModeSetsPolicyWithoutActivating() {
        // Premier lancement (clé absente, défaut « les deux ») : l'icône Dock
        // doit être là (.regular), sans vol de focus.
        let backend = BackendMock()
        makeService(backend).applyCurrentMode()

        XCTAssertEqual(backend.dockVisibleCalls, [true], "both → .regular (icône Dock)")
        XCTAssertEqual(backend.activateCalls, 0,
                       "au lancement (login item), pas de vol de focus")
    }

    func testApplyCurrentModeHidesDockForPersistedMenuBarMode() {
        defaults.set(AppPresenceMode.menuBar.rawValue, forKey: AppPresenceService.defaultsKey)
        let backend = BackendMock()
        makeService(backend).applyCurrentMode()

        XCTAssertEqual(backend.dockVisibleCalls, [false], "menuBar persisté → .accessory")
    }

    func testApplyCurrentModeShowsDockForPersistedDockMode() {
        defaults.set(AppPresenceMode.dock.rawValue, forKey: AppPresenceService.defaultsKey)
        let backend = BackendMock()
        makeService(backend).applyCurrentMode()

        XCTAssertEqual(backend.dockVisibleCalls, [true])
    }

    func testSetModeDockShowsDockIconAndActivates() {
        let backend = BackendMock()
        makeService(backend).setMode(.dock)

        XCTAssertEqual(backend.dockVisibleCalls, [true])
        XCTAssertEqual(backend.activateCalls, 1,
                       "après .regular, l'icône Dock n'apparaît fiablement qu'une fois l'app ré-activée")
    }

    func testSetModeBackToMenuBarHidesDockAndReactivates() {
        let backend = BackendMock()
        let service = makeService(backend)
        service.setMode(.dock)
        service.setMode(.menuBar)

        XCTAssertEqual(backend.dockVisibleCalls, [true, false])
        XCTAssertEqual(backend.activateCalls, 2,
                       "après .accessory, la fenêtre Réglages ouverte doit rester au premier plan")
    }

    func testSetModeSameValueIsNoOp() {
        let backend = BackendMock()
        makeService(backend).setMode(.both) // déjà le mode courant (défaut usine)

        XCTAssertTrue(backend.dockVisibleCalls.isEmpty)
        XCTAssertEqual(backend.activateCalls, 0)
    }

    // MARK: - Garde-fou « jamais aucun des deux »

    func testMenuBarRemovedExternallyFallsBackToDock() {
        let backend = BackendMock()
        let service = makeService(backend)

        service.setMenuBarInserted(false)

        XCTAssertEqual(service.mode, .dock,
                       "⌘-glisser l'icône hors de la barre ne doit pas rendre l'app invisible")
        XCTAssertEqual(backend.dockVisibleCalls, [true])
    }

    func testMenuBarRemovedInBothModeFallsBackToDock() {
        let service = makeService()
        service.setMode(.both)

        service.setMenuBarInserted(false)

        XCTAssertEqual(service.mode, .dock)
    }

    func testMenuBarRemovalEchoInDockModeIsNoOp() {
        let backend = BackendMock()
        let service = makeService(backend)
        service.setMode(.dock)
        let callsBefore = backend.dockVisibleCalls.count

        service.setMenuBarInserted(false)

        XCTAssertEqual(service.mode, .dock)
        XCTAssertEqual(backend.dockVisibleCalls.count, callsBefore,
                       "l'écho du binding isInserted (retrait déjà voulu) ne doit rien re-déclencher")
    }

    func testMenuBarInsertedTrueIsNoOp() {
        let service = makeService()
        service.setMenuBarInserted(true)
        XCTAssertEqual(service.mode, .both, "l'écho d'insertion ne change pas le mode")
    }
}
