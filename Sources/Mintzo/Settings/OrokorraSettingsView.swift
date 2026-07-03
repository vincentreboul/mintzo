import SwiftUI
import KeyboardShortcuts
import MintzoCore

/// Onglet Orokorra : langue par défaut, raccourci de dictée, touche Fn
/// (avec état de la permission Accessibilité + deep-link), mode d'insertion,
/// ouverture à l'ouverture de session.
struct OrokorraSettingsView: View {
    @Bindable var coordinator: AppCoordinator

    @State private var fnEnabled = AppSettings.fnKeyEnabled
    @State private var shortcutBehavior = AppSettings.shortcutBehavior
    @State private var autoInsert = AppSettings.autoInsert
    @State private var permissions: PermissionsSnapshot?

    // SMAppService est la source de vérité (pas de flag UserDefaults) :
    // l'état est relu par polling tant que l'onglet est affiché, comme les
    // permissions TCC — l'approbation se fait hors app, dans Réglages Système.
    @State private var loginItems = LoginItemService()
    @State private var openAtLogin = false
    @State private var loginNeedsApproval = false

    var body: some View {
        Form {
            Section {
                Picker(SettingsStrings.languageLabel, selection: $coordinator.language) {
                    Text("euskara").tag(HUDLanguage.eu)
                    Text("français").tag(HUDLanguage.fr)
                    Text(MzStrings.languageAuto).tag(HUDLanguage.auto)
                }
                .pickerStyle(.segmented)

                // Cycle de langue eu → fr → auto (§4.4) — défaut ⌃⌥L.
                KeyboardShortcuts.Recorder(SettingsStrings.languageShortcutLabel, name: .languageCycle)

                KeyboardShortcuts.Recorder(SettingsStrings.shortcutLabel, name: .dictation)

                // Appui simple (défaut, façon SuperWhisper) ou maintien —
                // ne concerne que le raccourci : la touche Fn reste un maintien.
                Picker(SettingsStrings.shortcutBehaviorLabel, selection: $shortcutBehavior) {
                    Text(SettingsStrings.shortcutBehaviorPressOnce)
                        .tag(AppSettings.ShortcutBehavior.pressOnce)
                    Text(SettingsStrings.shortcutBehaviorHold)
                        .tag(AppSettings.ShortcutBehavior.hold)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(shortcutBehavior == .pressOnce
                     ? SettingsStrings.shortcutBehaviorPressOnceNote
                     : SettingsStrings.shortcutBehaviorHoldNote)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }

            Section {
                Toggle(SettingsStrings.fnToggle, isOn: $fnEnabled)
                if fnEnabled {
                    accessibilityStatusRow
                }
            } footer: {
                Text(SettingsStrings.fnPermissionNote)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }

            Section {
                Toggle(SettingsStrings.autoInsertToggle, isOn: $autoInsert)
            } footer: {
                Text(SettingsStrings.autoInsertNote)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }

            // Présence : barre de menus / Dock / les deux — jamais « aucun ».
            Section {
                Picker(SettingsStrings.presenceLabel, selection: presenceMode) {
                    Text(SettingsStrings.presenceMenuBar).tag(AppPresenceMode.menuBar)
                    Text(SettingsStrings.presenceDock).tag(AppPresenceMode.dock)
                    Text(SettingsStrings.presenceBoth).tag(AppPresenceMode.both)
                }
            } footer: {
                Text(SettingsStrings.presenceNote)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }

            // Apparence : système / clair / sombre — appliquée à chaud sur
            // toute l'app (fenêtres, Réglages, capsule HUD).
            Section {
                Picker(SettingsStrings.appearanceLabel, selection: appearanceMode) {
                    Text(SettingsStrings.appearanceSystem).tag(AppAppearanceMode.system)
                    Text(SettingsStrings.appearanceLight).tag(AppAppearanceMode.light)
                    Text(SettingsStrings.appearanceDark).tag(AppAppearanceMode.dark)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle(SettingsStrings.loginItemToggle, isOn: $openAtLogin)
                if loginNeedsApproval {
                    loginItemApprovalRow
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .onChange(of: fnEnabled) { _, newValue in
            AppSettings.fnKeyEnabled = newValue
            coordinator.hotkeySettingsChanged()
        }
        .onChange(of: shortcutBehavior) { _, newValue in
            AppSettings.shortcutBehavior = newValue
            coordinator.hotkeySettingsChanged()
        }
        .onChange(of: autoInsert) { _, newValue in
            AppSettings.autoInsert = newValue
        }
        .onChange(of: openAtLogin) { _, newValue in
            setLoginItem(newValue)
        }
        .task {
            // État initial immédiat, puis re-lecture périodique tant que
            // l'onglet est affiché (l'approbation arrive de Réglages Système).
            while !Task.isCancelled {
                refreshLoginItem()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            // État initial immédiat, puis polling des changements TCC tant que
            // l'onglet est affiché (le flux s'arrête à la disparition de la vue).
            for await snapshot in coordinator.permissions.changes() {
                permissions = snapshot
            }
        }
    }

    // MARK: - Présence (menu bar / Dock / les deux)

    /// Liaison directe sur le service : `setMode` persiste, applique la
    /// politique Dock à chaud et ré-active l'app (la fenêtre Réglages reste
    /// au premier plan pendant la bascule).
    private var presenceMode: Binding<AppPresenceMode> {
        Binding(
            get: { coordinator.presence.mode },
            set: { coordinator.presence.setMode($0) }
        )
    }

    // MARK: - Apparence (système / clair / sombre)

    /// Liaison directe sur le service : `setMode` persiste et applique à chaud
    /// (`NSApp.appearance`) — fenêtres, Réglages et capsule HUD suivent.
    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { coordinator.appearance.mode },
            set: { coordinator.appearance.setMode($0) }
        )
    }

    // MARK: - Ouverture de session

    /// Relit l'état réel. Le toggle reflète l'inscription (active OU en
    /// attente d'approbation) ; la ligne d'approbation explique l'attente.
    private func refreshLoginItem() {
        openAtLogin = loginItems.isEnabled || loginItems.needsApproval
        loginNeedsApproval = loginItems.needsApproval
    }

    private func setLoginItem(_ enabled: Bool) {
        // Ignore les onChange déclenchés par refreshLoginItem() lui-même.
        guard enabled != (loginItems.isEnabled || loginItems.needsApproval) else { return }
        do {
            try loginItems.setEnabled(enabled)
        } catch {
            // register/unregister refusé par le système : l'UI revient à l'état réel.
        }
        refreshLoginItem()
    }

    /// Même pattern que la ligne Accessibilité : pastille + texte + deep-link.
    private var loginItemApprovalRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MzColor.gorri)
                .frame(width: 7, height: 7)
            Text(SettingsStrings.loginItemNeedsApproval)
                .font(.system(size: 12))
                .foregroundStyle(MzColor.inkSecondary)
            Spacer()
            Button(SettingsStrings.openSystemSettings) {
                loginItems.openSystemSettings()
            }
            .controlSize(.small)
        }
    }

    private var accessibilityStatusRow: some View {
        let granted = permissions?.accessibility == .granted
        return HStack(spacing: 8) {
            Circle()
                .fill(granted ? MzColor.success : MzColor.gorri)
                .frame(width: 7, height: 7)
            Text(granted ? SettingsStrings.accessibilityGranted : SettingsStrings.accessibilityMissing)
                .font(.system(size: 12))
                .foregroundStyle(MzColor.inkSecondary)
            Spacer()
            if !granted {
                Button(SettingsStrings.openSystemSettings) {
                    coordinator.permissions.requestAccessibilityAccess()
                    coordinator.permissions.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
    }
}
