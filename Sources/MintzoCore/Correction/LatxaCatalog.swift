import Foundation

/// Catalogue des modèles de correction téléchargeables (GGUF, gitignorés, installés
/// dans Models/ au runtime).
public enum LatxaCatalog {
    /// Un GGUF téléchargeable, identifié et vérifiable.
    public struct ModelEntry: Sendable, Equatable {
        public let id: String
        public let displayName: String
        /// URL de téléchargement direct (endpoint `resolve` de Hugging Face).
        public let url: URL
        /// Taille exacte en octets (API HF `tree`, champ `size`).
        public let sizeBytes: Int64
        /// SHA256 du fichier = `lfs.oid` de l'API Hugging Face — autoritatif.
        public let sha256: String
        /// Nom de fichier local attendu dans Models/.
        public var fileName: String { url.lastPathComponent }
    }

    /// Modèle de correction par défaut : **Latxa-Qwen3-VL-4B-Instruct, quant Q4_K_M**
    /// (~2,5 Go ≤ budget 5 Go), quantisé par mradermacher depuis
    /// `HiTZ/Latxa-Qwen3-VL-4B-Instruct` (Apache 2.0).
    ///
    /// Choix documenté (vérifié via l'API HF `/tree/main` le 2026-07-03, sha256 =
    /// `lfs.oid`) :
    /// - Famille reco par notes/research/latxa-correction.md : Latxa-Qwen3 4B = seul
    ///   gabarit basque tenant le budget latence M4 (~35-42 tok/s en Q4).
    /// - `itzune/Latxa-Qwen3-VL-4B-GGUF` ne publie QUE q8_0 (4,28 Go) et f16 (8 Go) —
    ///   pas de Q4_K_M ; `mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF` publie la gamme
    ///   complète → Q4_K_M retenu (meilleur ratio qualité/taille/latence).
    /// - Aucun GGUF de Latxa-Qwen3.5 n'existe à ce jour (vérifié) — à réévaluer quand
    ///   la famille 3.5 sera quantisée.
    /// - Usage TEXTE seul : le mmproj (projecteur vision, fichier séparé) n'est pas
    ///   téléchargé — llama.cpp charge la partie texte d'un Qwen3-VL comme un LLM normal.
    /// - Révision : mradermacher quantise la branche `main` de HiTZ (« static quants of
    ///   HiTZ/Latxa-Qwen3-VL-4B-Instruct », README vérifié) — pas la révision `mono_eu`
    ///   spécifiquement ; aucun GGUF `mono_eu` n'est publié à ce jour.
    /// - Caveat : carte modèle HiTZ marquée « still under development / preliminary » ;
    ///   la qualité de correction réelle est à valider à l'usage (garde-fous en place).
    public static let latxaQwen3VL4BInstructQ4KM = ModelEntry(
        id: "latxa-qwen3-vl-4b-instruct-q4_k_m",
        displayName: "Latxa Qwen3-VL 4B Instruct (Q4_K_M)",
        url: URL(
            string: "https://huggingface.co/mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF/resolve/main/Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf"
        )!,
        sizeBytes: 2_497_282_176,
        sha256: "3eae629d2714189689aa8de1b1d7cfdf8ec846c405b26e4faeeb1fdfa3b4f26b"
    )

    /// Le modèle par défaut de la passe de correction.
    public static let `default` = latxaQwen3VL4BInstructQ4KM
}
