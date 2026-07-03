import SwiftUI

/// Écran 1 · Ongi etorri — le moment wordmark : serif Black (§3.3, en
/// attendant Fraunces, tracking −1 %) posé sur le fond de fenêtre système
/// (v1.2). Les promesses sont des `Label` natifs (SF Symbols + texte SF),
/// hiérarchie HIG. Aucune illustration, aucun blob : la typographie porte tout.
struct OnboardingWelcomeView: View {

    private static let wordmarkSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(OnboardingStrings.welcomeKicker)
                .font(MzFont.sectionHeader)
                .tracking(MzFont.sectionHeaderTracking)
                .foregroundStyle(MzColor.gorri)
                .padding(.bottom, 18)

            Text(OnboardingStrings.wordmark)
                .font(.system(size: Self.wordmarkSize, weight: .black, design: .serif))
                .tracking(-0.01 * Self.wordmarkSize)
                .foregroundStyle(.primary)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            OnboardingBody(text: OnboardingStrings.tagline)
                .padding(.bottom, 44)

            VStack(alignment: .leading, spacing: 18) {
                promise(symbol: "character.cursor.ibeam",
                        text: OnboardingStrings.promiseDictation)
                promise(symbol: "arrow.down.doc",
                        text: OnboardingStrings.promiseFiles)
                promise(symbol: "lock",
                        text: OnboardingStrings.promiseLocal)
            }

            Spacer(minLength: 0)
        }
    }

    /// `Label` natif : symbole SF en Gorri (accent conservé v1.2), texte SF
    /// 15/22 en label système.
    private func promise(symbol: String, text: String) -> some View {
        Label {
            OnboardingBody(text: text, color: Color(nsColor: .labelColor))
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MzColor.gorri)
                .frame(width: 22, alignment: .center)
        }
    }
}
