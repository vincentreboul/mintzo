import SwiftUI

/// Onglets de la fenêtre Réglages — sélectionnables programmatiquement
/// (ex. clic sur l'erreur HUD « eredua falta da » → Ereduak, là où vit
/// le bouton Deskargatu).
enum SettingsTab: Hashable {
    case orokorra, ereduak, zuzenketa
}

/// Fenêtre Réglages — 3 onglets natifs (Form grouped) : Orokorra / Ereduak /
/// Zuzenketa. SF Symbols §9.3, microcopy §9, jamais d'emoji.
/// La sélection est portée par le coordinator (`settingsTab`) : la scène
/// `Settings` est ouverte via `openSettings()` (macOS 14+), l'onglet via ce binding.
struct SettingsRootView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        TabView(selection: $coordinator.settingsTab) {
            OrokorraSettingsView(coordinator: coordinator)
                .tabItem { Label(SettingsStrings.tabOrokorra, systemImage: "gearshape") }
                .tag(SettingsTab.orokorra)
            EreduakSettingsView(library: coordinator.modelLibrary)
                .tabItem { Label(SettingsStrings.tabEreduak, systemImage: "internaldrive") }
                .tag(SettingsTab.ereduak)
            ZuzenketaSettingsView(coordinator: coordinator)
                .tabItem { Label(SettingsStrings.tabZuzenketa, systemImage: "textformat.abc") }
                .tag(SettingsTab.zuzenketa)
        }
        .frame(width: 500)
    }
}
