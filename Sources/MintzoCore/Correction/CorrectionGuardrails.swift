import Foundation

/// Garde-fous post-génération : la sortie d'un LLM correcteur ne se fait JAMAIS
/// confiance telle quelle (sur-correction, hallucination, réponse au contenu,
/// méta-texte parasite — pathologies documentées de la correction post-ASR).
///
/// Pipeline : `sanitize` (nettoyage méta-texte) → `evaluate` (bornes quantitatives).
public enum CorrectionGuardrails {
    /// Bornes du ratio de longueur (caractères) sortie/entrée.
    public static let lengthRatioBounds: ClosedRange<Double> = 0.7...1.5
    /// Seuil minimal de similarité lexicale (Levenshtein mots normalisé, 1 = identique).
    public static let minimumWordSimilarity: Double = 0.6

    /// Préfixes de méta-texte connus (le modèle « présente » sa réponse au lieu de
    /// renvoyer le texte seul) — comparés en minuscules.
    private static let metaPrefixes: [String] = [
        "voici le texte corrigé :", "voici le texte corrigé:",
        "voici la correction :", "voici la correction:",
        "texte corrigé :", "texte corrigé:",
        "hona hemen testu zuzendua:", "hona hemen zuzenketa:",
        "testu zuzendua:", "zuzenketa:", "zuzendutako testua:",
        "here is the corrected text:", "corrected text:",
    ]

    /// Nettoie la sortie brute du LLM : trim, retrait d'un préfixe méta connu,
    /// retrait de guillemets enveloppants ajoutés par le modèle.
    public static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let lowered = text.lowercased()
        for prefix in metaPrefixes where lowered.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // Guillemets enveloppants (le modèle cite le texte au lieu de le renvoyer nu).
        let quotePairs: [(Character, Character)] = [("«", "»"), ("\u{201C}", "\u{201D}"), ("\"", "\"")]
        for (open, close) in quotePairs {
            if text.count >= 2, text.first == open, text.last == close {
                text = String(text.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    /// Évalue une sortie nettoyée contre l'entrée. Renvoie `nil` si la sortie est
    /// acceptable, sinon la raison du rejet.
    public static func evaluate(input: String, output: String) -> FallbackReason? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return .emptyOutput }
        guard !input.isEmpty else { return nil }

        let ratio = Double(output.count) / Double(input.count)
        guard lengthRatioBounds.contains(ratio) else { return .lengthRatio }

        guard wordSimilarity(input, output) >= minimumWordSimilarity else {
            return .lowSimilarity
        }
        return nil
    }

    /// Similarité lexicale ∈ [0 ; 1] : 1 − (distance de Levenshtein sur les mots
    /// normalisés / nombre max de mots). Les mots sont comparés en minuscules et sans
    /// ponctuation : une correction légitime (ponctuation, majuscules) ne compte pas
    /// comme une édition — seuls les remplacements/ajouts/suppressions de mots comptent.
    public static func wordSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = normalizedWords(a)
        let wordsB = normalizedWords(b)
        let maxCount = max(wordsA.count, wordsB.count)
        guard maxCount > 0 else { return 1 }
        let distance = levenshtein(wordsA, wordsB)
        return 1 - Double(distance) / Double(maxCount)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { word in
                String(word.unicodeScalars.filter {
                    !CharacterSet.punctuationCharacters.contains($0)
                        && !CharacterSet.symbols.contains($0)
                })
            }
            .filter { !$0.isEmpty }
    }

    /// Levenshtein classique (DP deux lignes) sur des séquences de mots.
    private static func levenshtein(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,           // suppression
                    current[j - 1] + 1,        // insertion
                    previous[j - 1] + substitutionCost // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
