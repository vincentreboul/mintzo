import SwiftUI
import MintzoCore

// Fenêtre d'onboarding — 3 écrans, 640 × 520 pt, non redimensionnable.
// Chrome 100 % natif (amendement v1.2) : barre de titre masquée mais traffic
// lights présents, fond = windowBackgroundColor système (jamais MzPaper en
// pleine fenêtre), contrôles système. L'identité Mintzo vit dans le wordmark
// serif, les accents Gorri et la zone d'essai (surface de lecture).
// Présentée au premier lancement (porte `OnboardingGate`), refermée par
// « Amaitu » ou le bouton fermer (elle se représentera au prochain lancement
// tant que non terminée).

// MARK: - Scène

/// Déclarée dans `MintzoApp` — le hook de première ouverture tient dans le
/// `defaultLaunchBehavior` : présentée si l'onboarding n'a jamais été terminé.
struct OnboardingScene: Scene {
    let coordinator: AppCoordinator

    var body: some Scene {
        Window("Mintzo", id: "onboarding") {
            OnboardingRootView(coordinator: coordinator)
        }
        // Titre masqué mais chrome système entier : traffic lights visibles,
        // coins, ombre et fond de fenêtre standards (feel Wispr/SuperWhisper).
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
    @Environment(\.openWindow) private var openWindow

    init(coordinator: AppCoordinator) {
        _controller = State(initialValue: OnboardingController(coordinator: coordinator))
    }

    var body: some View {
        OnboardingContainerView(controller: controller) {
            controller.finish()
            // « Amaitu » présente la fenêtre principale au premier plan
            // (retour client) : l'app ne disparaît pas dans la barre de menus
            // à la fin de l'onboarding — on atterrit quelque part.
            openWindow(id: WindowSceneID.main)
            dismiss()
            NSApp.activate()
        }
        #if DEBUG
        // Capture QA : l'app accessoire lancée du terminal ne peut pas devenir
        // active (activation coopérative) → les contrôles rendraient à l'état
        // inactif. On force l'état « key » pour une capture représentative.
        .transformEnvironment(\.controlActiveState) { state in
            if ProcessInfo.processInfo.environment[OnboardingSnapshots.environmentKey] != nil {
                state = .key
            }
        }
        #endif
        .task {
            #if DEBUG
            // Harnais QA : capture la fenêtre réelle (chrome compris) puis quitte.
            // Ne PAS démarrer le polling permissions : les états QA restent figés.
            if ProcessInfo.processInfo.environment[OnboardingSnapshots.environmentKey] != nil {
                await OnboardingSnapshots.runIfRequested(controller: controller)
                return
            }
            #endif
            controller.start()
            // App accessoire (LSUIElement) : sans activation, la fenêtre
            // apparaîtrait derrière l'app frontale au premier lancement.
            NSApp.activate()
        }
        .onDisappear { controller.stop() }
    }
}

// MARK: - Conteneur (écrans + navigation)

/// Rend l'écran courant + la barre de navigation, sur le fond de fenêtre
/// système (aucun `.background` custom — amendement v1.2).
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
                .padding(.bottom, 20)
        }
        .frame(width: Metrics.windowWidth, height: Metrics.windowHeight)
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

    // MARK: Barre de navigation — boutons système uniquement (v1.2)

    private var navigationBar: some View {
        HStack {
            if controller.journey.canGoBack {
                Button(OnboardingStrings.back) {
                    withAnimation(navigationAnimation) { controller.goBack() }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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

    /// Points de page discrets : actif = Gorri (accent conservé, v1.2),
    /// inactifs = gris système quaternaire.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingScreen.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == controller.journey.screen
                          ? AnyShapeStyle(MzColor.gorri)
                          : AnyShapeStyle(.quaternary))
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
}

// MARK: - Briques typographiques partagées

/// Titre d'écran §3.2 : SF Pro Display 28/34 Bold, aligné à gauche,
/// couleur label système (le chrome n'utilise plus l'encre custom — v1.2).
struct OnboardingTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MzFont.onboardingTitle)
            .foregroundStyle(.primary)
            .lineSpacing(2)
    }
}

/// Corps §3.2 : 15/22, mesure 460 pt, couleur secondaire système par défaut.
struct OnboardingBody: View {
    let text: String
    var color: Color = Color(nsColor: .secondaryLabelColor)

    var body: some View {
        Text(text)
            .font(MzFont.onboardingBody)
            .lineSpacing(MzFont.onboardingBodyLineSpacing)
            .foregroundStyle(color)
            .frame(maxWidth: Metrics.bodyMeasure, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
