import Foundation
import KeyboardShortcuts
import MintzoCore

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

    /// Variante routée par la langue de SESSION de dictée (eu/fr — jamais en) :
    /// les labels d'état de la capsule parlent la langue dictée, pas celle de
    /// l'interface (retour client : « quand on parle en basque, le texte
    /// “Transcription” doit être en basque »).
    private static func pick(_ eu: String, _ fr: String, session: HUDLanguage) -> String {
        session == .fr ? fr : eu
    }

    // MARK: HUD (§4.3, §9.2)

    /// État écoute — VoiceOver uniquement (le HUD montre la waveform, pas de label).
    static var listening: String { pick("Entzuten…", "Écoute…", "Listening…") }
    /// Langue d'UI — contextes hors capsule (ex. zone d'essai de l'onboarding).
    static var transcribing: String { pick("Transkribatzen…", "Transcription…", "Transcribing…") }
    static var correcting: String { pick("Zuzentzen…", "Correction…", "Correcting…") }
    static var inserted: String { pick("Itsatsita", "Inséré", "Inserted") }

    // Labels d'état de la capsule : langue de la SESSION en cours (celle
    // détectée/choisie au stop — celle de l'historique), résolue par
    // `HUDViewModel.labelLanguage`. Badge et timer inchangés (§4.4).
    static func transcribing(session language: HUDLanguage) -> String {
        pick("Transkribatzen…", "Transcription…", session: language)
    }

    static func correcting(session language: HUDLanguage) -> String {
        pick("Zuzentzen…", "Correction…", session: language)
    }

    static func inserted(session language: HUDLanguage) -> String {
        pick("Itsatsita", "Inséré", session: language)
    }
    /// Action VoiceOver de la capsule (§10 : la capsule est un bouton « Gelditu »).
    static var stop: String { pick("Gelditu", "Arrêter", "Stop") }
    /// Croix d'annulation de la capsule (tooltip + VoiceOver) : abandon de la
    /// session en cours, aucun texte inséré.
    static var cancel: String { pick("Utzi", "Annuler", "Cancel") }
    /// Tooltip du badge langue (§4.4) : cycle + raccourci global effectif
    /// (celui du Recorder — ⌃⌥L par défaut). Raccourci retiré : cycle seul,
    /// un tooltip ne promet pas dans le vide.
    @MainActor
    static var languageBadgeHelp: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .languageCycle) else {
            return "eu / fr / auto"
        }
        return "eu / fr / auto — \(shortcut.description)"
    }

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
