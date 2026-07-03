import SwiftUI
import MintzoCore

/// Onglet Zuzenketa : moteur de correction (off / Latxa local / cloud BYOK),
/// clé API Anthropic dans le trousseau, note honnête sur ce qui sort du Mac.
struct ZuzenketaSettingsView: View {
    let coordinator: AppCoordinator

    @State private var mode = AppSettings.correctionMode
    @State private var apiKeyInput = ""
    @State private var keyStored = false
    @State private var keyErrorMessage: String?

    private let keyStore = KeychainKeyStore()

    var body: some View {
        Form {
            Section {
                Picker(SettingsStrings.correctionModeLabel, selection: $mode) {
                    Text(SettingsStrings.correctionOff).tag(AppSettings.CorrectionMode.off)
                    Text(SettingsStrings.correctionLatxa).tag(AppSettings.CorrectionMode.latxa)
                    Text(SettingsStrings.correctionCloud).tag(AppSettings.CorrectionMode.cloud)
                }
                .pickerStyle(.radioGroup)

                if mode == .latxa, !latxaModelInstalled {
                    Text(SettingsStrings.latxaModelMissingNote)
                        .font(.system(size: 11))
                        .foregroundStyle(MzColor.gorri)
                }
            } footer: {
                Text(SettingsStrings.correctionExplainer)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }

            if mode == .cloud {
                Section {
                    SecureField(
                        SettingsStrings.apiKeyLabel,
                        text: $apiKeyInput,
                        prompt: Text(verbatim: "sk-ant-…")
                    )
                    .onSubmit { saveKey() }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(keyStored ? MzColor.success : MzColor.inkTertiary)
                            .frame(width: 7, height: 7)
                        Text(keyStored ? SettingsStrings.apiKeyStored : SettingsStrings.apiKeyMissing)
                            .font(.system(size: 12))
                            .foregroundStyle(MzColor.inkSecondary)
                        Spacer()
                        Button(SettingsStrings.save) { saveKey() }
                            .controlSize(.small)
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        if keyStored {
                            Button(SettingsStrings.remove, role: .destructive) { deleteKey() }
                                .controlSize(.small)
                        }
                    }
                    if let keyErrorMessage {
                        Text(keyErrorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(MzColor.gorri)
                    }
                } footer: {
                    Text(SettingsStrings.cloudHonestyNote)
                        .font(.system(size: 11))
                        .foregroundStyle(MzColor.inkSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
        .onChange(of: mode) { _, newValue in
            AppSettings.correctionMode = newValue
        }
        .onAppear {
            keyStored = keyStore.storedKey() != nil
        }
    }

    private var latxaModelInstalled: Bool {
        let url = coordinator.modelManager.expectedLocalURL(for: ModelCatalog.latxaCorrection)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keyStore.set(trimmed)
            keyStored = true
            keyErrorMessage = nil
            apiKeyInput = ""
        } catch {
            keyErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try keyStore.delete()
            keyStored = false
            keyErrorMessage = nil
        } catch {
            keyErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
