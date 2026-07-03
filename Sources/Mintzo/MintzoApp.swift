import SwiftUI
import AppKit
import MintzoCore

@main
struct MintzoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator: AppCoordinator

    /// Présence persistée (même clé que `AppPresenceService`), lue ici pour
    /// piloter réactivement l'insertion du MenuBarExtra et le comportement de
    /// lancement de la fenêtre principale.
    @AppStorage(AppPresenceService.defaultsKey)
    private var presenceModeRaw = AppPresenceMode.menuBar.rawValue

    init() {
        let coordinator = AppCoordinator()
        _coordinator = State(initialValue: coordinator)
        // Avant tout callback de cycle de vie : le délégué applique la
        // politique Dock et démarre les services au lancement.
        appDelegate.coordinator = coordinator
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarPopoverView(model: coordinator)
        } label: {
            MenuBarLabelView(coordinator: coordinator, delegate: appDelegate)
        }
        .menuBarExtraStyle(.window)

        MainWindowScene(
            store: coordinator.historyStore,
            queue: coordinator.fileQueue,
            onFilesDropped: { coordinator.enqueueFiles($0) }
        )
        // App menu bar : rien ne s'ouvre au lancement — la présentation au
        // lancement MANUEL est décidée par l'AppDelegate (login item discret).
        // Mode « Dock seul » : la fenêtre EST l'app, et aucune vue de menu bar
        // n'existe pour câbler `openWindow` — on laisse SwiftUI la présenter.
        .defaultLaunchBehavior(
            presenceModeRaw == AppPresenceMode.dock.rawValue ? .presented : .suppressed
        )

        Settings {
            SettingsRootView(coordinator: coordinator)
        }

        // Première ouverture : la scène se présente elle-même au lancement
        // tant que l'onboarding n'a pas été terminé (porte OnboardingGate).
        OnboardingScene(coordinator: coordinator)
    }

    /// Insertion du MenuBarExtra, dérivée du mode de présence. Le setter ne
    /// sert qu'au retrait par le système (⌘-glisser hors de la barre) : le
    /// garde-fou du service bascule alors vers le Dock — jamais « aucun des deux ».
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { presenceModeRaw != AppPresenceMode.dock.rawValue },
            set: { inserted in coordinator.presence.setMenuBarInserted(inserted) }
        )
    }
}

/// Label du menu bar : rend l'icône ET fait le pont entre le coordinator, le
/// délégué AppKit et les actions de scène SwiftUI (`openWindow`) — lisibles
/// uniquement depuis une vue. Rendu dès le lancement quand la barre de menus
/// est active : son `onAppear` sert d'amorçage (en mode « Dock seul », c'est
/// l'AppDelegate et la vue Réglages qui prennent le relais).
private struct MenuBarLabelView: View {
    let coordinator: AppCoordinator
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarIconView(
            state: coordinator.menuBarState,
            frame: coordinator.menuBarFrame,
            languageFlash: coordinator.languageFlash
        )
        .onAppear {
            coordinator.bootstrap(
                openMainWindow: { openWindow(id: WindowSceneID.main) },
                openSettings: { openSettings() }
            )
            delegate.attachOpenWindow { openWindow(id: $0) }
        }
    }
}
