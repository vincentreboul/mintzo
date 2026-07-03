import Foundation

/// Correction locale via un LLM Latxa (llama.cpp). Le même modèle gère l'euskara et
/// le français — seul le prompt système change (voir `CorrectionPrompt`).
public struct LatxaCorrector: Corrector {
    private let engine: LlamaEngine
    private let protectedWords: [String]

    /// - Parameters:
    ///   - engine: moteur chargé avec un GGUF INSTRUCT du catalogue
    ///     (`LatxaCatalog.default`), typiquement Latxa-Qwen3-VL-4B-Instruct Q4_K_M.
    ///   - protectedWords: graphies du dictionnaire personnalisé, injectées
    ///     dans le prompt système (section « respecte ces graphies »).
    public init(engine: LlamaEngine, protectedWords: [String] = []) {
        self.engine = engine
        self.protectedWords = protectedWords
    }

    public func correct(_ text: String, language: Language) async throws -> String {
        try await engine.generate(
            system: CorrectionPrompt.system(for: language, protectedWords: protectedWords),
            user: text,
            maxTokens: CorrectionPrompt.maxTokens(forInput: text)
        )
    }
}
