import AppKit
import Observation

/// Où Mintzo est visible : barre de menus (défaut historique), Dock, ou les deux.
/// « Nulle part » n'existe pas — le réglage ne l'offre jamais, et le retrait
/// manuel de l'icône menu bar (⌘-glisser) bascule automatiquement vers le Dock.
public enum AppPresenceMode: String, CaseIterable, Sendable {
    case menuBar
    case dock
    case both
}

/// Backend d'activation — abstraction de `NSApplication` (prod) pour la
/// testabilité : la politique d'activation réelle touche le WindowServer
/// et ne se teste pas en CI.
@MainActor
public protocol AppPresenceBackend {
    /// `true` → `.regular` (icône Dock, menus) ; `false` → `.accessory`.
    func setDockVisible(_ visible: Bool)
    /// Ramène l'app au premier plan (`NSApp.activate()`).
    func activateApp()
}

extension NSApplication: AppPresenceBackend {
    public func setDockVisible(_ visible: Bool) {
        setActivationPolicy(visible ? .regular : .accessory)
    }

    public func activateApp() {
        activate()
    }
}

/// Présence de l'app (menu bar / Dock / les deux), persistée et appliquée à chaud.
///
/// - Dock : `NSApp.setActivationPolicy(.regular / .accessory)`. Bascule à chaud :
///   après un passage en `.regular`, l'icône Dock n'apparaît de façon fiable
///   qu'une fois l'app ré-activée ; après un retour en `.accessory`, l'app est
///   désactivée par le système et sa fenêtre ouverte (Réglages) passerait à
///   l'arrière-plan — `activateApp()` est donc appelé après chaque changement
///   de politique demandé par l'utilisateur.
/// - Barre de menus : la visibilité est portée par le binding `isInserted` du
///   `MenuBarExtra` (MintzoApp), qui lit la même clé UserDefaults.
/// - Au lancement (`applyCurrentMode`) : politique seule, sans activation —
///   un lancement de session (login item) doit rester discret.
@MainActor
@Observable
public final class AppPresenceService {

    /// Clé partagée avec l'`@AppStorage` de `MintzoApp` (binding `isInserted`).
    public static let defaultsKey = "mintzo.presenceMode"

    @ObservationIgnored private let backend: any AppPresenceBackend
    @ObservationIgnored private let defaults: UserDefaults

    /// Mode courant. Écriture via `setMode(_:)` uniquement (persistance + application).
    public private(set) var mode: AppPresenceMode

    public init(
        backend: (any AppPresenceBackend)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend ?? NSApplication.shared
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.defaultsKey) ?? ""
        self.mode = AppPresenceMode(rawValue: raw) ?? .menuBar
    }

    /// L'icône de la barre de menus doit exister.
    public var isMenuBarVisible: Bool { mode != .dock }

    /// L'icône du Dock doit exister (politique `.regular`).
    public var isDockVisible: Bool { mode != .menuBar }

    /// Change le mode (action utilisateur) : persiste, applique la politique
    /// Dock et ré-active l'app pour que la bascule soit visible immédiatement.
    public func setMode(_ newMode: AppPresenceMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.defaultsKey)
        backend.setDockVisible(isDockVisible)
        backend.activateApp()
    }

    /// Applique la politique du mode persisté, sans activer l'app — appelé au
    /// lancement (AppDelegate) : un démarrage via login item reste discret.
    public func applyCurrentMode() {
        backend.setDockVisible(isDockVisible)
    }

    /// Garde-fou « jamais aucun des deux » : relaie le setter du binding
    /// `isInserted` du MenuBarExtra. Si le système retire l'icône alors que le
    /// mode la requiert (⌘-glisser hors de la barre), on bascule vers le Dock.
    /// Les échos du binding (retrait déjà voulu par le mode) sont ignorés.
    public func setMenuBarInserted(_ inserted: Bool) {
        guard !inserted, isMenuBarVisible else { return }
        setMode(.dock)
    }
}
