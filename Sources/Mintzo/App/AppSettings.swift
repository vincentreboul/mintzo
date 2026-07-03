import Foundation

// Réglages persistés (UserDefaults) — source unique lue par le coordinator et
// par l'UI de réglages. Le raccourci de dictée n'apparaît pas ici : il est
// stocké par le package KeyboardShortcuts sous son propre identifiant.

enum AppSettings {

    enum Key {
        /// Langue de dictée courante ET défaut au lancement (une seule vérité).
        static let language = "mintzo.language"
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
            Key.language: "eu",
            Key.fnKeyEnabled: true,
            Key.autoInsert: true,
            Key.correctionMode: CorrectionMode.off.rawValue,
        ])
    }

    static var language: HUDLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.language) ?? "eu"
            let value = HUDLanguage(rawValue: raw) ?? .eu
            return value == .auto ? .eu : value // auto masqué V1 (whisper_full_lang_id pas exposé)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.language) }
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
