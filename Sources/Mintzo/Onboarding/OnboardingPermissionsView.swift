import SwiftUI
import MintzoCore

/// Écran 2 · Baimenak — deux `GroupBox` natifs (v1.2) à état LIVE (polling
/// `PermissionsService`). Honnêteté structurelle §9 : chaque boîte dit POURQUOI
/// et ce qui ne sort pas du Mac. L'accessibilité est optionnelle — on peut
/// continuer sans (le texte reste alors sur le presse-papiers).
struct OnboardingPermissionsView: View {
    var controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(text: OnboardingStrings.permissionsTitle)
                .padding(.bottom, 10)
            OnboardingBody(text: OnboardingStrings.permissionsIntro)
                .padding(.bottom, 24)

            PermissionBox(
                symbol: "mic",
                title: OnboardingStrings.microphoneTitle,
                badge: OnboardingStrings.microphoneRequiredBadge,
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
            .padding(.bottom, 12)

            PermissionBox(
                symbol: "accessibility",
                title: OnboardingStrings.accessibilityTitle,
                badge: OnboardingStrings.accessibilityOptionalBadge,
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

// MARK: - Boîte permission (GroupBox système)

private struct PermissionBox: View {
    let symbol: String
    let title: String
    let badge: String
    let explanation: String
    let footnote: String?
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(MzColor.gorri)
                    .frame(width: 30, height: 24, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(title)
                            .font(.headline)
                        Text(badge)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(explanation)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let footnote {
                        Text(footnote)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 14)
                statusView
            }
            .padding(6)
        }
        .animation(MzMotion.micro, value: status)
    }

    @ViewBuilder
    private var statusView: some View {
        if status == .granted {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
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
