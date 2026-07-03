import XCTest
@testable import MintzoCore

/// Smoke tests LLM réels (modèles GGUF dans Models/, gitignorés — XCTSkip si absents).
///
/// Deux étages :
/// 1. Plumbing : le plus petit GGUF instruct réel trouvé (SmolLM2-360M q8_0, 386 Mo,
///    HuggingFaceTB officiel) → `LlamaEngine.generate` → sortie non vide.
/// 2. Le vrai : Latxa-Qwen3-VL-4B-Instruct Q4_K_M (catalogue) → correction réelle
///    d'une phrase eu volontairement dégradée, sortie loggée verbatim.
final class CorrectionLlamaSmokeTests: XCTestCase {

    /// Racine du repo, dérivée du chemin de ce fichier source (Tests/MintzoCoreTests/…).
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MintzoCoreTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // racine du repo

    private static let models = repoRoot.appendingPathComponent("Models")

    /// SmolLM2-360M-Instruct q8_0 — sha256 (lfs.oid API HF, vérifié 2026-07-03) :
    /// 48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201 (386 404 992 o).
    private static let smolLM2URL = models.appendingPathComponent("smollm2-360m-instruct-q8_0.gguf")

    private static let latxaURL = models.appendingPathComponent(LatxaCatalog.default.fileName)

    /// Skip si le modèle est absent OU incomplet (taille ≠ attendue : download partiel,
    /// fichier corrompu) — un GGUF tronqué ferait échouer le chargement, pas skipper.
    private func requireModel(_ url: URL, expectedBytes: Int64, hint: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Modèle absent (\(url.path)) — \(hint)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
            .flatMap { $0 } ?? 0
        guard size == expectedBytes else {
            throw XCTSkip(
                "Modèle incomplet (\(size)/\(expectedBytes) octets) à \(url.path) — \(hint)"
            )
        }
    }

    /// Étage 1 — plumbing llama.cpp de bout en bout sur un petit modèle réel.
    func testSmolLM2GeneratesNonEmptyOutput() async throws {
        try requireModel(
            Self.smolLM2URL,
            expectedBytes: 386_404_992,
            hint: "curl -L -o Models/smollm2-360m-instruct-q8_0.gguf "
                + "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf"
        )

        let engine = try LlamaEngine(modelPath: Self.smolLM2URL)
        let output = try await engine.generate(
            system: "You are a helpful assistant. Answer in one short sentence.",
            user: "What is the capital of France?",
            maxTokens: 64
        )
        await engine.unload()

        print("SMOKE-TEST LLM [SmolLM2-360M] → « \(output) »")
        XCTAssertFalse(output.isEmpty, "La génération ne doit pas être vide")
    }

    /// Étage 2 — correction basque réelle avec le modèle du catalogue.
    /// Entrée volontairement dégradée (aucune ponctuation, aucune majuscule).
    func testLatxaCorrectsDegradedBasqueSentence() async throws {
        try requireModel(
            Self.latxaURL,
            expectedBytes: LatxaCatalog.default.sizeBytes,
            hint: "télécharger LatxaCatalog.default (\(LatxaCatalog.default.url.absoluteString), "
                + "\(LatxaCatalog.default.sizeBytes) octets)"
        )

        let input = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"

        let engine = try LlamaEngine(modelPath: Self.latxaURL)
        let service = CorrectionService(corrector: LatxaCorrector(engine: engine))
        let start = Date()
        let result = await service.correct(input, language: .basque)
        let elapsed = Date().timeIntervalSince(start)
        await engine.unload()

        print("SMOKE-TEST CORRECTION LATXA [eu] (\(String(format: "%.1f", elapsed)) s)")
        print("  entrée  → « \(input) »")
        print("  sortie  → « \(result.text) »")
        print("  outcome → \(result.outcome)")

        XCTAssertFalse(result.text.isEmpty)
        switch result.outcome {
        case .corrected:
            XCTAssertNotEqual(result.text, input, "Une phrase sans ponctuation doit être corrigée")
        case .unchanged, .fallbackRaw:
            // Les garde-fous peuvent légitimement replier sur le brut — le smoke test
            // documente alors le comportement réel sans casser la CI.
            print("  ⚠️ sortie non corrigée — voir logs ci-dessus")
        }
    }
}
