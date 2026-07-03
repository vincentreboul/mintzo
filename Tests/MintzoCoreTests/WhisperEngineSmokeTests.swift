import XCTest
import AVFoundation
@testable import MintzoCore

/// Smoke test de transcription réelle : fixture WAV française → WhisperEngine (ggml-tiny).
final class WhisperEngineSmokeTests: XCTestCase {

    /// Racine du repo, dérivée du chemin de ce fichier source (Tests/MintzoCoreTests/…).
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MintzoCoreTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // racine du repo

    private static let modelURL = repoRoot
        .appendingPathComponent("Models")
        .appendingPathComponent("ggml-tiny.bin")

    func testTranscribesFrenchFixture() async throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else {
            throw XCTSkip(
                "Modèle absent (\(Self.modelURL.path)) — lancer scripts/download-test-model.sh"
            )
        }

        let bundle = Bundle(for: Self.self)
        let wavURL = try XCTUnwrap(
            bundle.url(forResource: "bonjour-16k", withExtension: "wav"),
            "Fixture bonjour-16k.wav absente du bundle de test"
        )

        let samples = try Self.loadSamples(from: wavURL)
        XCTAssertGreaterThan(samples.count, 16_000, "Fixture trop courte (< 1 s d'audio)")

        let engine = try WhisperEngine(modelPath: Self.modelURL)
        let text = try await engine.transcribe(samples: samples, language: "fr")

        print("SMOKE-TEST TRANSCRIPTION [fr] → « \(text) »")
        XCTAssertFalse(text.isEmpty, "La transcription ne doit pas être vide")
    }

    /// Charge un WAV mono 16 kHz en PCM float32 normalisé.
    private static func loadSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000, accuracy: 0.1, "La fixture doit être en 16 kHz")
        XCTAssertEqual(format.channelCount, 1, "La fixture doit être mono")

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw NSError(domain: "WhisperEngineSmokeTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Impossible d'allouer le buffer PCM",
            ])
        }
        try file.read(into: buffer)

        guard let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "WhisperEngineSmokeTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Pas de données float dans le buffer",
            ])
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
