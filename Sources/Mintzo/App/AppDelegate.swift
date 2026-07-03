import AppKit

/// Identifiants des scènes `Window` de MintzoApp — utilisés par le pont
/// AppKit → SwiftUI (`openWindow(id:)`). Doivent rester alignés sur les
/// littéraux des scènes (`MainWindowScene` : "main", `OnboardingScene` :
/// "onboarding").
enum WindowSceneID {
    static let main = "main"
    static let onboarding = "onboarding"
}

/// Délégué AppKit de Mintzo — la part du cycle de vie que SwiftUI ne couvre
/// pas pour une app de barre de menus :
///
/// 1. **Relance depuis le Finder / Launchpad / Dock** (`applicationShouldHandleReopen`) :
///    sans lui, « il ne se passe rien » — l'app tourne déjà, aucune fenêtre
///    ne s'ouvre. Désormais : fenêtre principale (ou onboarding si jamais terminé).
/// 2. **Lancement manuel** : présenter la fenêtre principale une fois
///    l'onboarding terminé. Un lancement de session (login item SMAppService)
///    est détecté via l'évènement Apple `keyAELaunchedAsLogInItem` et reste
///    discret (aucune fenêtre volée au login).
/// 3. **Politique d'activation** : applique le mode de présence persisté
///    (Dock / barre de menus / les deux) dès le lancement, et démarre les
///    services du coordinator indépendamment de toute vue (en mode « Dock
///    seul », aucun label de MenuBarExtra n'existe pour le faire).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Accès depuis les vues-ancres (Réglages) sans injection d'environnement.
    private(set) static weak var shared: AppDelegate?

    /// Renseigné par `MintzoApp.init` — donc avant tout callback du cycle de vie.
    var coordinator: AppCoordinator?

    /// Pont vers `openWindow(id:)` — câblé par la première vue SwiftUI rendue
    /// (label du menu bar, Réglages). AppKit ne sait pas créer une `Window`
    /// SwiftUI : sans ce pont, aucune scène ne peut être ouverte d'ici.
    private var openWindowAction: ((String) -> Void)?

    /// Présentation demandée avant que le pont ne soit câblé (le label du
    /// menu bar apparaît juste après `applicationDidFinishLaunching`).
    private var pendingWindowID: String?

    /// Dernière `NSWindow` connue par scène — repli quand le pont n'est pas
    /// câblé (mode « Dock seul » : aucune vue-ancre n'existe forcément).
    /// Référence forte assumée : une fenêtre fermée reste ré-affichable.
    private var rememberedWindows: [String: NSWindow] = [:]

    /// `true` si le processus a été lancé par loginwindow (login item).
    private(set) var launchedAsLoginItem = false

    override init() {
        super.init()
        Self.shared = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = Self.detectLoginItemLaunch()

        // Présence (Dock / menu bar) : politique seule, sans activation —
        // un lancement de session doit rester discret.
        coordinator?.presence.applyCurrentMode()

        // Services réels (hotkeys, flow, notifications) : démarrés ici et non
        // plus seulement depuis le label du menu bar — en mode « Dock seul »
        // ce label n'existe pas, la dictée doit fonctionner quand même.
        coordinator?.startServices()

        #if DEBUG
        // Harnais QA (previews / snapshots) : pas de présentation parasite.
        let env = ProcessInfo.processInfo.environment
        if env["MINTZO_HUD_PREVIEW"] == "1" || env["MINTZO_HUD_SNAPSHOT_DIR"] != nil {
            return
        }
        #endif

        // Lancement MANUEL (Finder / Launchpad) après onboarding : montrer la
        // fenêtre principale — une app qui démarre invisible est le premier
        // « il ne se passe rien » du client. Login item : discret.
        // (L'onboarding jamais terminé se présente déjà tout seul :
        // `OnboardingScene.defaultLaunchBehavior`.)
        if !launchedAsLoginItem, OnboardingGate.hasCompleted() {
            presentWindow(id: WindowSceneID.main, activating: true)
        }
    }

    /// Clic sur l'icône du Dock, ou double-clic Finder / Launchpad alors que
    /// l'app tourne déjà. `hasVisibleWindows` ment pour une app menu bar (la
    /// fenêtre du status item compte comme visible) : on évalue nous-mêmes.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasUserFacingVisibleWindow else {
            // Une fenêtre existe : la ramener au premier plan (défaut système).
            NSApp.activate()
            return true
        }
        let id = OnboardingGate.hasCompleted() ? WindowSceneID.main : WindowSceneID.onboarding
        return !presentWindow(id: id, activating: true)
    }

    /// App de barre de menus / utilitaire : fermer la dernière fenêtre ne
    /// quitte pas (le mode Dock seul y compris — la dictée continue).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Pont openWindow

    /// Câblé par la première vue rendue (label menu bar, Réglages). Idempotent ;
    /// vide la présentation en attente posée par `applicationDidFinishLaunching`.
    func attachOpenWindow(_ action: @escaping (String) -> Void) {
        if openWindowAction == nil {
            openWindowAction = action
        }
        if let pendingWindowID {
            self.pendingWindowID = nil
            openWindowAction?(pendingWindowID)
            NSApp.activate()
        }
    }

    /// Ouvre une scène : pont SwiftUI si câblé, sinon dernière NSWindow connue,
    /// sinon mémorise (vidée au câblage). Retourne `true` si une action a eu lieu.
    @discardableResult
    private func presentWindow(id: String, activating: Bool) -> Bool {
        defer { if activating { NSApp.activate() } }
        if let openWindowAction {
            openWindowAction(id)
            return true
        }
        if let window = rememberedWindows[id] {
            window.makeKeyAndOrderFront(nil)
            return true
        }
        pendingWindowID = id
        return false
    }

    // MARK: - Fenêtres utilisateur

    /// Fenêtres « de contenu » réellement visibles : exclut les panels (HUD),
    /// la fenêtre du status item et autres fenêtres système sans contenu.
    private var hasUserFacingVisibleWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible
                && !(window is NSPanel)
                && !window.className.contains("StatusBar")
                && window.styleMask.contains(.titled)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let identifier = window.identifier?.rawValue else { return }
        // SwiftUI nomme les fenêtres de scène `<sceneID>` ou `<sceneID>-AppWindow-<n>`.
        for sceneID in [WindowSceneID.main, WindowSceneID.onboarding]
        where identifier == sceneID || identifier.hasPrefix("\(sceneID)-") {
            rememberedWindows[sceneID] = window
        }
    }

    // MARK: - Détection login item

    /// L'évènement Apple d'ouverture (`kAEOpenApplication`) porte
    /// `keyAELaunchedAsLogInItem` quand le processus est lancé par loginwindow
    /// (login item SMAppService). Valide uniquement pendant le lancement.
    private static func detectLoginItemLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let propData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        else { return false }
        return propData.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
