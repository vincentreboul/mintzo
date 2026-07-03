import AVFoundation
import XCTest
@testable import MintzoCore

/// Tests headless du pipeline de capture : conversion et fenêtrage RMS testés
/// avec des buffers synthétiques — AUCUN micro ni permission requis.
final class SystemCaptureTests: XCTestCase {

    // MARK: - Helpers

    /// Buffer PCM Float32 non-entrelacé rempli d'un sinus identique sur tous
    /// les canaux.
    private func makeSineBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frames: AVAudioFrameCount,
        frequency: Double,
        amplitude: Float
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0 ..< Int(frames) {
            let value = amplitude * Float(sin(2.0 * .pi * frequency * Double(frame) / sampleRate))
            for channel in 0 ..< Int(channels) {
                channelData[channel][frame] = value
            }
        }
        return buffer
    }

    private func rms(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    // MARK: - AudioResampler : 48 kHz stéréo → 16 kHz mono

    func testResamplerConverts48kStereoTo16kMonoWithExpectedCount() throws {
        let resampler = try XCTUnwrap(
            AudioResampler(inputFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        )
        // 0,3 s à 48 kHz = 14 400 frames → attendu ≈ 4 800 échantillons à 16 kHz.
        let buffer = try makeSineBuffer(
            sampleRate: 48_000, channels: 2, frames: 14_400, frequency: 440, amplitude: 0.5
        )
        let streamed = resampler.resample(buffer)
        // En streaming, le filtre retient une queue interne (plusieurs
        // centaines d'échantillons) : la sortie est partielle mais jamais
        // excédentaire.
        XCTAssertLessThanOrEqual(streamed.count, 4_864)
        XCTAssertGreaterThan(streamed.count, 3_800)
        XCTAssertFalse(streamed.contains { $0.isNaN })

        // flush() draine la queue : le total doit couvrir la durée complète.
        let flushed = resampler.flush()
        XCTAssertEqual(streamed.count + flushed.count, 4_800, accuracy: 64)
    }

    func testResamplerPreservesSineAmplitudeRMS() throws {
        let amplitude: Float = 0.5
        let resampler = try XCTUnwrap(
            AudioResampler(inputFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        )
        let buffer = try makeSineBuffer(
            sampleRate: 48_000, channels: 2, frames: 24_000, frequency: 440, amplitude: amplitude
        )
        let output = resampler.resample(buffer)
        XCTAssertGreaterThan(output.count, 4_000)

        // RMS mesuré sur la partie centrale (évite les transitoires du filtre
        // aux bords). Sinus d'amplitude A → RMS théorique A/√2 ≈ 0,3536.
        let quarter = output.count / 4
        let measured = rms(of: output[quarter ..< output.count - quarter])
        let expected = amplitude / Float(2).squareRoot()
        XCTAssertEqual(measured, expected, accuracy: expected * 0.05,
                       "RMS après conversion doit rester ≈ A/√2")
    }

    func testResamplerStereoDownmixDoesNotDoubleAmplitude() throws {
        // Deux canaux identiques à 0,5 : le downmix mono ne doit pas sommer
        // (sinon amplitude 1,0 → RMS 0,707 au lieu de 0,354).
        let resampler = try XCTUnwrap(
            AudioResampler(inputFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        )
        let buffer = try makeSineBuffer(
            sampleRate: 48_000, channels: 2, frames: 24_000, frequency: 330, amplitude: 0.5
        )
        let output = resampler.resample(buffer)
        let peak = output.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.55, "le downmix stéréo→mono ne doit pas amplifier le signal")
    }

    func testResamplerPassthrough16kMonoKeepsSampleCount() throws {
        let resampler = try XCTUnwrap(
            AudioResampler(inputFormat: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!)
        )
        let buffer = try makeSineBuffer(
            sampleRate: 16_000, channels: 1, frames: 1_600, frequency: 200, amplitude: 0.3
        )
        let output = resampler.resample(buffer)
        XCTAssertEqual(output.count, 1_600, accuracy: 16)
    }

    func testResamplerEmptyBufferYieldsNothing() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let resampler = try XCTUnwrap(AudioResampler(inputFormat: format))
        let empty = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        empty.frameLength = 0
        XCTAssertTrue(resampler.resample(empty).isEmpty)
    }

    // MARK: - RMSChunker : fenêtrage 66 ms + RMS

    func testChunkerEmitsFixedWindowsWithExactDCLevel() {
        var chunker = RMSChunker()
        let level: Float = 0.25
        // 2 fenêtres complètes + 100 échantillons de reliquat.
        let feed = [Float](repeating: level, count: RMSChunker.defaultWindowSize * 2 + 100)
        let chunks = chunker.consume(feed)

        XCTAssertEqual(chunks.count, 2)
        for chunk in chunks {
            XCTAssertEqual(chunk.samples.count, RMSChunker.defaultWindowSize)
            // Signal constant → RMS exactement égal au niveau.
            XCTAssertEqual(chunk.rms, level, accuracy: 1e-6)
        }
        let remainder = chunker.drain()
        XCTAssertEqual(remainder?.samples.count, 100)
        XCTAssertEqual(remainder?.rms ?? 0, level, accuracy: 1e-6)
    }

    func testChunkerSineRMSMatchesTheory() {
        let amplitude: Float = 0.8
        // Fenêtre = multiple entier de la période (1 056 = 66 périodes de 16
        // échantillons) → RMS théorique exact A/√2, sans effet de bord.
        var chunker = RMSChunker()
        let window = RMSChunker.defaultWindowSize
        let samples = (0 ..< window).map { i in
            amplitude * Float(sin(2.0 * .pi * Double(i) / 16.0))
        }
        let chunks = chunker.consume(samples)
        XCTAssertEqual(chunks.count, 1)
        let expected = amplitude / Float(2).squareRoot()
        XCTAssertEqual(chunks[0].rms, expected, accuracy: 1e-3)
    }

    func testChunkerKeepsRemainderAcrossFeeds() {
        var chunker = RMSChunker(windowSize: 1_000)
        XCTAssertTrue(chunker.consume([Float](repeating: 0.1, count: 700)).isEmpty)
        // 700 + 700 = 1 400 → une fenêtre de 1 000, reliquat 400.
        let chunks = chunker.consume([Float](repeating: 0.1, count: 700))
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].samples.count, 1_000)
        XCTAssertEqual(chunker.drain()?.samples.count, 400)
        XCTAssertNil(chunker.drain(), "drain doit vider le reliquat")
    }

    func testChunkerSilenceHasZeroRMS() {
        var chunker = RMSChunker()
        let chunks = chunker.consume([Float](repeating: 0, count: RMSChunker.defaultWindowSize))
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].rms, 0)
    }

    func testRMSOfEmptyIsZero() {
        XCTAssertEqual(RMSChunker.rms(of: []), 0)
    }

    // MARK: - Chaîne complète synthétique (converter → chunker)

    func testFullPipelineSyntheticBuffersProduceCoherentChunks() throws {
        let resampler = try XCTUnwrap(
            AudioResampler(inputFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        )
        var chunker = RMSChunker()
        var session: [Float] = []
        var chunks: [CaptureChunk] = []

        // 10 buffers de 4 800 frames (0,1 s chacun) = 1 s d'audio.
        for _ in 0 ..< 10 {
            let buffer = try makeSineBuffer(
                sampleRate: 48_000, channels: 2, frames: 4_800, frequency: 440, amplitude: 0.4
            )
            let converted = resampler.resample(buffer)
            session.append(contentsOf: converted)
            chunks.append(contentsOf: chunker.consume(converted))
        }
        // Fin de session : drainage de la queue du convertisseur (cf. stop()).
        session.append(contentsOf: resampler.flush())

        // 1 s à 16 kHz ≈ 16 000 échantillons ≈ 15 fenêtres de 1 056.
        XCTAssertEqual(session.count, 16_000, accuracy: 128)
        XCTAssertEqual(chunks.count, 15, accuracy: 1)
        let expected: Float = 0.4 / Float(2).squareRoot()
        // Les fenêtres du milieu doivent porter le RMS du sinus.
        for chunk in chunks.dropFirst().dropLast() {
            XCTAssertEqual(chunk.rms, expected, accuracy: expected * 0.08)
        }
    }
}

private func XCTAssertEqual(_ value: Int, _ expected: Int, accuracy: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(
        abs(value - expected), accuracy,
        "\(value) hors de ±\(accuracy) autour de \(expected)",
        file: file, line: line
    )
}
