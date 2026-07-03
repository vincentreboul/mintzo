import Foundation
import GRDB

/// Une transcription enregistrée dans l'historique Mintzo.
///
/// Le texte affiché à l'utilisateur est `texteCorrige` s'il existe (sortie du
/// correcteur), sinon `texteBrut` (sortie directe de Whisper).
public struct Transcription: Identifiable, Hashable, Sendable, Codable {

    /// Langue de la transcription (eu / fr, ou auto si non déterminée).
    public enum Langue: String, Codable, Sendable, CaseIterable {
        case eu
        case fr
        /// Auto-détection demandée et langue pas (encore) résolue.
        case auto
    }

    /// Origine de la transcription : dictée live ou fichier importé.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case dictee
        case fichier
    }

    /// Identifiant auto-incrémenté par SQLite (nil tant que non inséré).
    public var id: Int64?
    /// Sortie brute du moteur de transcription.
    public var texteBrut: String
    /// Texte après correction (nil si pas de passe de correction).
    public var texteCorrige: String?
    /// Date de la transcription.
    public var date: Date
    /// Durée de l'audio transcrit, en secondes.
    public var dureeAudio: TimeInterval
    public var langue: Langue
    public var source: Source
    /// Nom du fichier d'origine (source == .fichier uniquement).
    public var nomFichier: String?
    /// Chemin du WAV conservé (16 kHz mono) pour la réécoute et la relance —
    /// nil : entrée antérieure à la v2, ou écriture audio échouée (non bloquant).
    public var audioPath: String?

    /// Texte présenté à l'utilisateur : corrigé si disponible, sinon brut.
    public var texteAffiche: String { texteCorrige ?? texteBrut }

    public init(
        id: Int64? = nil,
        texteBrut: String,
        texteCorrige: String? = nil,
        date: Date = Date(),
        dureeAudio: TimeInterval,
        langue: Langue,
        source: Source,
        nomFichier: String? = nil,
        audioPath: String? = nil
    ) {
        self.id = id
        self.texteBrut = texteBrut
        self.texteCorrige = texteCorrige
        self.date = date
        self.dureeAudio = dureeAudio
        self.langue = langue
        self.source = source
        self.nomFichier = nomFichier
        self.audioPath = audioPath
    }
}

// MARK: - GRDB

extension Transcription: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transcription"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let date = Column(CodingKeys.date)
        public static let texteBrut = Column(CodingKeys.texteBrut)
        public static let texteCorrige = Column(CodingKeys.texteCorrige)
        public static let source = Column(CodingKeys.source)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
