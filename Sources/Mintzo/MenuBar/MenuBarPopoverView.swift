import SwiftUI

// Popover du menu bar (§5.3) — matériau système du MenuBarExtra .window,
// aucun chrome custom. Actions câblées sur des notifications placeholder :
// l'intégration réelle (moteur de dictée, fenêtre, réglages) arrive vague 3.

extension Notification.Name {
    static let mintzoDictateToggleRequested = Notification.Name("eus.mintzo.dictateToggleRequested")
    static let mintzoOpenMainWindowRequested = Notification.Name("eus.mintzo.openMainWindowRequested")
    static let mintzoTranscribeFileRequested = Notification.Name("eus.mintzo.transcribeFileRequested")
    static let mintzoOpenSettingsRequested = Notification.Name("eus.mintzo.openSettingsRequested")
}

struct MenuBarPopoverView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// Mêmes trois modes que le cycle du badge HUD (§4.4) : eu / fr / auto.
    private static let selectableLanguages = HUDLanguage.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ligne d'état : langue + modèle chargé (11 pt secondaire).
            Text("\(model.language.rawValue) · \(MzStrings.modelReady)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            Picker(selection: $model.language) {
                ForEach(Self.selectableLanguages, id: \.self) { language in
                    Text(language.rawValue).tag(language)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                PopoverRow(title: MzStrings.dictate, shortcut: "⌥Space") {
                    dismiss()
                    NotificationCenter.default.post(name: .mintzoDictateToggleRequested, object: nil)
                }
                PopoverRow(title: MzStrings.openMintzo) {
                    dismiss()
                    NotificationCenter.default.post(name: .mintzoOpenMainWindowRequested, object: nil)
                }
                PopoverRow(title: MzStrings.transcribeFile) {
                    dismiss()
                    NotificationCenter.default.post(name: .mintzoTranscribeFileRequested, object: nil)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                PopoverRow(title: MzStrings.settings) {
                    dismiss()
                    NotificationCenter.default.post(name: .mintzoOpenSettingsRequested, object: nil)
                }
                PopoverRow(title: MzStrings.quit, shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(10)
        .frame(width: 240)
    }
}

/// Rangée façon menu : hover discret, pas de point final, pas de Title Case (§9.1).
private struct PopoverRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.08 : 0))
        }
        .onHover { hovered = $0 }
    }
}
