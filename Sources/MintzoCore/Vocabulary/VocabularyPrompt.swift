import Foundation

/// Construction du prompt d'amorçage whisper à partir des mots du dictionnaire.
///
/// `whisper_full_params.initial_prompt` conditionne le décodeur : les graphies
/// présentes dans le prompt deviennent des tokens « déjà vus », que le modèle
/// privilégie face à des homophones (« Bitwip » plutôt que « bit whip »).
public enum VocabularyPrompt {

    /// Le prompt whisper est tronqué en interne à ~224 tokens (n_ctx/2).
    /// 800 caractères ≈ 200 tokens sur des noms propres — marge prudente,
    /// jamais de prompt coupé en plein token côté C.
    public static let maxLength = 800

    /// Joint les mots en une amorce type « Bitwip, Maite, Donostia. »
    ///
    /// - Mots trimés, entrées vides ignorées, ordre de la liste préservé.
    /// - Troncature à `limit` caractères par MOTS ENTIERS : un mot qui ne
    ///   tient plus est abandonné (jamais coupé au milieu), les suivants aussi.
    /// - Returns: l'amorce, ou `nil` si aucun mot n'est utilisable — l'appelant
    ///   passe alors `nil` à whisper (pas de prompt vide).
    public static func whisperPrompt(words: [String], limit: Int = maxLength) -> String? {
        var included: [String] = []
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Longueur de la chaîne FINALE si on ajoute ce mot — correct par
            // construction, listes minuscules (le O(n²) est sans objet).
            let candidate = (included + [trimmed]).joined(separator: ", ") + "."
            guard candidate.count <= limit else {
                break // premier mot qui déborde : on arrête (ordre stable, pas de trous)
            }
            included.append(trimmed)
        }
        guard !included.isEmpty else { return nil }
        return included.joined(separator: ", ") + "."
    }
}
