import SwiftUI

/// Écran 1 · Ongi etorri — le wordmark en héros (serif Black en attendant
/// Fraunces, §3.3 : tracking −1 %), la tagline, trois promesses en une ligne
/// chacune. Aucune illustration, aucun blob : la typographie porte tout.
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
                .foregroundStyle(MzColor.ink)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            OnboardingBody(text: OnboardingStrings.tagline)
                .padding(.bottom, 44)

            VStack(alignment: .leading, spacing: 18) {
                promiseRow(symbol: "character.cursor.ibeam",
                           text: OnboardingStrings.promiseDictation)
                promiseRow(symbol: "arrow.down.doc",
                           text: OnboardingStrings.promiseFiles)
                promiseRow(symbol: "lock",
                           text: OnboardingStrings.promiseLocal)
            }

            Spacer(minLength: 0)
        }
    }

    private func promiseRow(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MzColor.gorri)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            OnboardingBody(text: text, color: MzColor.ink)
        }
    }
}
