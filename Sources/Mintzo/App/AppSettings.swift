import Foundation
import MintzoCore

// Réglages persistés (UserDefaults) — source unique lue par le coordinator et
// par l'UI de réglages. Le raccourci de dictée n'apparaît pas ici : il est
// stocké par le package KeyboardShortcuts sous son propre identifiant.

enum AppSettings {

    enum Key {
        /// Langue de dictée courante ET défaut au lancement (une seule vérité).
        static let language = "mintzo.language"
        /// Langue de repli du mode auto (confiance faible, modèle de détection
        /// absent) — dernière langue explicite choisie par l'utilisateur.
        static let fallbackLanguage = "mintzo.fallbackLanguage"
        /// Comportement du raccourci de dictée : appui simple (toggle) ou
        /// maintien (push-to-talk).
        static let shortcutBehavior = "mintzo.shortcutBehavior"
        /// `true` = insertion au curseur ; `false` = clipboard seul.
        static let autoInsert = "mintzo.autoInsert"
        static let correctionMode = "mintzo.correctionMode"
    }

    /// Moteur de la passe de correction post-ASR.
    enum CorrectionMode: String, CaseIterable {
        case off
        case latxa
        case cloud
    }

    /// Comportement du raccourci de dictée configurable (retour client :
    /// « comme SuperWhisper — j'appuie une fois, ça lance, je rappuie pour
    /// arrêter »).
    enum ShortcutBehavior: String, CaseIterable {
        /// Appui simple : un appui démarre, le suivant stoppe et transcrit.
        case pressOnce
        /// Maintien (push-to-talk) : écoute tant que le raccourci est enfoncé.
        case hold

        var activationMode: ActivationMode {
            switch self {
            case .pressOnce: .toggle
            case .hold: .pushToTalk
            }
        }
    }

    static func registerDefaults(on defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            // Défaut usine : auto — la langue est détectée à la dictée (eu/fr).
            Key.language: "auto",
            Key.fallbackLanguage: Language.basque.rawValue,
            // Défaut usine : appui simple (préférence explicite du client).
            Key.shortcutBehavior: ShortcutBehavior.pressOnce.rawValue,
            Key.autoInsert: true,
            Key.correctionMode: CorrectionMode.off.rawValue,
        ])
    }

    static var language: HUDLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.language) ?? "auto"
            return HUDLanguage(rawValue: raw) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.language) }
    }

    /// Langue de repli du mode auto : suit la dernière langue EXPLICITE choisie
    /// par l'utilisateur (badge, popover, réglages, choix du modèle d'onboarding).
    static var fallbackLanguage: Language {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.fallbackLanguage)
            return raw.flatMap(Language.init(rawValue:)) ?? .basque
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.fallbackLanguage) }
    }

    static var shortcutBehavior: ShortcutBehavior {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.shortcutBehavior)
            return raw.flatMap(ShortcutBehavior.init(rawValue:)) ?? .pressOnce
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.shortcutBehavior) }
    }

    static var autoInsert: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoInsert) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoInsert) }
    }

    static var correctionMode: CorrectionMode {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.correctionMode) ?? "off"
            return CorrectionMode(rawValue: raw) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.correctionMode) }
    }
}
