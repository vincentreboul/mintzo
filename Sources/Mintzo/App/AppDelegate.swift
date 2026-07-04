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

        // Menu principal dans la langue de l'app : macOS ne traduit pas les
        // menus standard en euskara, et une app SwiftUI n'a pas de MainMenu.xib
        // à localiser. Ré-appliqué à chaque fenêtre active (`windowDidBecomeKey`)
        // car SwiftUI peut reconstruire le menu après le lancement.
        MainMenuLocalizer.localize()

        #if DEBUG
        // Harnais QA (previews / snapshots) : pas de présentation parasite.
        let env = ProcessInfo.processInfo.environment
        if env["MINTZO_HUD_PREVIEW"] == "1" || env["MINTZO_HUD_SNAPSHOT_DIR"] != nil {
            return
        }
        #endif

        // Lancement MANUEL (Finder / Launchpad) : TOUJOURS une fenêtre visible
        // au premier plan — une app qui démarre invisible est le premier
        // « il ne se passe rien » du client. Premier lancement : l'onboarding.
        // Ensuite : la fenêtre principale. Login item : discret.
        //
        // L'onboarding jamais terminé se présente certes tout seul
        // (`OnboardingScene.defaultLaunchBehavior(.presented)`) MAIS l'app est
        // un accessoire (`LSUIElement`) : le système ne l'active pas au
        // lancement, la fenêtre naissait DERRIÈRE l'app frontale, sans focus —
        // vécue comme « pas de fenêtre » (retour client, 1er lancement).
        // Ici : présentation via le pont `openWindow` + `NSApp.activate()`
        // (différées au câblage du pont si nécessaire) → premier plan garanti.
        if !launchedAsLoginItem {
            let id = OnboardingGate.hasCompleted()
                ? WindowSceneID.main
                : WindowSceneID.onboarding
            presentWindow(id: id, activating: true)

            // Filet : l'activation coopérative (macOS 14+) peut être REFUSÉE à
            // une app accessoire (autre app frontale qui ne cède pas, dialogue
            // système). La fenêtre serait alors présentée DERRIÈRE l'app
            // frontale — vécu « aucune fenêtre ». Une fois la scène créée, si
            // l'app n'est toujours pas active : ordre au premier plan sans
            // condition (`orderFrontRegardless`) — visible même sans focus.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !NSApp.isActive else { return }
                self.raiseSceneWindow(id: id)
                NSApp.activate()
            }
        }
    }

    /// Met les fenêtres d'une scène au premier plan sans exiger l'activation.
    private func raiseSceneWindow(id sceneID: String) {
        for window in NSApp.windows where window.isVisible {
            guard let identifier = window.identifier?.rawValue,
                  identifier == sceneID || identifier.hasPrefix("\(sceneID)-")
            else { continue }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
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

    /// Quitter proprement malgré une course connue de ggml : à l'`exit()`, les
    /// destructeurs statiques C++ libèrent les devices Metal de whisper/llama
    /// pendant que leurs threads d'init « residency sets » tournent encore
    /// (`ggml-metal-device.m`) → `ggml_abort`, crash systématique au quit.
    /// On flush les préférences puis on sort SANS exécuter ces destructeurs :
    /// le système récupère mémoire, GPU et fichiers, et il n'y a rien à écrire
    /// en attente (historique et audio sont commités de façon synchrone).
    /// À retirer si llama.cpp / whisper.cpp corrigent la course en amont.
    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.synchronize()
        _exit(0)
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
        // Toute fenêtre qui devient active : re-localiser le menu principal
        // (SwiftUI a pu le reconstruire depuis le dernier passage).
        MainMenuLocalizer.localize()

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
