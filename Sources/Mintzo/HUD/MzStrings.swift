import Foundation

// Microcopy HUD + menu bar — chaînes canoniques du design language §9.2.
// Langue : euskara batua si le système est en eu, sinon français, sinon anglais (§9.1).
// Ton : sobre, zéro point d'exclamation, ellipse typographique « … » (U+2026),
// apostrophe « ' » (U+2019), pas de point final sur les labels.

enum MzStrings {
    enum UILanguage: String { case eu, fr, en }

    /// Langue de l'interface, résolue une fois au lancement.
    /// DEBUG : forçable via l'env `MINTZO_UI_LANG=eu|fr|en` (screenshots, QA).
    static let ui: UILanguage = {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["MINTZO_UI_LANG"],
           let lang = UILanguage(rawValue: forced) {
            return lang
        }
        #endif
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("eu") { return .eu }
            if preferred.hasPrefix("fr") { return .fr }
        }
        return .en
    }()

    private static func pick(_ eu: String, _ fr: String, _ en: String) -> String {
        switch ui {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }

    // MARK: HUD (§4.3, §9.2)

    /// État écoute — VoiceOver uniquement (le HUD montre la waveform, pas de label).
    static var listening: String { pick("Entzuten…", "Écoute…", "Listening…") }
    static var transcribing: String { pick("Transkribatzen…", "Transcription…", "Transcribing…") }
    static var correcting: String { pick("Zuzentzen…", "Correction…", "Correcting…") }
    static var inserted: String { pick("Itsatsita", "Inséré", "Inserted") }
    /// Action VoiceOver de la capsule (§10 : la capsule est un bouton « Gelditu »).
    static var stop: String { pick("Gelditu", "Arrêter", "Stop") }
    /// Tooltip du badge langue (§4.4).
    static var languageBadgeHelp: String { "eu / fr / auto — ⌃⌥L" }

    // MARK: Menu bar (§5.3)

    static var dictate: String { pick("Diktatu", "Dicter", "Dictate") }
    static var openMintzo: String { pick("Ireki Mintzo", "Ouvrir Mintzo", "Open Mintzo") }
    static var transcribeFile: String { pick("Fitxategia transkribatu…", "Transcrire un fichier…", "Transcribe a file…") }
    static var settings: String { pick("Ezarpenak…", "Réglages…", "Settings…") }
    static var quit: String { pick("Irten", "Quitter", "Quit") }
    /// Ligne d'état du popover (placeholder vague 3 : état réel du modèle).
    static var modelReady: String { pick("eredua prest", "modèle prêt", "model ready") }
    static var languageAuto: String { pick("auto", "auto", "auto") }
}
