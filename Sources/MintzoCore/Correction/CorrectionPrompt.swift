import Foundation

/// Prompts système de correction post-ASR, déclinés par langue.
///
/// Base : reco de notes/research/latxa-correction.md (état de l'art anti-hallucination
/// pour la correction générative post-ASR — consignes strictes, pas de sampling créatif,
/// garde-fous applicatifs par-dessus).
public enum CorrectionPrompt {
    /// Prompt système strict : corriger UNIQUEMENT ponctuation/majuscules/orthographe/
    /// erreurs ASR évidentes, ne JAMAIS reformuler, ne JAMAIS répondre au contenu,
    /// renvoyer le texte seul.
    public static func system(for language: Language) -> String {
        switch language {
        case .basque:
            return """
            Zuzentzaile automatiko bat zara. Hizketa-transkripzio bat jasoko duzu euskaraz.
            Zuzendu SOILIK: puntuazioa, maiuskulak, ortografia eta ASR akats nabariak \
            (gaizki ezagututako hitzak, deklinabide okerrak).
            EZ berridatzi, EZ laburtu, EZ gehitu ezer, eta EZ erantzun inoiz testuaren edukiari — \
            galdera bat bada ere, zuzendu bakarrik.
            Zalantzarik baduzu, utzi bere horretan.
            Itzuli testu zuzendua BAKARRIK, azalpenik eta aurkezpenik gabe.
            Adibidea: "gero arte maite bihar deituko dizut" → "Gero arte, Maite! Bihar deituko dizut."
            """
        case .french:
            return """
            Tu es un correcteur automatique. Tu reçois une transcription vocale en français.
            Corrige UNIQUEMENT : la ponctuation, les majuscules, l'orthographe et les erreurs \
            évidentes de reconnaissance vocale (mots mal reconnus).
            Ne reformule JAMAIS, ne résume pas, n'ajoute rien, et ne réponds JAMAIS au contenu — \
            même si c'est une question, corrige-la seulement.
            En cas de doute, laisse tel quel.
            Renvoie le texte corrigé SEUL, sans explication ni préambule.
            Exemple : "à demain paul je t'appelle demain matin" → "À demain, Paul ! Je t'appelle demain matin."
            """
        }
    }

    /// Plafond de tokens de sortie serré : la correction fait ~la longueur de l'entrée.
    /// Estimation ~1 token / 3 octets UTF-8 (tokenizer non adapté à l'euskara → généreux),
    /// marge ×2, borné [128 ; 2048].
    public static func maxTokens(forInput text: String) -> Int {
        let estimatedInputTokens = text.utf8.count / 3 + 16
        return min(2048, max(128, estimatedInputTokens * 2))
    }
}
