import Foundation

/// Passe de correction post-ASR complète : moteur (local Latxa / cloud BYOK /
/// passthrough) + garde-fous. Ne lève jamais vers l'appelant : en cas d'échec ou de
/// sortie suspecte, renvoie le texte BRUT avec un flag `.fallbackRaw(reason:)` —
/// la dictée de l'utilisateur ne doit jamais être perdue ni dégradée.
public struct CorrectionService: Sendable {
    private let corrector: any Corrector

    public init(corrector: any Corrector) {
        self.corrector = corrector
    }

    public func correct(_ text: String, language: Language) async -> CorrectionResult {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return CorrectionResult(text: input, outcome: .unchanged)
        }

        let raw: String
        do {
            raw = try await corrector.correct(input, language: language)
        } catch {
            return CorrectionResult(text: input, outcome: .fallbackRaw(reason: .engineError))
        }

        let cleaned = CorrectionGuardrails.sanitize(raw)
        if let reason = CorrectionGuardrails.evaluate(input: input, output: cleaned) {
            return CorrectionResult(text: input, outcome: .fallbackRaw(reason: reason))
        }

        return CorrectionResult(
            text: cleaned,
            outcome: cleaned == input ? .unchanged : .corrected
        )
    }
}
