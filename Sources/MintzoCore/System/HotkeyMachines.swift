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

/// Machine d'état du raccourci configurable.
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
