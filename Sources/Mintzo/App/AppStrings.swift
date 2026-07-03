import Foundation
import MintzoCore

// Microcopy du coordinator (erreurs HUD, replis) — design-language §9.1/§9.2 :
// sobre, zéro point d'exclamation, formes courtes pour la capsule d'erreur
// (largeur plafonnée à 320 pt). Résolution de langue partagée avec MzStrings.

enum AppStrings {

    private static func pick(_ eu: String, _ fr: String, _ en: String) -> String {
        switch MzStrings.ui {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }

    /// Modèle de la langue demandée absent (§9.2 « eredua falta da », forme courte HUD).
    static func modelMissing(for language: Language) -> String {
        switch language {
        case .basque:
            pick("Euskarazko eredua falta da.",
                 "Le modèle basque n'est pas installé.",
                 "The Basque model isn't installed.")
        case .french:
            pick("Frantsesezko eredua falta da.",
                 "Le modèle français n'est pas installé.",
                 "The French model isn't installed.")
        }
    }

    /// Permission micro absente ou refusée (§9.2, forme titre).
    static var microphoneNeeded: String {
        pick("Mikrofonoa behar dugu.",
             "Le micro est nécessaire.",
             "Microphone needed.")
    }

    /// La capture n'a pas démarré (device/engine).
    static var captureFailed: String {
        pick("Mikrofonoak huts egin du.",
             "Le micro n'a pas démarré.",
             "Microphone failed to start.")
    }

    /// La transcription a échoué (le détail technique part dans le log, pas le HUD).
    static var transcriptionFailed: String {
        pick("Transkripzioak huts egin du.",
             "La transcription a échoué.",
             "Transcription failed.")
    }

    /// Texte livré sur le clipboard seulement (réglage ou repli) — état HUD
    /// `.success` à message custom, tenu 1,5 s (§4.3 état 4). Forme courte,
    /// pas de point final (label, §9.1). Routé par la langue de la SESSION
    /// (comme les autres labels d'état de la capsule — retour client),
    /// jamais par la langue de l'interface.
    static func clipboardSuccess(session language: HUDLanguage) -> String {
        language == .fr
            ? "Presse-papiers — collez avec ⌘V"
            : "Arbelean — sakatu ⌘V"
    }
}
