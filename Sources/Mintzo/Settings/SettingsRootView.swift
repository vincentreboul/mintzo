import SwiftUI

/// Fenêtre Réglages — 3 onglets natifs (Form grouped) : Orokorra / Ereduak /
/// Zuzenketa. SF Symbols §9.3, microcopy §9, jamais d'emoji.
struct SettingsRootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            OrokorraSettingsView(coordinator: coordinator)
                .tabItem { Label(SettingsStrings.tabOrokorra, systemImage: "gearshape") }
            EreduakSettingsView(library: coordinator.modelLibrary)
                .tabItem { Label(SettingsStrings.tabEreduak, systemImage: "internaldrive") }
            ZuzenketaSettingsView(coordinator: coordinator)
                .tabItem { Label(SettingsStrings.tabZuzenketa, systemImage: "textformat.abc") }
        }
        .frame(width: 500)
    }
}
