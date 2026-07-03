import SwiftUI
import MintzoCore

/// Onglet Ereduak : les 3 modèles Whisper + Latxa (correction) — état installé,
/// taille, téléchargement avec progression réelle (`ModelManager.download`),
/// suppression. Les fichiers restent sur le Mac, aucun compte requis.
struct EreduakSettingsView: View {
    let library: ModelLibraryController

    var body: some View {
        Form {
            Section(SettingsStrings.transcriptionSection) {
                ForEach(whisperEntries) { entry in
                    ModelRowView(entry: entry, library: library)
                }
            }
            Section {
                ForEach(correctionEntries) { entry in
                    ModelRowView(entry: entry, library: library)
                }
            } header: {
                Text(SettingsStrings.correctionSection)
            } footer: {
                Text(SettingsStrings.modelsFolderNote)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
        .task { await library.refresh() }
    }

    private var whisperEntries: [ModelLibraryController.Entry] {
        library.entries.filter { $0.id != ModelCatalog.latxaCorrection.id }
    }

    private var correctionEntries: [ModelLibraryController.Entry] {
        library.entries.filter { $0.id == ModelCatalog.latxaCorrection.id }
    }
}

/// Rangée modèle : nom + taille/état à gauche, action à droite (Télécharger /
/// barre de progression / Supprimer). Erreur en clair sous la rangée, en Gorri.
private struct ModelRowView: View {
    let entry: ModelLibraryController.Entry
    let library: ModelLibraryController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.model.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(MzColor.inkSecondary)
                }
                Spacer(minLength: 16)
                trailingControl
            }
            if let message = entry.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.gorri)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(
            fromByteCount: entry.model.sizeBytes, countStyle: .file
        )
        let state = entry.isInstalled ? SettingsStrings.installed : SettingsStrings.notInstalled
        return "\(size) · \(state)"
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let fraction = entry.downloadFraction {
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(MzColor.gorri)
                    .frame(width: 120)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MzColor.inkSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        } else if entry.isInstalled {
            Button(SettingsStrings.remove, role: .destructive) {
                Task { await library.remove(entry.model) }
            }
            .controlSize(.small)
        } else {
            Button(SettingsStrings.download) {
                library.download(entry.model)
            }
            .controlSize(.small)
        }
    }
}
