import SwiftUI
import MintzoCore

/// Écran 3 · Eredua — téléchargement du modèle de la langue par défaut
/// (progression réelle sur le flux `ModelManager.download` en `ProgressView`
/// native, taille annoncée, reprise d'erreur), Latxa mentionné en une ligne
/// sobre, puis zone d'essai « Proba ezazu » : une vraie dictée via le
/// coordinator, un `TextField` natif comme cible — le texte dicté s'y affiche
/// en serif (§3.1 : la surface de lecture garde l'identité éditoriale).
struct OnboardingModelView: View {
    @Bindable var controller: OnboardingController

    @FocusState private var trialFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(text: OnboardingStrings.modelTitle)
                .padding(.bottom, 10)
            OnboardingBody(text: OnboardingStrings.modelIntro)
                .padding(.bottom, 20)

            languagePicker
                .padding(.bottom, 12)

            ModelBox(
                row: controller.modelRow,
                onDownload: { controller.downloadSelectedModel() }
            )
            .padding(.bottom, 8)

            Text(OnboardingStrings.latxaNote)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)

            trialSection

            Spacer(minLength: 0)
        }
        .task(id: controller.selectedLanguage) {
            await controller.refreshModels()
        }
    }

    private var languagePicker: some View {
        Picker(selection: $controller.selectedLanguage) {
            Text(OnboardingStrings.languageBasque).tag(HUDLanguage.eu)
            Text(OnboardingStrings.languageFrench).tag(HUDLanguage.fr)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        // §2.1 « un seul accent » : sans tint, le segment sélectionné rend
        // BLEU système (seul contrôle bleu de l'app — vu en capture QA R3).
        .tint(MzColor.gorri)
        .labelsHidden()
        // Largeur naturelle : un frame plus large centrerait le contrôle
        // dans son cadre et le décollerait de la marge de gauche.
        .fixedSize()
    }

    // MARK: Zone d'essai

    @ViewBuilder
    private var trialSection: some View {
        switch controller.trialAvailability {
        case .missingModel:
            // Rien tant que le modèle n'est pas prêt : l'écran reste calme.
            EmptyView()
        case .microphoneDenied:
            VStack(alignment: .leading, spacing: 8) {
                trialHeader
                HStack(spacing: 10) {
                    Text(OnboardingStrings.trialNeedsMicrophone)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button(OnboardingStrings.openSystemSettings) {
                        controller.openMicrophoneSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .transition(.opacity)
        case .ready:
            VStack(alignment: .leading, spacing: 9) {
                // Le bouton d'essai vit sur la ligne du titre de section :
                // loin du « Amaitu » de la navigation, aucune concurrence
                // entre deux boutons proéminents dans le même coin.
                HStack(alignment: .firstTextBaseline) {
                    trialHeader
                    Spacer(minLength: 16)
                    trialButton
                }
                trialField
                Text(OnboardingStrings.trialHint)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .transition(.opacity)
        }
    }

    private var trialHeader: some View {
        Text(OnboardingStrings.trialTitle)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    /// La cible de la dictée d'essai : `TextField` système (bordure, focus
    /// ring et placeholder natifs) — le texte dicté y arrive en serif, comme
    /// partout dans Mintzo (§3.1 : la parole est typographiée).
    private var trialField: some View {
        TextField(
            OnboardingStrings.trialTitle,
            text: $controller.trialText,
            prompt: Text(OnboardingStrings.trialPlaceholder),
            axis: .vertical
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .lineLimit(3, reservesSpace: true)
        .font(MzFont.historyExcerpt)
        .focused($trialFieldFocused)
    }

    @ViewBuilder
    private var trialButton: some View {
        switch controller.trialPhase {
        case .idle:
            Button(OnboardingStrings.trialDictate) {
                // Le champ local devient la cible de l'insertion.
                trialFieldFocused = true
                controller.toggleTrialDictation()
            }
            .buttonStyle(.borderedProminent)
            .tint(MzColor.gorri)
        case .listening:
            Button(OnboardingStrings.trialStop) {
                controller.toggleTrialDictation()
            }
            .buttonStyle(.borderedProminent)
            .tint(MzColor.gorri)
        case .processing:
            Button(OnboardingStrings.trialProcessing) {}
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }
}

// MARK: - Boîte modèle (GroupBox système)

private struct ModelBox: View {
    let row: OnboardingController.ModelRowState
    let onDownload: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.model.displayName)
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    trailingControl
                }

                if let fraction = row.downloadFraction {
                    progressBlock(fraction: fraction)
                }

                if let message = row.errorMessage {
                    // Erreur = systemRed (§2.3) — le Gorri reste à la marque.
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        }
        .animation(MzMotion.micro, value: row.isInstalled)
        .animation(MzMotion.micro, value: row.downloadFraction == nil)
    }

    private var subtitle: String {
        ByteCountFormatter.string(fromByteCount: row.model.sizeBytes, countStyle: .file)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if row.downloadFraction != nil {
            EmptyView() // la progression occupe le bas de la boîte
        } else if row.isInstalled {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(OnboardingStrings.installed)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MzColor.success)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else if row.errorMessage == nil {
            // Le téléchargement est LA raison d'être de l'écran : seul bouton
            // proéminent du moment (la zone d'essai n'existe pas encore).
            Button(OnboardingStrings.download, action: onDownload)
                .buttonStyle(.borderedProminent)
                .tint(MzColor.gorri)
                .controlSize(.regular)
        } else {
            // Après une erreur : le texte systemRed porte déjà l'alerte, le
            // bouton reste sobre — les deux rouges ne se mélangent pas (§2.2).
            Button(OnboardingStrings.retry, action: onDownload)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }

    /// `ProgressView` linéaire système teintée Gorri, détail chiffré en
    /// `currentValueLabel` (construct natif), monospacedDigit §3.1.
    private func progressBlock(fraction: Double) -> some View {
        ProgressView(value: fraction) {
            EmptyView()
        } currentValueLabel: {
            HStack {
                Text(OnboardingStrings.downloading)
                Spacer()
                Text(progressDetail(fraction: fraction))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .tint(MzColor.gorri)
        .transition(.opacity)
    }

    private func progressDetail(fraction: Double) -> String {
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        guard let received = row.downloadedBytes else { return percent }
        let done = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: row.model.sizeBytes, countStyle: .file)
        return "\(done) / \(total) · \(percent)"
    }
}
