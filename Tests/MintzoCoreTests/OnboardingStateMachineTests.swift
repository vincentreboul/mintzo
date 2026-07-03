import XCTest
@testable import MintzoCore

// Tests de la logique pure de l'onboarding (OnboardingStateMachine.swift,
// compilé ici via symlink — comme AppCoordinatorFlow) : progression sans
// condition, bornes, sens des transitions, disponibilité de la dictée d'essai
// (modèle puis micro), mapping HUD → phase du bouton, porte de persistance.

final class OnboardingStateMachineTests: XCTestCase {

    // MARK: - Parcours : progression

    func testJourneyStartsOnWelcomeScreen() {
        let journey = OnboardingJourney()
        XCTAssertEqual(journey.screen, .ongiEtorri)
        XCTAssertTrue(journey.isFirstScreen)
        XCTAssertFalse(journey.isLastScreen)
        XCTAssertFalse(journey.canGoBack)
    }

    func testAdvanceWalksAllScreensInOrder() {
        var journey = OnboardingJourney()
        journey.advance()
        XCTAssertEqual(journey.screen, .baimenak)
        XCTAssertEqual(journey.direction, .forward)
        XCTAssertTrue(journey.canGoBack)
        journey.advance()
        XCTAssertEqual(journey.screen, .eredua)
        XCTAssertTrue(journey.isLastScreen)
    }

    /// On peut TOUJOURS avancer — aucune permission n'est requise pour
    /// progresser (l'accessibilité est optionnelle, le micro ne bloque que
    /// l'essai). `advance()` ne prend aucun état de permission en entrée :
    /// ce test verrouille l'absence de couplage.
    func testAdvanceRequiresNoPermissions() {
        var journey = OnboardingJourney()
        journey.advance() // depuis Baimenak, rien d'accordé
        journey.advance()
        XCTAssertEqual(journey.screen, .eredua)
    }

    func testAdvanceStopsAtLastScreen() {
        var journey = OnboardingJourney()
        journey.advance()
        journey.advance()
        journey.advance() // sans effet
        XCTAssertEqual(journey.screen, .eredua)
    }

    func testGoBackWalksBackwardsAndStopsAtFirstScreen() {
        var journey = OnboardingJourney()
        journey.advance()
        journey.advance()
        journey.goBack()
        XCTAssertEqual(journey.screen, .baimenak)
        XCTAssertEqual(journey.direction, .backward)
        journey.goBack()
        XCTAssertEqual(journey.screen, .ongiEtorri)
        journey.goBack() // sans effet
        XCTAssertEqual(journey.screen, .ongiEtorri)
        XCTAssertFalse(journey.canGoBack)
    }

    func testDirectionFollowsLastMove() {
        var journey = OnboardingJourney()
        journey.advance()
        XCTAssertEqual(journey.direction, .forward)
        journey.goBack()
        XCTAssertEqual(journey.direction, .backward)
        journey.advance()
        XCTAssertEqual(journey.direction, .forward)
    }

    // MARK: - Dictée d'essai : disponibilité

    func testTrialRequiresModelFirst() {
        // Sans modèle, rien à essayer — même avec le micro accordé.
        XCTAssertEqual(
            OnboardingTrial.availability(microphone: .granted, modelInstalled: false),
            .missingModel
        )
        // Le modèle manquant prime sur le micro refusé (un seul obstacle à la fois).
        XCTAssertEqual(
            OnboardingTrial.availability(microphone: .denied, modelInstalled: false),
            .missingModel
        )
    }

    func testTrialBlockedWhenMicrophoneDenied() {
        XCTAssertEqual(
            OnboardingTrial.availability(microphone: .denied, modelInstalled: true),
            .microphoneDenied
        )
    }

    func testTrialReadyWhenMicrophoneGranted() {
        XCTAssertEqual(
            OnboardingTrial.availability(microphone: .granted, modelInstalled: true),
            .ready
        )
    }

    /// `notDetermined` ne bloque pas : le flux de dictée affiche le prompt
    /// système au premier déclenchement.
    func testTrialReadyWhenMicrophoneNeverAsked() {
        XCTAssertEqual(
            OnboardingTrial.availability(microphone: .notDetermined, modelInstalled: true),
            .ready
        )
    }

    // MARK: - Dictée d'essai : phase du bouton (dérivée de l'état HUD)

    func testTrialPhaseMapsHUDStates() {
        XCTAssertEqual(OnboardingTrial.phase(for: .idle), .idle)
        XCTAssertEqual(OnboardingTrial.phase(for: .success), .idle)
        XCTAssertEqual(OnboardingTrial.phase(for: .error(message: "Eredua falta da.")), .idle)
        XCTAssertEqual(OnboardingTrial.phase(for: .listening), .listening)
        XCTAssertEqual(OnboardingTrial.phase(for: .transcribing), .processing)
        XCTAssertEqual(OnboardingTrial.phase(for: .correcting), .processing)
    }

    // MARK: - Porte de première ouverture

    func testGatePersistsCompletion() throws {
        let suiteName = "eus.mintzo.tests.onboarding-gate"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertFalse(OnboardingGate.hasCompleted(defaults: defaults),
                       "jamais terminé → la fenêtre doit se présenter")
        OnboardingGate.markCompleted(defaults: defaults)
        XCTAssertTrue(OnboardingGate.hasCompleted(defaults: defaults),
                      "terminé → la fenêtre ne se représente plus")
    }
}
