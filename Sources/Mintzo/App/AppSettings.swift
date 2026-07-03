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
        static let fnKeyEnabled = "mintzo.fnKeyEnabled"
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

    static func registerDefaults(on defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            // Défaut usine : auto — la langue est détectée à la dictée (eu/fr).
            Key.language: "auto",
            Key.fallbackLanguage: Language.basque.rawValue,
            Key.fnKeyEnabled: true,
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

    static var fnKeyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.fnKeyEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.fnKeyEnabled) }
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
