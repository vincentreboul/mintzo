import Foundation

/// Langue de la dictée, pilote le prompt de correction.
public enum Language: String, Sendable, CaseIterable, Equatable {
    case basque = "eu"
    case french = "fr"
}

/// Une passe de correction post-ASR : ponctuation, majuscules, orthographe,
/// erreurs ASR évidentes — jamais de reformulation.
///
/// Les implémentations renvoient la sortie BRUTE du moteur (ou le texte inchangé
/// pour `PassthroughCorrector`). Les garde-fous s'appliquent au-dessus, dans
/// `CorrectionService` — la sortie d'un LLM ne se fait jamais confiance telle quelle.
public protocol Corrector: Sendable {
    func correct(_ text: String, language: Language) async throws -> String
}

/// Raison d'un repli sur le texte brut (sortie LLM rejetée par les garde-fous).
public enum FallbackReason: String, Sendable, Equatable {
    /// Ratio longueur sortie/entrée hors bornes — le modèle a tronqué ou brodé.
    case lengthRatio
    /// Similarité lexicale trop faible — le modèle a reformulé ou répondu au contenu.
    case lowSimilarity
    /// Sortie vide (ou vide après nettoyage du méta-texte).
    case emptyOutput
    /// Le moteur a levé une erreur (modèle déchargé, réseau, API…).
    case engineError
}

/// Résultat d'une correction, garde-fous appliqués.
public struct CorrectionResult: Sendable, Equatable {
    /// Le texte à utiliser — corrigé si accepté, BRUT si repli.
    public let text: String
    public let outcome: Outcome

    public enum Outcome: Sendable, Equatable {
        /// Sortie LLM acceptée et différente de l'entrée.
        case corrected
        /// Sortie LLM identique à l'entrée (rien à corriger) — ou correction désactivée.
        case unchanged
        /// Sortie LLM rejetée : `text` contient l'entrée brute inchangée.
        case fallbackRaw(reason: FallbackReason)
    }

    public init(text: String, outcome: Outcome) {
        self.text = text
        self.outcome = outcome
    }
}

/// Correction désactivée : renvoie le texte tel quel.
public struct PassthroughCorrector: Corrector {
    public init() {}

    public func correct(_ text: String, language: Language) async throws -> String {
        text
    }
}
