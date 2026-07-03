import ServiceManagement

/// Backend d'inscription à l'ouverture de session — abstraction de
/// `SMAppService.mainApp` (prod) pour la testabilité : le vrai SMAppService
/// dialogue avec le daemon `smd` et ne se teste pas en CI.
public protocol LoginItemBackend {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

/// `SMAppService` expose déjà exactement les trois membres requis
/// (`status`, `register()`, `unregister()`), la conformance est directe.
extension SMAppService: LoginItemBackend {}

/// Inscription de Mintzo comme élément d'ouverture de session (login item).
///
/// `SMAppService` est la seule source de vérité : aucun flag UserDefaults en
/// doublon (l'utilisateur peut changer l'état dans Réglages Système, un flag
/// local mentirait). Cas `.requiresApproval` : l'inscription est enregistrée
/// mais macOS attend l'approbation de l'utilisateur dans Réglages Système >
/// Général > Ouverture — voir `needsApproval` + `openSystemSettings()`.
@MainActor
public final class LoginItemService {
    private let backend: any LoginItemBackend

    public init(backend: any LoginItemBackend = SMAppService.mainApp) {
        self.backend = backend
    }

    /// `true` si l'app est inscrite ET approuvée à l'ouverture de session.
    public var isEnabled: Bool {
        backend.status == .enabled
    }

    /// `true` si l'inscription attend l'approbation de l'utilisateur dans
    /// Réglages Système (status `.requiresApproval`).
    public var needsApproval: Bool {
        backend.status == .requiresApproval
    }

    /// Inscrit / désinscrit l'app à l'ouverture de session.
    ///
    /// Idempotent : ne rappelle pas le backend si l'état demandé est déjà
    /// effectif (re-register d'un service enregistré = erreur système).
    /// Désactiver depuis `.requiresApproval` désinscrit l'inscription en
    /// attente d'approbation.
    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard backend.status != .enabled else { return }
            try backend.register()
        } else {
            guard backend.status != .notRegistered else { return }
            try backend.unregister()
        }
    }

    /// Ouvre Réglages Système > Général > Ouverture (éléments d'ouverture).
    /// API officielle `openSystemSettingsLoginItems()` — même destination que
    /// le deep-link `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`,
    /// mais stable (l'URL, elle, n'est pas documentée).
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
