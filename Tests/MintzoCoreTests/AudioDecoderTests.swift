import XCTest
@testable import MintzoCore

/// Tests d'`AudioFileDecoder` : WAV 16 kHz natif, Ogg Opus 48 kHz (resamplé),
/// formats invalides.
final class AudioDecoderTests: XCTestCase {

    private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: ext),
            "Fixture \(name).\(ext) absente du bundle de test"
        )
    }

    /// Vérifie les invariants communs : pas de NaN/inf, signal non silencieux.
    private func assertSaneSamples(_ samples: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            samples.contains { $0.isNaN || $0.isInfinite },
            "Les échantillons contiennent des NaN/inf", file: file, line: line
        )
        let peak = samples.reduce(0) { max($0, abs($1)) }
        XCTAssertGreaterThan(peak, 0.01, "Signal quasi silencieux (pic \(peak))", file: file, line: line)
        XCTAssertLessThanOrEqual(peak, 1.0, "Échantillons hors [-1, 1] (pic \(peak))", file: file, line: line)
    }

    /// WAV mono 16 kHz (3.518 s) : passage 1:1, longueur exacte à ±1 %.
    func testDecodesWav16k() throws {
        let url = try fixtureURL("bonjour-16k", "wav")
        let samples = try AudioFileDecoder.decode(url: url)

        let expected = Int(3.517812 * 16_000) // durée afinfo de la fixture
        XCTAssertEqual(Double(samples.count), Double(expected), accuracy: Double(expected) * 0.01,
                       "Longueur incohérente avec la durée du WAV")
        assertSaneSamples(samples)
    }

    /// Ogg Opus (vocal type WhatsApp, 5.809 s) : CoreAudio décode en 48 kHz,
    /// le décodeur doit resampler en 16 kHz. Tolérance 5 % (pre-skip Opus).
    func testDecodesOggOpus() throws {
        let url = try fixtureURL("phrase-fr", "opus")
        let samples = try AudioFileDecoder.decode(url: url)

        let expected = Int(5.809062 * 16_000) // durée afinfo de la fixture
        XCTAssertEqual(Double(samples.count), Double(expected), accuracy: Double(expected) * 0.05,
                       "Longueur incohérente avec la durée de l'Opus")
        assertSaneSamples(samples)
    }

    /// Un fichier non-audio doit lever une erreur typée, pas crasher.
    func testUnknownFormatThrowsTypedError() throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-bogus-\(UUID().uuidString).xyz")
        try Data("ceci n'est pas de l'audio, juste du texte".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        XCTAssertThrowsError(try AudioFileDecoder.decode(url: bogus)) { error in
            guard let decodingError = error as? AudioDecodingError else {
                return XCTFail("Erreur non typée : \(error)")
            }
            switch decodingError {
            case .unsupportedFormat, .corruptedFile:
                XCTAssertFalse(decodingError.localizedDescription.isEmpty)
            default:
                XCTFail("Cas d'erreur inattendu : \(decodingError)")
            }
        }
    }

    /// Fichier absent → .fileNotFound.
    func testMissingFileThrowsFileNotFound() {
        let missing = URL(fileURLWithPath: "/nonexistent/mintzo-\(UUID().uuidString).wav")
        XCTAssertThrowsError(try AudioFileDecoder.decode(url: missing)) { error in
            guard case .fileNotFound = error as? AudioDecodingError else {
                return XCTFail("Attendu .fileNotFound, obtenu : \(error)")
            }
        }
    }
}
