import ServiceManagement
import XCTest
@testable import MintzoCore

/// Tests du LoginItemService avec backend mocké — le vrai SMAppService
/// (daemon smd) n'est jamais appelé.
@MainActor
final class LoginItemServiceTests: XCTestCase {

    /// Backend simulé : statut piloté par le test, compteurs d'appels.
    private final class BackendMock: LoginItemBackend {
        var status: SMAppService.Status
        /// Statut résultant d'un `register()` réussi (`.enabled` par défaut,
        /// `.requiresApproval` pour simuler l'attente d'approbation macOS).
        var statusAfterRegister: SMAppService.Status = .enabled
        var registerCalls = 0
        var unregisterCalls = 0
        var registerError: Error?
        var unregisterError: Error?

        init(status: SMAppService.Status) {
            self.status = status
        }

        func register() throws {
            registerCalls += 1
            if let registerError { throw registerError }
            status = statusAfterRegister
        }

        func unregister() throws {
            unregisterCalls += 1
            if let unregisterError { throw unregisterError }
            status = .notRegistered
        }
    }

    private static let testError = NSError(domain: "eus.mintzo.tests", code: 1)

    // MARK: - Lecture d'état

    func testIsEnabledOnlyWhenStatusEnabled() {
        let cases: [(SMAppService.Status, Bool)] = [
            (.enabled, true),
            (.notRegistered, false),
            (.requiresApproval, false),
            (.notFound, false),
        ]
        for (status, expected) in cases {
            let service = LoginItemService(backend: BackendMock(status: status))
            XCTAssertEqual(service.isEnabled, expected, "status \(status.rawValue)")
        }
    }

    func testNeedsApprovalOnlyWhenStatusRequiresApproval() {
        let cases: [(SMAppService.Status, Bool)] = [
            (.requiresApproval, true),
            (.enabled, false),
            (.notRegistered, false),
            (.notFound, false),
        ]
        for (status, expected) in cases {
            let service = LoginItemService(backend: BackendMock(status: status))
            XCTAssertEqual(service.needsApproval, expected, "status \(status.rawValue)")
        }
    }

    // MARK: - Activation

    func testEnableRegistersWhenNotRegistered() throws {
        let backend = BackendMock(status: .notRegistered)
        let service = LoginItemService(backend: backend)

        try service.setEnabled(true)

        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertEqual(backend.unregisterCalls, 0)
        XCTAssertTrue(service.isEnabled)
    }

    func testEnableIsIdempotentWhenAlreadyEnabled() throws {
        let backend = BackendMock(status: .enabled)
        let service = LoginItemService(backend: backend)

        try service.setEnabled(true)

        XCTAssertEqual(backend.registerCalls, 0,
                       "re-register d'un service déjà actif = erreur système à éviter")
    }

    func testEnableCanLandOnRequiresApproval() throws {
        let backend = BackendMock(status: .notRegistered)
        backend.statusAfterRegister = .requiresApproval
        let service = LoginItemService(backend: backend)

        try service.setEnabled(true)

        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(service.needsApproval,
                      "macOS peut mettre l'inscription en attente d'approbation")
    }

    // MARK: - Désactivation

    func testDisableUnregistersWhenEnabled() throws {
        let backend = BackendMock(status: .enabled)
        let service = LoginItemService(backend: backend)

        try service.setEnabled(false)

        XCTAssertEqual(backend.unregisterCalls, 1)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertFalse(service.isEnabled)
    }

    func testDisableIsIdempotentWhenNotRegistered() throws {
        let backend = BackendMock(status: .notRegistered)
        let service = LoginItemService(backend: backend)

        try service.setEnabled(false)

        XCTAssertEqual(backend.unregisterCalls, 0,
                       "unregister d'un service non inscrit = erreur système à éviter")
    }

    func testDisableCancelsPendingApproval() throws {
        let backend = BackendMock(status: .requiresApproval)
        let service = LoginItemService(backend: backend)

        try service.setEnabled(false)

        XCTAssertEqual(backend.unregisterCalls, 1,
                       "désactiver depuis .requiresApproval doit annuler l'inscription en attente")
        XCTAssertFalse(service.needsApproval)
    }

    // MARK: - Erreurs

    func testEnablePropagatesRegisterError() {
        let backend = BackendMock(status: .notRegistered)
        backend.registerError = Self.testError
        let service = LoginItemService(backend: backend)

        XCTAssertThrowsError(try service.setEnabled(true))
        XCTAssertFalse(service.isEnabled, "l'état reflète l'échec, pas l'intention")
    }

    func testDisablePropagatesUnregisterError() {
        let backend = BackendMock(status: .enabled)
        backend.unregisterError = Self.testError
        let service = LoginItemService(backend: backend)

        XCTAssertThrowsError(try service.setEnabled(false))
        XCTAssertTrue(service.isEnabled, "l'état reflète l'échec, pas l'intention")
    }
}
