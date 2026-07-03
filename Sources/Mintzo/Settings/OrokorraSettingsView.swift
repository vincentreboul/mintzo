import SwiftUI
import KeyboardShortcuts
import MintzoCore

/// Onglet Orokorra : langue par défaut, raccourci de dictée, touche Fn
/// (avec état de la permission Accessibilité + deep-link), mode d'insertion.
struct OrokorraSettingsView: View {
    @Bindable var coordinator: AppCoordinator

    @State private var fnEnabled = AppSettings.fnKeyEnabled
    @State private var autoInsert = AppSettings.autoInsert
    @State private var permissions: PermissionsSnapshot?

    var body: some View {
        Form {
            Section {
                Picker(SettingsStrings.languageLabel, selection: $coordinator.language) {
                    Text("euskara").tag(HUDLanguage.eu)
                    Text("français").tag(HUDLanguage.fr)
                }
                .pickerStyle(.segmented)

                KeyboardShortcuts.Recorder(SettingsStrings.shortcutLabel, name: .dictation)
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
        }
        .formStyle(.grouped)
        .frame(height: 340)
        .onChange(of: fnEnabled) { _, newValue in
            AppSettings.fnKeyEnabled = newValue
            coordinator.hotkeySettingsChanged()
        }
        .onChange(of: autoInsert) { _, newValue in
            AppSettings.autoInsert = newValue
        }
        .task {
            // État initial immédiat, puis polling des changements TCC tant que
            // l'onglet est affiché (le flux s'arrête à la disparition de la vue).
            for await snapshot in coordinator.permissions.changes() {
                permissions = snapshot
            }
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
