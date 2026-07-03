import Foundation

/// Correction locale via un LLM Latxa (llama.cpp). Le même modèle gère l'euskara et
/// le français — seul le prompt système change (voir `CorrectionPrompt`).
public struct LatxaCorrector: Corrector {
    private let engine: LlamaEngine

    /// - Parameter engine: moteur chargé avec un GGUF INSTRUCT du catalogue
    ///   (`LatxaCatalog.default`), typiquement Latxa-Qwen3-VL-4B-Instruct Q4_K_M.
    public init(engine: LlamaEngine) {
        self.engine = engine
    }

    public func correct(_ text: String, language: Language) async throws -> String {
        try await engine.generate(
            system: CorrectionPrompt.system(for: language),
            user: text,
            maxTokens: CorrectionPrompt.maxTokens(forInput: text)
        )
    }
}
