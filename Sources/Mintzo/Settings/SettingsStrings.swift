import Foundation

// Microcopy des réglages — §9.1 : euskara batua / français (formes impersonnelles,
// vous si inévitable) / anglais. Sobre, zéro point d'exclamation, zéro emoji.
// Labels sans point final ; explications = phrases ponctuées.

enum SettingsStrings {

    private static func pick(_ eu: String, _ fr: String, _ en: String) -> String {
        switch MzStrings.ui {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }

    // MARK: Onglets

    static var tabOrokorra: String { pick("Orokorra", "Général", "General") }
    static var tabEreduak: String { pick("Ereduak", "Modèles", "Models") }
    static var tabZuzenketa: String { pick("Zuzenketa", "Correction", "Correction") }

    // MARK: Orokorra

    static var languageLabel: String {
        pick("Hizkuntza lehenetsia", "Langue par défaut", "Default language")
    }
    static var shortcutLabel: String {
        pick("Diktaketa-lasterbidea", "Raccourci de dictée", "Dictation shortcut")
    }
    static var shortcutBehaviorLabel: String {
        pick("Lasterbidearen portaera", "Comportement du raccourci", "Shortcut behavior")
    }
    static var shortcutBehaviorPressOnce: String {
        pick("Sakatu behin", "Appui simple", "Press once")
    }
    static var shortcutBehaviorHold: String {
        pick("Eduki sakatuta", "Maintenir", "Hold")
    }
    static var shortcutBehaviorPressOnceNote: String {
        pick("Sakatze batek grabaketa abiarazten du; hurrengoak gelditu eta transkribatzen du.",
             "Un appui démarre l'enregistrement ; le suivant l'arrête et transcrit.",
             "One press starts recording; the next one stops and transcribes.")
    }
    static var shortcutBehaviorHoldNote: String {
        pick("Lasterbidea sakatuta dagoen bitartean grabatzen da; askatzean transkribatzen da.",
             "L'enregistrement dure tant que le raccourci est maintenu ; le relâcher transcrit.",
             "Recording lasts while the shortcut is held; releasing it transcribes.")
    }
    static var fnToggle: String {
        pick("Fn tekla sakatuta diktatu",
             "Dicter en maintenant la touche Fn",
             "Dictate by holding the Fn key")
    }
    static var fnPermissionNote: String {
        pick("Fn teklak Irisgarritasuna baimena behar du. Teklatua ez da inoiz grabatzen.",
             "La touche Fn requiert l'autorisation Accessibilité. Le clavier n'est jamais enregistré.",
             "The Fn key requires the Accessibility permission. The keyboard is never recorded.")
    }
    static var accessibilityGranted: String {
        pick("Irisgarritasuna: emanda", "Accessibilité : accordée", "Accessibility: granted")
    }
    static var accessibilityMissing: String {
        pick("Irisgarritasuna: falta da", "Accessibilité : manquante", "Accessibility: missing")
    }
    static var openSystemSettings: String {
        pick("Ireki Sistemaren ezarpenak", "Ouvrir les Réglages Système", "Open System Settings")
    }
    static var autoInsertToggle: String {
        pick("Testua kurtsorean itsatsi",
             "Insérer le texte au curseur",
             "Insert text at the cursor")
    }
    static var autoInsertNote: String {
        pick("Desaktibatuta: testua arbelean geratzen da, ⌘V-rekin itsasteko.",
             "Désactivé : le texte reste dans le presse-papiers, à coller avec ⌘V.",
             "Off: text stays on the clipboard, paste it with ⌘V.")
    }
    static var loginItemToggle: String {
        pick("Abiaraztean ireki",
             "Ouvrir à l'ouverture de session",
             "Open at login")
    }
    static var loginItemNeedsApproval: String {
        pick("Onarpena falta da Sistemaren ezarpenetan",
             "Approbation requise dans les Réglages Système",
             "Approval required in System Settings")
    }
    static var presenceLabel: String {
        pick("Non erakutsi Mintzo",
             "Où afficher Mintzo",
             "Where to show Mintzo")
    }
    static var presenceMenuBar: String {
        pick("Menu-barran", "Dans la barre de menus", "In the menu bar")
    }
    static var presenceDock: String {
        pick("Dock-ean", "Dans le Dock", "In the Dock")
    }
    static var presenceBoth: String {
        pick("Bietan", "Les deux", "Both")
    }
    static var presenceNote: String {
        pick("Dock moduan ere, diktaketa erabilgarri dago beti lasterbidearen bidez.",
             "En mode Dock seul, la dictée reste accessible par le raccourci.",
             "In Dock-only mode, dictation stays available through the shortcut.")
    }
    static var appearanceLabel: String {
        pick("Itxura", "Apparence", "Appearance")
    }
    static var appearanceSystem: String {
        pick("Sistema", "Système", "System")
    }
    static var appearanceLight: String {
        pick("Argia", "Clair", "Light")
    }
    static var appearanceDark: String {
        pick("Iluna", "Sombre", "Dark")
    }

    // MARK: Ereduak

    static var transcriptionSection: String {
        pick("Transkripzioa (Whisper)", "Transcription (Whisper)", "Transcription (Whisper)")
    }
    static var correctionSection: String {
        pick("Zuzenketa (Latxa)", "Correction (Latxa)", "Correction (Latxa)")
    }
    static var installed: String { pick("Instalatuta", "Installé", "Installed") }
    static var notInstalled: String { pick("Deskargatu gabe", "Non téléchargé", "Not downloaded") }
    static var download: String { pick("Deskargatu", "Télécharger", "Download") }
    static var remove: String { pick("Ezabatu", "Supprimer", "Delete") }
    static var modelsFolderNote: String {
        pick("Ereduak zure Mac-ean gordetzen dira eta konexiorik gabe dabiltza.",
             "Les modèles sont stockés sur votre Mac et fonctionnent sans connexion.",
             "Models are stored on your Mac and work without a connection.")
    }

    // MARK: Zuzenketa

    static var correctionModeLabel: String {
        pick("Motorra", "Moteur", "Engine")
    }
    static var correctionOff: String {
        pick("Zuzenketarik ez", "Aucune correction", "No correction")
    }
    static var correctionLatxa: String {
        pick("Latxa (lokala)", "Latxa (local)", "Latxa (local)")
    }
    static var correctionCloud: String {
        pick("Cloud (Anthropic)", "Cloud (Anthropic)", "Cloud (Anthropic)")
    }
    static var correctionExplainer: String {
        pick("Zuzenketak puntuazioa, maiuskulak eta ASR akats nabariak konpontzen ditu — ez du inoiz testua berridazten.",
             "La correction répare ponctuation, majuscules et erreurs ASR évidentes — elle ne reformule jamais le texte.",
             "Correction fixes punctuation, capitalization and obvious ASR errors — it never rewrites the text.")
    }
    static var latxaModelMissingNote: String {
        pick("Latxa eredua falta da: deskargatu « Ereduak » atalean.",
             "Le modèle Latxa n'est pas installé : téléchargez-le dans « Modèles ».",
             "The Latxa model isn't installed: download it in “Models”.")
    }
    static var cloudHonestyNote: String {
        pick("Cloud moduan zure testua Anthropic-en zerbitzarietara bidaltzen da. Audioa ez da inoiz zure Mac-etik ateratzen.",
             "En mode cloud, votre texte est envoyé aux serveurs d'Anthropic. L'audio, lui, ne quitte jamais votre Mac.",
             "In cloud mode, your text is sent to Anthropic's servers. Audio itself never leaves your Mac.")
    }
    static var apiKeyLabel: String {
        pick("Anthropic API gakoa", "Clé API Anthropic", "Anthropic API key")
    }
    static var apiKeyStored: String {
        pick("Gakoa gordeta trousseau-an", "Clé enregistrée dans le trousseau", "Key stored in the keychain")
    }
    static var apiKeyMissing: String {
        pick("Gakorik ez", "Aucune clé", "No key")
    }
    static var save: String { pick("Gorde", "Enregistrer", "Save") }
}
