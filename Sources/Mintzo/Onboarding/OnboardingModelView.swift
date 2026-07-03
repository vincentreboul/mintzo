import SwiftUI
import MintzoCore

/// Écran 3 · Eredua — téléchargement du modèle de la langue par défaut
/// (progression réelle sur le flux `ModelManager.download`, taille annoncée,
/// reprise d'erreur), Latxa mentionné en une ligne sobre, puis zone d'essai
/// « Proba ezazu » : une vraie dictée via le coordinator, le champ local comme
/// cible (sans Accessibilité, le texte reste sur le presse-papiers — le HUD le dit).
struct OnboardingModelView: View {
    @Bindable var controller: OnboardingController

    @FocusState private var trialFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(text: OnboardingStrings.modelTitle)
                .padding(.bottom, 10)
            OnboardingBody(text: OnboardingStrings.modelIntro)
                .padding(.bottom, 22)

            languagePicker
                .padding(.bottom, 12)

            ModelCardView(
                row: controller.modelRow,
                onDownload: { controller.downloadSelectedModel() }
            )
            .padding(.bottom, 10)

            Text(OnboardingStrings.latxaNote)
                .font(.system(size: 11))
                .foregroundStyle(MzColor.inkTertiary)
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
        .labelsHidden()
        .frame(width: 236)
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
                        .foregroundStyle(MzColor.inkSecondary)
                    Button(OnboardingStrings.openSystemSettings) {
                        controller.openMicrophoneSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .transition(.opacity)
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                trialHeader
                trialField
                HStack(alignment: .firstTextBaseline) {
                    Text(OnboardingStrings.trialHint)
                        .font(.system(size: 11))
                        .foregroundStyle(MzColor.inkTertiary)
                    Spacer(minLength: 16)
                    trialButton
                }
            }
            .transition(.opacity)
        }
    }

    private var trialHeader: some View {
        Text(OnboardingStrings.trialTitle)
            .font(MzFont.sectionHeader)
            .tracking(MzFont.sectionHeaderTracking)
            .foregroundStyle(MzColor.inkSecondary)
    }

    /// La cible de la dictée d'essai : le texte dicté y arrive en serif,
    /// comme partout dans Mintzo (§3.1 — la parole est typographiée).
    private var trialField: some View {
        TextEditor(text: $controller.trialText)
            .font(MzFont.historyExcerpt)
            .lineSpacing(MzFont.historyExcerptLineSpacing)
            .foregroundStyle(MzColor.ink)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .fill(MzColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        trialFieldFocused
                            ? MzColor.gorri.opacity(MzOpacity.activeBorder)
                            : MzColor.hairline,
                        lineWidth: trialFieldFocused ? 1 : Metrics.hairlineWidth
                    )
            )
            .overlay(alignment: .topLeading) {
                if controller.trialText.isEmpty {
                    Text(OnboardingStrings.trialPlaceholder)
                        .font(MzFont.historyExcerpt)
                        .foregroundStyle(MzColor.inkTertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .focused($trialFieldFocused)
            .animation(MzMotion.micro, value: trialFieldFocused)
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

// MARK: - Carte modèle

private struct ModelCardView: View {
    let row: OnboardingController.ModelRowState
    let onDownload: () -> Void

    var body: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.model.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MzColor.ink)
                        Text(subtitle)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(MzColor.inkSecondary)
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
            EmptyView() // la progression occupe le bas de la carte
        } else if row.isInstalled {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(OnboardingStrings.installed)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MzColor.success)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else {
            Button(row.errorMessage == nil
                   ? OnboardingStrings.download
                   : OnboardingStrings.retry, action: onDownload)
                .buttonStyle(.borderedProminent)
                .tint(MzColor.gorri)
                .controlSize(.regular)
        }
    }

    private func progressBlock(fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(MzColor.gorri)
            HStack {
                Text(OnboardingStrings.downloading)
                    .font(.system(size: 11))
                    .foregroundStyle(MzColor.inkSecondary)
                Spacer()
                Text(progressDetail(fraction: fraction))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MzColor.inkSecondary)
            }
        }
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
