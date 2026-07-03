import XCTest
@testable import MintzoCore

/// Détection de langue RÉELLE (whisper-tiny) — opt-in : MINTZO_E2E=1.
///
/// - fr : fixture committée `bonjour-16k.wav`.
/// - eu : échantillon local pointé par `MINTZO_E2E_AUDIO_EU` (chemin d'un
///   wav/opus de parole basque) — pas de fixture committée tant que la
///   provenance/licence d'un échantillon eu n'est pas actée.
///
/// Lancer : MINTZO_E2E=1 [MINTZO_E2E_AUDIO_EU=/chemin/eu.wav] xcodebuild test…
/// (modèle : scripts/download-test-model.sh → Models/ggml-tiny.bin)
final class LanguageDetectionE2ETests: XCTestCase {

    /// Racine du repo, dérivée du chemin de ce fichier source.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MintzoCoreTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // racine du repo

    private static let modelURL = repoRoot
        .appendingPathComponent("Models")
        .appendingPathComponent("ggml-tiny.bin")

    private func makeEngine() throws -> WhisperEngine {
        guard ProcessInfo.processInfo.environment["MINTZO_E2E"] == "1" else {
            throw XCTSkip("MINTZO_E2E != 1")
        }
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else {
            throw XCTSkip(
                "Modèle absent (\(Self.modelURL.path)) — lancer scripts/download-test-model.sh"
            )
        }
        return try WhisperEngine(modelPath: Self.modelURL)
    }

    /// Décode, tronque à la fenêtre produit (~3 s) et détecte parmi eu/fr.
    private func detect(url: URL, engine: WhisperEngine) async throws -> LanguageDetection {
        let samples = try AudioFileDecoder.decode(url: url)
        let window = Array(samples.prefix(TranscriptionService.detectionWindowSampleCount))
        return try await engine.detectLanguage(
            samples: window, among: TranscriptionService.detectionCandidates
        )
    }

    func testDetectsFrenchFixtureAsFrench() async throws {
        let engine = try makeEngine()
        let wavURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "bonjour-16k", withExtension: "wav"),
            "Fixture bonjour-16k.wav absente du bundle de test"
        )

        let detection = try await detect(url: wavURL, engine: engine)
        print("DETECTION-E2E [bonjour-16k.wav] → \(detection.language) (confiance \(detection.confidence))")

        XCTAssertEqual(detection.language, "fr")
        XCTAssertGreaterThanOrEqual(
            detection.confidence, TranscriptionService.detectionConfidenceThreshold,
            "la fixture fr doit passer le seuil produit"
        )
    }

    func testDetectsBasqueSampleAsBasque() async throws {
        let engine = try makeEngine()
        guard let path = ProcessInfo.processInfo.environment["MINTZO_E2E_AUDIO_EU"] else {
            throw XCTSkip("MINTZO_E2E_AUDIO_EU non fourni (chemin d'un wav de parole basque)")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Échantillon basque introuvable : \(url.path)")
        }

        let detection = try await detect(url: url, engine: engine)
        print("DETECTION-E2E [\(url.lastPathComponent)] → \(detection.language) (confiance \(detection.confidence))")

        XCTAssertEqual(detection.language, "eu")
        XCTAssertGreaterThanOrEqual(
            detection.confidence, TranscriptionService.detectionConfidenceThreshold,
            "l'échantillon eu doit passer le seuil produit"
        )
    }

    /// Moins de 0,5 s d'audio : erreur typée, jamais un verdict fantaisiste.
    func testTooShortAudioThrowsTypedError() async throws {
        let engine = try makeEngine()
        do {
            _ = try await engine.detectLanguage(
                samples: Array(repeating: 0.05, count: 1_000), among: ["eu", "fr"]
            )
            XCTFail("détection attendue en erreur sur 1 000 échantillons")
        } catch let error as WhisperError {
            XCTAssertEqual(error, .insufficientAudioForDetection)
        }
    }
}
