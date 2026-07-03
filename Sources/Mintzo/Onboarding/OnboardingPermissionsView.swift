import SwiftUI
import MintzoCore

/// Écran 2 · Baimenak — deux cartes à état LIVE (polling `PermissionsService`).
/// Honnêteté structurelle §9 : chaque carte dit POURQUOI et ce qui ne sort pas
/// du Mac. L'accessibilité est optionnelle — on peut continuer sans (le texte
/// reste alors sur le presse-papiers).
struct OnboardingPermissionsView: View {
    var controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(text: OnboardingStrings.permissionsTitle)
                .padding(.bottom, 10)
            OnboardingBody(text: OnboardingStrings.permissionsIntro)
                .padding(.bottom, 26)

            PermissionCardView(
                symbol: "mic",
                title: OnboardingStrings.microphoneTitle,
                badge: OnboardingStrings.microphoneRequiredBadge,
                badgeIsAccent: true,
                explanation: OnboardingStrings.microphoneBody,
                footnote: nil,
                status: controller.permissions.microphone,
                actionTitle: controller.permissions.microphone == .notDetermined
                    ? OnboardingStrings.microphoneAllow
                    : OnboardingStrings.openSystemSettings,
                action: {
                    if controller.permissions.microphone == .notDetermined {
                        controller.requestMicrophone()
                    } else {
                        controller.openMicrophoneSettings()
                    }
                }
            )
            .padding(.bottom, 14)

            PermissionCardView(
                symbol: "accessibility",
                title: OnboardingStrings.accessibilityTitle,
                badge: OnboardingStrings.accessibilityOptionalBadge,
                badgeIsAccent: false,
                explanation: OnboardingStrings.accessibilityBody,
                footnote: OnboardingStrings.accessibilityWithout,
                status: controller.permissions.accessibility,
                actionTitle: OnboardingStrings.accessibilityAllow,
                action: { controller.requestAccessibility() }
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Carte permission

private struct PermissionCardView: View {
    let symbol: String
    let title: String
    let badge: String
    let badgeIsAccent: Bool
    let explanation: String
    let footnote: String?
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    init(symbol: String, title: String, badge: String, badgeIsAccent: Bool,
         explanation: String, footnote: String?, status: PermissionStatus,
         actionTitle: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.badgeIsAccent = badgeIsAccent
        self.explanation = explanation
        self.footnote = footnote
        self.status = status
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        OnboardingCard {
            HStack(alignment: .top, spacing: 14) {
                symbolTile
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MzColor.ink)
                        badgeView
                    }
                    Text(explanation)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(MzColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let footnote {
                        Text(footnote)
                            .font(.system(size: 11))
                            .lineSpacing(2)
                            .foregroundStyle(MzColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 14)
                statusView
            }
        }
        .animation(MzMotion.micro, value: status)
    }

    private var symbolTile: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(MzColor.gorri)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MzColor.gorri.opacity(MzOpacity.subtle))
            )
            .accessibilityHidden(true)
    }

    private var badgeView: some View {
        Text(badge)
            .font(MzFont.historyMetaTag)
            .foregroundStyle(badgeIsAccent ? MzColor.gorri : MzColor.inkSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(badgeIsAccent
                          ? MzColor.gorri.opacity(MzOpacity.tint)
                          : MzColor.surfaceHover)
            )
    }

    @ViewBuilder
    private var statusView: some View {
        if status == .granted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(OnboardingStrings.granted)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MzColor.success)
            .padding(.vertical, 3)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else {
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .transition(.opacity)
        }
    }
}
