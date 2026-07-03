import Foundation

/// Un modèle Whisper téléchargeable, avec ses métadonnées d'intégrité.
public struct WhisperModel: Sendable, Identifiable, Equatable, Hashable {
    /// Rôle du modèle dans Mintzo.
    public enum Role: Sendable, Equatable, Hashable {
        /// Transcription basque (euskara).
        case basque
        /// Transcription française (et multilingue).
        case french
        /// Petit modèle réservé aux tests automatisés.
        case testing
    }

    public let id: String
    public let displayName: String
    public let downloadURL: URL
    /// Taille exacte du fichier en octets (vérifiée via l'API Hugging Face).
    public let sizeBytes: Int64
    /// SHA256 attendu (lfs.oid de l'API Hugging Face).
    public let sha256: String
    public let role: Role

    /// Nom du fichier sur disque, dérivé de l'id — stable et sans collision.
    public var fileName: String { "\(id).bin" }

    public init(
        id: String,
        displayName: String,
        downloadURL: URL,
        sizeBytes: Int64,
        sha256: String,
        role: Role
    ) {
        self.id = id
        self.displayName = displayName
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.role = role
    }
}

/// Catalogue statique des modèles connus de Mintzo.
///
/// URLs, tailles et SHA256 vérifiés le 2026-07-03 :
/// - HEAD sur chaque URL `resolve/main` → HTTP 200 (CDN hf.co),
///   Content-Length identique au `size` de l'API,
/// - SHA256 = `lfs.oid` retourné par
///   `https://huggingface.co/api/models/<repo>/tree/main`.
public enum ModelCatalog {

    /// Whisper large-v3 affiné basque (xezpeleta/whisper-large-v3-eu), ~3,1 Go.
    public static let whisperEU = WhisperModel(
        id: "whisper-eu",
        displayName: "Whisper Large v3 — Euskara",
        downloadURL: URL(string: "https://huggingface.co/xezpeleta/whisper-large-v3-eu/resolve/main/ggml-large-v3.eu.bin")!,
        sizeBytes: 3_095_033_483,
        sha256: "dae98a83f5450d1a26632430649633842f0b6e535c246baa5b46b962bedf8cab",
        role: .basque
    )

    /// Whisper large-v3-turbo multilingue (ggerganov/whisper.cpp), ~1,6 Go.
    public static let whisperFR = WhisperModel(
        id: "whisper-fr",
        displayName: "Whisper Large v3 Turbo — Français",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        sizeBytes: 1_624_555_275,
        sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
        role: .french
    )

    /// Whisper tiny multilingue (~75 Mo) — tests automatisés uniquement.
    public static let whisperTiny = WhisperModel(
        id: "whisper-tiny",
        displayName: "Whisper Tiny (tests)",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
        sizeBytes: 77_691_713,
        sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
        role: .testing
    )

    /// Tous les modèles du catalogue.
    public static let all: [WhisperModel] = [whisperEU, whisperFR, whisperTiny]

    /// Recherche par identifiant.
    public static func model(withID id: String) -> WhisperModel? {
        all.first { $0.id == id }
    }
}
