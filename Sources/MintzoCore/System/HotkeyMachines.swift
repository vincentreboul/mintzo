import Foundation

/// Événement hotkey consommé par l'orchestrateur de dictée.
public enum HotkeyEvent: Sendable, Equatable {
    /// Début d'un maintien (push-to-talk) : ouvrir le micro.
    case pressBegan
    /// Fin du maintien : fermer le micro et transcrire.
    case pressEnded
    /// Bascule (mode toggle) : inverser l'état d'écoute.
    case toggled
}

/// Comportement du raccourci configurable.
public enum ActivationMode: Sendable, Equatable {
    /// Maintien = écoute (keyDown → pressBegan, keyUp → pressEnded).
    case pushToTalk
    /// Chaque appui inverse l'état (keyDown → toggled).
    case toggle
}

/// Transition brute d'une touche de raccourci.
public enum KeyTransition: Sendable, Equatable {
    case down
    case up
}

/// Transition brute de la touche Fn/Globe, horodatée par la source
/// (les timestamps rendent le debounce testable sans horloge réelle).
public enum FnKeyTransition: Sendable, Equatable {
    case down(at: TimeInterval)
    case up(at: TimeInterval)
}

/// Machine d'état du raccourci configurable (mode a).
///
/// Pure : aucune dépendance système, testée par événements injectés (les
/// timestamps sont fournis par l'appelant, jamais lus sur une horloge).
/// Déduplique les transitions répétées (auto-repeat, doubles handlers).
///
/// Mode toggle : anti-rebond — un ré-appui < `toggleDebounce` (300 ms) après
/// le dernier `toggled` émis est absorbé (double-clic nerveux, rebond
/// matériel : la session ne doit pas démarrer PUIS stopper aussitôt). Un
/// appui absorbé ne ré-arme pas le délai : passé 300 ms après le dernier
/// toggle réussi, l'appui suivant passe toujours.
struct ShortcutActivationMachine: Sendable {
    let mode: ActivationMode
    let toggleDebounce: TimeInterval
    private var isDown = false
    private var lastToggleAt: TimeInterval?

    init(mode: ActivationMode, toggleDebounce: TimeInterval = 0.3) {
        self.mode = mode
        self.toggleDebounce = toggleDebounce
    }

    mutating func process(_ transition: KeyTransition, at time: TimeInterval) -> HotkeyEvent? {
        switch (transition, mode) {
        case (.down, .pushToTalk):
            guard !isDown else { return nil }
            isDown = true
            return .pressBegan
        case (.up, .pushToTalk):
            guard isDown else { return nil }
            isDown = false
            return .pressEnded
        case (.down, .toggle):
            // Dédup AVANT debounce : un auto-repeat (down répété sans up)
            // reste muet même une fois le délai anti-rebond écoulé.
            guard !isDown else { return nil }
            isDown = true
            if let lastToggleAt, time - lastToggleAt < toggleDebounce { return nil }
            lastToggleAt = time
            return .toggled
        case (.up, .toggle):
            isDown = false
            return nil
        }
    }
}

/// Machine d'état du mode « touche Fn maintenue » (mode b).
///
/// Règles (notes/research/mac-stack.md §2, pattern Speak2) :
/// - maintien ≥ seuil (150 ms) → push-to-talk (`pressBegan` au franchissement
///   du seuil, `pressEnded` au relâchement) ;
/// - tap bref < seuil → ignoré (le comportement système de la touche Fn,
///   émoji/dictée Apple, reste intact — le tap est listen-only) ;
/// - debounce : les `flagsChanged` dupliqués d'un même appui sont ignorés
///   (dédup par état), et un ré-appui immédiat après relâchement (rebond
///   matériel) est absorbé.
///
/// Pure et pilotée par effets : la machine ne possède aucun timer — elle
/// demande `scheduleHoldTimer` et reçoit `holdTimerFired` en retour. Les
/// timers périmés (tap bref, nouvel appui) sont neutralisés par identifiant.
struct FnHoldMachine: Sendable {
    enum Input: Sendable, Equatable {
        case fnDown(at: TimeInterval)
        case fnUp(at: TimeInterval)
        case holdTimerFired(id: UInt64)
    }

    enum Effect: Sendable, Equatable {
        /// Planifier un rappel `holdTimerFired(id)` dans `after` secondes.
        case scheduleHoldTimer(id: UInt64, after: TimeInterval)
        case emit(HotkeyEvent)
    }

    private enum Phase: Sendable, Equatable {
        case idle
        case waitingHold(timerID: UInt64)
        case holding
    }

    let holdThreshold: TimeInterval
    let reengageDebounce: TimeInterval

    private var phase: Phase = .idle
    private var lastUpAt: TimeInterval?
    private var nextTimerID: UInt64 = 0

    init(holdThreshold: TimeInterval = 0.15, reengageDebounce: TimeInterval = 0.05) {
        self.holdThreshold = holdThreshold
        self.reengageDebounce = reengageDebounce
    }

    mutating func process(_ input: Input) -> [Effect] {
        switch input {
        case .fnDown(let at):
            // Dédup : déjà enfoncée (flagsChanged multiples par appui perçu).
            guard phase == .idle else { return [] }
            // Anti-rebond : ré-appui immédiat après un relâchement.
            if let lastUpAt, at - lastUpAt < reengageDebounce { return [] }
            nextTimerID += 1
            phase = .waitingHold(timerID: nextTimerID)
            return [.scheduleHoldTimer(id: nextTimerID, after: holdThreshold)]

        case .fnUp(let at):
            switch phase {
            case .idle:
                return []
            case .waitingHold:
                // Tap bref < seuil : ignoré, le timer devenu périmé sera
                // neutralisé par son identifiant.
                phase = .idle
                lastUpAt = at
                return []
            case .holding:
                phase = .idle
                lastUpAt = at
                return [.emit(.pressEnded)]
            }

        case .holdTimerFired(let id):
            // Ne franchit le seuil que si ce timer est CELUI de l'appui en
            // cours (un timer d'un appui précédent est périmé).
            guard case .waitingHold(let timerID) = phase, timerID == id else { return [] }
            phase = .holding
            return [.emit(.pressBegan)]
        }
    }
}
