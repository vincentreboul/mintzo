import SwiftUI
import MintzoCore

// Fenêtre d'onboarding — 3 écrans, 640 × 520 pt, non redimensionnable, fond
// MzPaper opaque (contenu = jamais de verre, §2.5). Présentée au premier
// lancement (porte `OnboardingGate`), refermée par « Amaitu » ou le bouton
// fermer (elle se représentera au prochain lancement tant que non terminée).

// MARK: - Scène

/// Déclarée dans `MintzoApp` — le hook de première ouverture tient dans le
/// `defaultLaunchBehavior` : présentée si l'onboarding n'a jamais été terminé.
struct OnboardingScene: Scene {
    let coordinator: AppCoordinator

    var body: some Scene {
        Window("Mintzo", id: "onboarding") {
            OnboardingRootView(coordinator: coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(OnboardingGate.hasCompleted() ? .suppressed : .presented)
        .restorationBehavior(.disabled)
    }
}

// MARK: - Racine (cycle de vie)

struct OnboardingRootView: View {
    @State private var controller: OnboardingController
    @Environment(\.dismiss) private var dismiss

    init(coordinator: AppCoordinator) {
        _controller = State(initialValue: OnboardingController(coordinator: coordinator))
    }

    var body: some View {
        OnboardingContainerView(controller: controller) {
            controller.finish()
            dismiss()
        }
        #if DEBUG
        // Capture QA : l'app accessoire lancée du terminal ne peut pas devenir
        // active (activation coopérative) → les contrôles rendraient à l'état
        // inactif. On force l'état « key » pour une capture représentative.
        .transformEnvironment(\.controlActiveState) { state in
            if ProcessInfo.processInfo.environment[OnboardingSnapshots.liveEnvironmentKey] != nil {
                state = .key
            }
        }
        #endif
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment[OnboardingSnapshots.environmentKey] != nil {
                await OnboardingSnapshots.runIfRequested(controller: controller)
                return
            }
            // QA live : `MINTZO_ONBOARDING_SCREEN=baimenak|eredua` ouvre la
            // fenêtre réelle directement sur un écran (capture des contrôles
            // AppKit que ImageRenderer ne rastérise pas).
            if let target = ProcessInfo.processInfo.environment["MINTZO_ONBOARDING_SCREEN"] {
                let screen: OnboardingScreen? = switch target {
                case "baimenak": .baimenak
                case "eredua": .eredua
                default: nil
                }
                if let screen {
                    while controller.journey.screen != screen { controller.advance() }
                }
            }
            #endif
            controller.start()
            #if DEBUG
            await OnboardingSnapshots.runLiveCaptureIfRequested(controller: controller)
            #endif
            // App accessoire (LSUIElement) : sans activation, la fenêtre
            // apparaîtrait derrière l'app frontale au premier lancement.
            NSApp.activate()
        }
        .onDisappear { controller.stop() }
    }
}

// MARK: - Conteneur (écrans + navigation)

/// Rend l'écran courant + la barre de navigation. Séparé de la racine pour
/// être rendable tel quel par le harnais de snapshots QA (états figés).
struct OnboardingContainerView: View {
    @Bindable var controller: OnboardingController
    var onFinish: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                screen
                    .padding(.horizontal, Metrics.marginH)
                    .padding(.top, Metrics.marginTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipped()
            navigationBar
                .padding(.horizontal, Metrics.marginH)
                .padding(.bottom, 22)
        }
        .frame(width: Metrics.windowWidth, height: Metrics.windowHeight)
        .background(MzColor.paper)
    }

    // MARK: Écran courant

    @ViewBuilder
    private var screen: some View {
        switch controller.journey.screen {
        case .ongiEtorri:
            OnboardingWelcomeView()
                .transition(screenTransition)
        case .baimenak:
            OnboardingPermissionsView(controller: controller)
                .transition(screenTransition)
        case .eredua:
            OnboardingModelView(controller: controller)
                .transition(screenTransition)
        }
    }

    /// §7 : l'écran entrant se pose (léger glissé 28 pt + fondu), jamais de
    /// bounce. Reduce Motion → crossfade pur.
    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let forward = controller.journey.direction == .forward
        return .asymmetric(
            insertion: .offset(x: forward ? Metrics.slideDistance : -Metrics.slideDistance)
                .combined(with: .opacity),
            removal: .offset(x: forward ? -Metrics.slideDistance : Metrics.slideDistance)
                .combined(with: .opacity)
        )
    }

    private var navigationAnimation: Animation {
        reduceMotion ? MzMotion.micro : MzMotion.morph
    }

    // MARK: Barre de navigation

    private var navigationBar: some View {
        HStack {
            if controller.journey.canGoBack {
                OnboardingBackButton(title: OnboardingStrings.back) {
                    withAnimation(navigationAnimation) { controller.goBack() }
                }
                .transition(.opacity)
            }
            Spacer()
            primaryButton
        }
        .animation(MzMotion.micro, value: controller.journey.canGoBack)
        .overlay(alignment: .center) { progressDots }
        .frame(height: 34)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if controller.journey.isLastScreen {
            Button(OnboardingStrings.finish) { onFinish() }
                .buttonStyle(.borderedProminent)
                .tint(MzColor.gorri)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        } else {
            Button(OnboardingStrings.next) {
                withAnimation(navigationAnimation) { controller.advance() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MzColor.gorri)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingScreen.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == controller.journey.screen
                          ? AnyShapeStyle(MzColor.gorri)
                          : AnyShapeStyle(MzColor.inkTertiary.opacity(0.35)))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(MzMotion.micro, value: controller.journey.screen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingStrings.progressLabel(
            step: controller.journey.screen.rawValue + 1,
            of: OnboardingScreen.allCases.count
        ))
    }
}

// MARK: - Bouton retour (texte discret, hover encre)

private struct OnboardingBackButton: View {
    let title: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(hovered ? MzColor.ink : MzColor.inkSecondary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MzMotion.micro) { hovered = hovering }
        }
    }
}

// MARK: - Métriques partagées des écrans

enum Metrics {
    static let windowWidth: CGFloat = 640
    static let windowHeight: CGFloat = 520
    /// Marges généreuses, alignement gauche (convention Tahoe §3.2).
    static let marginH: CGFloat = 48
    /// Dégage les feux tricolores de la barre de titre masquée.
    static let marginTop: CGFloat = 52
    /// Mesure maximale du corps de texte (§3.2 : 460 pt).
    static let bodyMeasure: CGFloat = 460
    /// Glissé des transitions d'écran — se pose, ne balaye pas.
    static let slideDistance: CGFloat = 28

    static let cardCornerRadius: CGFloat = 10
    static let hairlineWidth: CGFloat = 0.5
}

// MARK: - Briques typographiques partagées

/// Titre d'écran §3.2 : SF Pro Display 28/34 Bold, aligné à gauche.
struct OnboardingTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MzFont.onboardingTitle)
            .foregroundStyle(MzColor.ink)
            .lineSpacing(2)
    }
}

/// Corps §3.2 : 15/22, mesure 460 pt.
struct OnboardingBody: View {
    let text: String
    var color: Color = MzColor.inkSecondary

    var body: some View {
        Text(text)
            .font(MzFont.onboardingBody)
            .lineSpacing(MzFont.onboardingBodyLineSpacing)
            .foregroundStyle(color)
            .frame(maxWidth: Metrics.bodyMeasure, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Carte opaque sur papier : surface, rayon 10, hairline 0,5 pt (§6.3).
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .fill(MzColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(MzColor.hairline, lineWidth: Metrics.hairlineWidth)
            )
    }
}
