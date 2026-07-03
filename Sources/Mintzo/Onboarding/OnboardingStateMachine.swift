import Foundation
import MintzoCore

// Logique PURE de l'onboarding (Foundation + MintzoCore, pas de SwiftUI/AppKit).
// Compilée aussi dans MintzoCoreTests via symlink
// (Tests/MintzoCoreTests/OnboardingStateMachine.swift), comme AppCoordinatorFlow.
//
// Règles de progression (brief onboarding) :
// - on peut TOUJOURS avancer, avec ou sans permissions (l'accessibilité est
//   optionnelle, le micro n'est bloquant que pour la dictée d'essai) ;
// - la dictée d'essai exige un modèle installé + un micro non refusé
//   (`notDetermined` suffit : le flux de dictée demande la permission au vol) ;
// - « Amaitu » est disponible à tout moment sur le dernier écran — l'onboarding
//   ne prend jamais l'utilisateur en otage.

// MARK: - Écrans

/// Les trois écrans, dans l'ordre du parcours.
enum OnboardingScreen: Int, CaseIterable, Equatable, Sendable {
    case ongiEtorri = 0
    case baimenak = 1
    case eredua = 2
}

// MARK: - Parcours

/// Position dans le parcours + sens du dernier déplacement (pour les
/// transitions directionnelles de la vue).
struct OnboardingJourney: Equatable, Sendable {

    enum Direction: Equatable, Sendable {
        case forward
        case backward
    }

    private(set) var screen: OnboardingScreen = .ongiEtorri
    private(set) var direction: Direction = .forward

    var isFirstScreen: Bool { screen == .ongiEtorri }
    var isLastScreen: Bool { screen == .eredua }
    var canGoBack: Bool { !isFirstScreen }

    /// Avance d'un écran. Sans condition : aucune permission n'est requise
    /// pour progresser. Sans effet sur le dernier écran.
    mutating func advance() {
        guard let next = OnboardingScreen(rawValue: screen.rawValue + 1) else { return }
        screen = next
        direction = .forward
    }

    /// Recule d'un écran. Sans effet sur le premier.
    mutating func goBack() {
        guard let previous = OnboardingScreen(rawValue: screen.rawValue - 1) else { return }
        screen = previous
        direction = .backward
    }
}

// MARK: - Dictée d'essai

/// Conditions et état de la zone « Proba ezazu » (écran 3).
enum OnboardingTrial {

    /// Ce qui manque (ou non) pour lancer une dictée d'essai.
    enum Availability: Equatable, Sendable {
        /// Prêt : modèle installé, micro accordé ou jamais demandé.
        case ready
        /// Le modèle de la langue choisie n'est pas installé.
        case missingModel
        /// Micro explicitement refusé — l'essai est impossible tant que la
        /// permission n'est pas accordée dans Réglages Système.
        case microphoneDenied
    }

    /// Le modèle prime (sans lui, rien à essayer), puis le micro.
    /// `notDetermined` ne bloque pas : le flux de dictée affiche le prompt
    /// système au premier déclenchement.
    static func availability(
        microphone: PermissionStatus,
        modelInstalled: Bool
    ) -> Availability {
        guard modelInstalled else { return .missingModel }
        guard microphone != .denied else { return .microphoneDenied }
        return .ready
    }

    /// Phase du bouton d'essai, dérivée de l'état du HUD (source de vérité de
    /// la session de dictée).
    enum Phase: Equatable, Sendable {
        /// Aucune session : bouton « Diktatu ».
        case idle
        /// Écoute en cours : bouton « Gelditu ».
        case listening
        /// Transcription/correction : bouton inactif.
        case processing
    }

    static func phase(for hudState: HUDState) -> Phase {
        switch hudState {
        case .idle, .success, .error:
            .idle
        case .listening:
            .listening
        case .transcribing, .correcting:
            .processing
        }
    }
}

// MARK: - Porte de première ouverture

/// Persistance du « déjà vu » de l'onboarding. Clé lue par `MintzoApp` au
/// lancement (fenêtre présentée ou non) et écrite par « Amaitu ».
/// QA : surchargée en ligne de commande via `-mintzo.hasCompletedOnboarding 0`.
enum OnboardingGate {
    static let defaultsKey = "mintzo.hasCompletedOnboarding"

    static func hasCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }
}
