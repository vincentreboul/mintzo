import XCTest
import AVFoundation
@testable import MintzoCore

/// Test E2E opt-in sur modèles réels — QA de release, pas CI.
/// Lancer avec MINTZO_E2E=1 et les modèles installés dans ~/Library/Application Support/Mintzo/Models.
/// MINTZO_E2E_AUDIO peut pointer un fichier audio basque ; sinon la fixture opus FR est utilisée avec whisper-eu ignoré.
final class RealEndToEndTests: XCTestCase {

    private var modelsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mintzo/Models")
    }

    func testRealBasquePipelineWhisperEuPlusLatxa() async throws {
        guard ProcessInfo.processInfo.environment["MINTZO_E2E"] == "1" else {
            throw XCTSkip("MINTZO_E2E != 1")
        }
        let whisperEu = modelsDir.appendingPathComponent("whisper-eu.bin")
        let latxa = modelsDir.appendingPathComponent("Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf")
        guard FileManager.default.fileExists(atPath: whisperEu.path) else { throw XCTSkip("whisper-eu.bin absent") }

        guard let audioPath = ProcessInfo.processInfo.environment["MINTZO_E2E_AUDIO"] else {
            throw XCTSkip("MINTZO_E2E_AUDIO non fourni")
        }
        let samples = try AudioFileDecoder.decode(url: URL(fileURLWithPath: audioPath))
        XCTAssertGreaterThan(samples.count, 16_000, "audio trop court")

        // 1. Transcription whisper-eu réelle
        let t0 = Date()
        let engine = try WhisperEngine(modelPath: whisperEu)
        let loadTime = Date().timeIntervalSince(t0)
        let t1 = Date()
        let raw = try await engine.transcribe(samples: samples, language: "eu")
        let asrTime = Date().timeIntervalSince(t1)
        print("E2E-ASR [\(String(format: "%.1f", asrTime))s, load \(String(format: "%.1f", loadTime))s] → « \(raw.trimmingCharacters(in: .whitespacesAndNewlines)) »")
        XCTAssertFalse(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // 2. Correction Latxa réelle (si installée)
        if FileManager.default.fileExists(atPath: latxa.path) {
            let t2 = Date()
            let llama = try LlamaEngine(modelPath: latxa)
            let corrector = LatxaCorrector(engine: llama)
            let corrected = try await corrector.correct(raw, language: .basque)
            let corrTime = Date().timeIntervalSince(t2)
            print("E2E-CORRECTION [\(String(format: "%.1f", corrTime))s] → « \(corrected) »")
            XCTAssertFalse(corrected.isEmpty)
        }
    }
}
