import Foundation

/// Post-pass déterministe du dictionnaire : applique les remplacements
/// « entendu → voulu » APRÈS la passe de correction (dictée ET fichiers).
///
/// Contrat (design validé) :
/// - détection INSENSIBLE à la casse (« Mine Tso », « mine tso » → même règle) ;
/// - la cible est insérée VERBATIM — sa casse telle que saisie est préservée ;
/// - frontières de mots : jamais de remplacement en plein milieu d'un mot
///   (« min » ne touche pas « Mintzo ») — frontière = tout sauf lettre/chiffre,
///   en classes Unicode (accents français, graphies basques couverts) ;
/// - « entendu » multi-mots toléré aux espaces près (« mine tso » matche
///   aussi « mine  tso ») ;
/// - ordre STABLE : les règles s'appliquent dans l'ordre de la liste, la
///   sortie d'une règle est l'entrée de la suivante ;
/// - règle invalide (« entendu » ou cible vides) ignorée — jamais d'effacement.
public enum VocabularyPostPass {

    public static func apply(_ text: String, replacements: [VocabularyReplacement]) -> String {
        guard !text.isEmpty, !replacements.isEmpty else { return text }
        var result = text
        for rule in replacements {
            result = applyOne(rule, to: result)
        }
        return result
    }

    private static func applyOne(_ rule: VocabularyReplacement, to text: String) -> String {
        let heard = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !wanted.isEmpty else { return text } // règle invalide : no-op

        // « entendu » découpé en tokens, chaque token échappé littéralement,
        // recousus par \s+ — tolère les variations d'espaces du moteur ASR.
        let tokens = heard
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map(NSRegularExpression.escapedPattern(for:))
        guard !tokens.isEmpty else { return text }
        // Frontières : pas de lettre (avec diacritiques combinants) ni de
        // chiffre collés — plus fiable que \b hors ASCII.
        let boundary = "\\p{L}\\p{M}\\p{N}"
        let pattern = "(?<![\(boundary)])" + tokens.joined(separator: "\\s+") + "(?![\(boundary)])"

        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return text }

        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: wanted)
        )
    }
}
