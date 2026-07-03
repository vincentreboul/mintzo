import Foundation

/// Microcopy eu / fr / en — source : design-language.md §9.
/// Règle : euskara si le système est en `eu`, sinon français, sinon anglais.
/// Ton : sobre, zéro point d'exclamation, pas de point final sur les labels.
@MainActor
enum MzL10n {
    enum Language {
        case eu, fr, en
    }

    /// Forçage pour tests et rendus QA (nil = suit la langue système).
    static var forced: Language?

    static var current: Language {
        if let forced { return forced }
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if code.hasPrefix("eu") { return .eu }
        if code.hasPrefix("fr") { return .fr }
        return .en
    }

    /// Locale associée (formats de dates des en-têtes de section).
    static var locale: Locale {
        switch current {
        case .eu: Locale(identifier: "eu")
        case .fr: Locale(identifier: "fr_FR")
        case .en: Locale(identifier: "en_US")
        }
    }

    static func t(_ eu: String, _ fr: String, _ en: String) -> String {
        switch current {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }

    // MARK: - Fenêtre principale

    static var delete: String { t("Ezabatu", "Supprimer", "Delete") }
    static var deleteAll: String { t("Ezabatu dena", "Tout effacer", "Delete all") }
    static var moreActions: String { t("Gehiago", "Plus d\u{2019}actions", "More") }
    static var deleteAllConfirmTitle: String {
        t("Historia osoa ezabatu?", "Effacer tout l\u{2019}historique ?", "Delete all history?")
    }
    static var deleteAllConfirmMessage: String {
        t("Transkripzio guztiak betiko ezabatuko dira.",
          "Toutes les transcriptions seront définitivement supprimées.",
          "All transcriptions will be permanently deleted.")
    }
    static var dictateNow: String { t("Diktatu", "Dicter", "Dictate") }
    static var dictateNowHelp: String {
        t("Hasi diktaketa mikrofonoarekin — laster-teklarik gabe",
          "Démarrer la dictée au micro — sans raccourci ni Accessibilité",
          "Start dictating with the microphone — no shortcut needed")
    }
    static var filterDena: String { t("Dena", "Tout", "All") }
    static var filterDiktaketak: String { t("Diktaketak", "Dictées", "Dictations") }
    static var filterFitxategiak: String { t("Fitxategiak", "Fichiers", "Files") }
    static var searchPrompt: String { t("Bilatu…", "Rechercher…", "Search…") }
    /// Titre système de l'état vide (`ContentUnavailableView`) — la phrase
    /// éditoriale canonique reste `emptyTitle`, en serif dans la description.
    static var emptyHeadline: String {
        t("Oraindik ez dago transkripziorik",
          "Aucune transcription pour l\u{2019}instant",
          "No transcriptions yet")
    }
    static var emptyTitle: String {
        t("Sakatu Fn eta hitz egin.", "Appuyez sur Fn et parlez.", "Press Fn and speak.")
    }
    static var emptySubtitle: String {
        t("edo arrastatu audio-fitxategi bat hona",
          "ou déposez un fichier audio ici",
          "or drop an audio file here")
    }
    static var searchNoResults: String { t("Ez da emaitzarik", "Aucun résultat", "No results") }
    static var dropHint: String {
        t("Askatu hemen transkribatzeko", "Déposez ici pour transcrire", "Drop here to transcribe")
    }
    static var copy: String { t("Kopiatu", "Copier", "Copy") }
    static var copied: String { t("Kopiatuta", "Copié", "Copied") }

    // MARK: - Sources et langues

    static var sourceDictee: String { t("diktaketa", "dictée", "dictation") }
    static var sourceFichier: String { t("fitxategia", "fichier", "file") }

    // MARK: - Détail

    static var detailOriginal: String { t("jatorrizkoa", "original", "original") }
    static var detailCorrige: String { t("zuzendua", "corrigé", "corrected") }

    // MARK: - Lecteur audio (détail)

    static var playerPlay: String { t("Entzun", "Écouter", "Play") }
    static var playerPause: String { t("Pausatu", "Mettre en pause", "Pause") }

    // MARK: - Relance (détail)

    static var replayMenu: String { t("Berriz sortu", "Relancer", "Regenerate") }
    static var replayAuto: String { t("Berriz sortu (auto)", "Relancer (auto)", "Regenerate (auto)") }
    static var replayEU: String { t("Berriz euskaraz", "Relancer en euskara", "Regenerate in Basque") }
    static var replayFR: String {
        t("Berriz frantsesez", "Relancer en français", "Regenerate in French")
    }
    /// Échecs de relance — formes courtes et sobres (systemRed 11 pt, pas de
    /// modale) ; le détail technique part au log.
    static var replayModelMissing: String {
        t("Eredua falta da — deskargatu Ereduak atalean",
          "Le modèle est absent — téléchargez-le dans Réglages",
          "Model missing — download it in Settings")
    }
    static var replayAudioUnreadable: String {
        t("Audioa ezin da irakurri", "L\u{2019}audio est illisible", "The audio can\u{2019}t be read")
    }
    static var replayFailed: String {
        t("Berriz sortzeak huts egin du", "La relance a échoué", "Regeneration failed")
    }

    // MARK: - File d'attente

    static var queueWaiting: String { t("zain", "en attente", "queued") }

    /// Échec d'un fichier — formes courtes (colonne statut, systemRed §2.3).
    /// Le détail technique part dans le log, jamais dans la file.
    static var queueFailed: String {
        t("transkripzioak huts egin du", "échec de la transcription", "transcription failed")
    }
    static var queueNoText: String {
        t("ez da testurik ezagutu", "aucun texte reconnu", "no text recognized")
    }
    static var queueHistoryWriteFailed: String {
        t("ezin izan da historian gorde", "enregistrement de l'historique impossible", "couldn't save to history")
    }

    static func queueHeader(count: Int) -> String {
        switch current {
        case .eu: count == 1 ? "ilara — fitxategi 1" : "ilara — \(count) fitxategi"
        case .fr: count == 1 ? "file d\u{2019}attente — 1 fichier" : "file d\u{2019}attente — \(count) fichiers"
        case .en: count == 1 ? "queue — 1 file" : "queue — \(count) files"
        }
    }

    // MARK: - Sections par jour

    /// Titre de section : « gaur » / « atzo » / date en toutes lettres.
    /// En bas de casse — la fonte small caps fait le travail (§3.4).
    static func sectionTitle(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) {
            return t("gaur", "aujourd\u{2019}hui", "today")
        }
        if calendar.isDateInYesterday(day) {
            return t("atzo", "hier", "yesterday")
        }
        return day.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar)
        ).lowercased(with: locale)
    }
}

// MARK: - Formats numériques (§3.4 : durées m:ss, jamais de « s » ni « min »)

enum MzFormat {
    /// `0:42`, `12:07` — durée en m:ss.
    static func duree(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// `14:32` — heure du jour, 24 h.
    static func heure(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
