import SwiftUI
import AppKit

@main
struct MintzoApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(model: coordinator)
        } label: {
            MenuBarLabelView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        MainWindowScene(
            store: coordinator.historyStore,
            queue: coordinator.fileQueue,
            onFilesDropped: { coordinator.enqueueFiles($0) }
        )
        .defaultLaunchBehavior(.suppressed) // app menu bar : rien ne s'ouvre au lancement
    }
}

/// Label du menu bar : rend l'icône ET fait le pont entre le coordinator et les
/// actions de scène SwiftUI (`openWindow`) — lisibles uniquement depuis une vue.
/// Ce label est rendu dès le lancement : son `onAppear` sert d'amorçage unique.
private struct MenuBarLabelView: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarIconView(
            state: coordinator.menuBarState,
            frame: coordinator.menuBarFrame,
            languageFlash: coordinator.languageFlash
        )
        .onAppear {
            coordinator.bootstrap(
                openMainWindow: { openWindow(id: "main") },
                openSettings: {}
            )
        }
    }
}
