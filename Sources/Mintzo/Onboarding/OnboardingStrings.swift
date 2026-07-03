import Foundation

// Microcopy de l'onboarding — étend le pattern MzStrings (euskara si le système
// est en eu, sinon français, sinon anglais — §9.1) sans toucher aux fichiers
// existants. Ton §9 : sobre, zéro point d'exclamation, pas de point final sur
// les labels, honnêteté structurelle (chaque permission dit POURQUOI et ce qui
// ne sort pas du Mac). Typographie §3.4 : ellipse « … », apostrophe « ' »,
// espace fine insécable (U+202F) avant « : » en français.

enum OnboardingStrings {

    private static func pick(_ eu: String, _ fr: String, _ en: String) -> String {
        switch MzStrings.ui {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }

    // MARK: - Navigation

    static var next: String { pick("Jarraitu", "Continuer", "Continue") }
    static var back: String { pick("Atzera", "Retour", "Back") }
    static var finish: String { pick("Amaitu", "Terminer", "Finish") }

    /// VoiceOver des points de progression : « 2 / 3 ».
    static func progressLabel(step: Int, of total: Int) -> String {
        pick("\(step) / \(total). urratsa", "étape \(step) sur \(total)", "step \(step) of \(total)")
    }

    // MARK: - Écran 1 · Ongi etorri

    static var welcomeKicker: String { pick("ongi etorri", "ongi etorri", "ongi etorri") }
    static var wordmark: String { "Mintzo" }
    static var tagline: String {
        pick("Euskarazko diktaketa, osorik zure Mac-ean.",
             "La dictée en basque, entièrement sur votre Mac.",
             "Basque dictation, entirely on your Mac.")
    }

    static var promiseDictation: String {
        pick("Sakatu Fn eta hitz egin — testua kurtsorean agertzen da, edozein aplikaziotan.",
             "Appuyez sur Fn et parlez — le texte apparaît au curseur, dans n'importe quelle application.",
             "Press Fn and speak — text appears at your cursor, in any app.")
    }
    static var promiseFiles: String {
        pick("Arrastatu WhatsApp-eko ahots-mezu bat edo beste edozein audio: testu bihurtuko da.",
             "Déposez un vocal WhatsApp ou n'importe quel fichier audio\u{202F}: il devient du texte.",
             "Drop a WhatsApp voice message or any audio file: it becomes text.")
    }
    /// La promesse privacy canonique (§9.1) — copy récurrent, verbatim.
    static var promiseLocal: String {
        pick("Audioa ez da inoiz zure Mac-etik ateratzen.",
             "L'audio ne sort jamais de votre Mac.",
             "Audio never leaves your Mac.")
    }

    // MARK: - Écran 2 · Baimenak

    static var permissionsTitle: String { pick("Baimenak", "Autorisations", "Permissions") }
    static var permissionsIntro: String {
        pick("Mintzok bi baimen erabiltzen ditu. Hona zergatik.",
             "Mintzo utilise deux autorisations. Voici pourquoi.",
             "Mintzo uses two permissions. Here is why.")
    }

    // Micro — corps §9.2 verbatim.
    static var microphoneTitle: String { pick("Mikrofonoa", "Micro", "Microphone") }
    static var microphoneRequiredBadge: String { pick("beharrezkoa", "requise", "required") }
    static var microphoneBody: String {
        pick("Mintzok mikrofonoa erabiltzen du zure ahotsa entzuteko. Audioa zure Mac-ean prozesatzen da, eta ez da inoiz hemendik aterako.",
             "Mintzo utilise le micro pour entendre votre voix. L'audio est traité sur votre Mac et n'en sort jamais.",
             "Mintzo uses the microphone to hear your voice. Audio is processed on your Mac and never leaves it.")
    }
    static var microphoneAllow: String {
        pick("Baimendu mikrofonoa", "Autoriser le micro", "Allow microphone")
    }

    static var accessibilityTitle: String {
        pick("Erabilerraztasuna", "Accessibilité", "Accessibility")
    }
    static var accessibilityOptionalBadge: String { pick("aukerakoa", "optionnelle", "optional") }
    static var accessibilityBody: String {
        pick("Diktatutako testua kurtsorean itsasteko eta Fn tekla antzemateko. Mintzok ez du beste ezer irakurtzen; ezer ez da zure Mac-etik ateratzen.",
             "Sert à coller le texte dicté au curseur et à détecter la touche Fn. Mintzo ne lit rien d'autre, et rien ne sort de votre Mac.",
             "Used to paste dictated text at the cursor and to detect the Fn key. Mintzo reads nothing else, and nothing leaves your Mac.")
    }
    /// L'alternative honnête, sans dramatiser : on peut vivre sans.
    static var accessibilityWithout: String {
        pick("Hori gabe: testua arbelean geratzen da — itsatsi ⌘V sakatuta.",
             "Sans elle\u{202F}: presse-papiers seulement — collez avec ⌘V.",
             "Without it: clipboard only — paste with ⌘V.")
    }
    static var accessibilityAllow: String {
        pick("Baimendu ezarpenetan", "Autoriser dans les réglages", "Allow in settings")
    }

    static var granted: String { pick("Emanda", "Accordée", "Granted") }
    static var openSystemSettings: String {
        pick("Ireki ezarpenak", "Ouvrir les réglages", "Open settings")
    }

    // MARK: - Écran 3 · Eredua

    static var modelTitle: String { pick("Eredua", "Le modèle", "The model") }
    /// Écho du copy canonique §9.2 : « Deskargatu behin, erabili betiko — konexiorik gabe. »
    static var modelIntro: String {
        pick("Transkripzioa zure Mac-ean gertatzen da. Deskargatu eredua behin, erabili betiko — konexiorik gabe.",
             "La transcription se fait sur votre Mac. Téléchargez le modèle une fois, utilisez-le pour toujours — sans connexion.",
             "Transcription happens on your Mac. Download the model once, use it forever — no connection needed.")
    }

    static var languageBasque: String { pick("euskara", "basque", "Basque") }
    static var languageFrench: String { pick("frantsesa", "français", "French") }

    static var download: String { pick("Deskargatu", "Télécharger", "Download") }
    static var downloading: String { pick("Deskargatzen…", "Téléchargement…", "Downloading…") }
    static var installed: String { pick("Instalatuta", "Installé", "Installed") }
    static var retry: String { pick("Saiatu berriro", "Réessayer", "Try again") }

    static var latxaNote: String {
        pick("Latxa zuzenketa (aukerakoa) geroago aktiba daiteke, ezarpenetan.",
             "La correction Latxa (optionnelle) s'active plus tard, dans les réglages.",
             "Latxa correction (optional) can be enabled later, in settings.")
    }

    static var trialTitle: String { pick("proba ezazu", "essayez", "try it") }
    static var trialHint: String {
        pick("Sakatu Diktatu, esan zerbait, eta sakatu berriro gelditzeko.",
             "Cliquez sur Dicter, parlez, puis cliquez à nouveau pour arrêter.",
             "Click Dictate, say something, then click again to stop.")
    }
    static var trialPlaceholder: String {
        pick("Zure hitzak hemen agertuko dira…",
             "Vos mots apparaîtront ici…",
             "Your words will appear here…")
    }
    static var trialNeedsMicrophone: String {
        pick("Mikrofonoaren baimena behar da probarako.",
             "L'autorisation du micro est nécessaire pour l'essai.",
             "Microphone permission is needed for the trial.")
    }

    // Labels du bouton d'essai — chaînes canoniques réutilisées (MzStrings).
    static var trialDictate: String { MzStrings.dictate }
    static var trialStop: String { MzStrings.stop }
    static var trialProcessing: String { MzStrings.transcribing }
}
