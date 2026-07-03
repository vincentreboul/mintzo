import XCTest
@testable import MintzoCore

final class TranscriptionAudioStoreTests: XCTestCase {

    private var directory: URL!
    private var store: TranscriptionAudioStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-audio-tests-\(UUID().uuidString)", isDirectory: true)
        store = TranscriptionAudioStore(directory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// 0,5 s de sinus à 440 Hz — un signal réaliste, ni silence ni bruit.
    private func makeSamples(count: Int = 8_000, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * sin(2 * .pi * 440 * Float($0) / 16_000) }
    }

    // MARK: - En-tête WAV

    func testWavDataHasCanonicalHeader() {
        let samples = makeSamples(count: 100)
        let data = TranscriptionAudioStore.wavData(samples: samples)

        XCTAssertEqual(data.count, 44 + 200) // en-tête + 100 échantillons × 2 octets
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(readUInt16(data, at: 20), 1)        // PCM
        XCTAssertEqual(readUInt16(data, at: 22), 1)        // mono
        XCTAssertEqual(readUInt32(data, at: 24), 16_000)   // 16 kHz
        XCTAssertEqual(readUInt16(data, at: 34), 16)       // 16 bits
        XCTAssertEqual(readUInt32(data, at: 40), 200)      // taille des données
    }

    func testWavDataClampsOutOfRangeSamples() {
        // Un float hors [-1, 1] ne doit pas wrapper en Int16.
        let data = TranscriptionAudioStore.wavData(samples: [2.0, -2.0])
        XCTAssertEqual(readInt16(data, at: 44), Int16.max)
        XCTAssertEqual(readInt16(data, at: 46), -Int16.max) // -1 × 32767
    }

    // MARK: - Aller-retour écriture / décodage

    func testWriteProducesWavDecodableByAudioFileDecoder() throws {
        let samples = makeSamples()
        let url = try store.write(samples: samples)

        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Le WAV conservé repasse dans le MÊME décodeur que les fichiers
        // importés — c'est le chemin réel de la relance.
        let decoded = try AudioFileDecoder.decode(url: url)
        XCTAssertEqual(decoded.count, samples.count)
        for index in stride(from: 0, to: samples.count, by: 500) {
            XCTAssertEqual(decoded[index], samples[index], accuracy: 0.001,
                           "échantillon \(index) hors tolérance de quantification")
        }
    }

    func testWriteCreatesDirectoryLazily() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        _ = try store.write(samples: makeSamples(count: 10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEachWriteGetsDistinctFile() throws {
        let first = try store.write(samples: makeSamples(count: 10))
        let second = try store.write(samples: makeSamples(count: 10))
        XCTAssertNotEqual(first, second)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents.count, 2)
    }

    // MARK: - Suppression

    func testRemoveDeletesFile() throws {
        let url = try store.write(samples: makeSamples(count: 10))
        TranscriptionAudioStore.remove(atPath: url.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemoveIsSilentOnMissingFileNilAndEmptyPath() {
        // Best effort : aucune de ces formes ne doit lever ni crasher.
        TranscriptionAudioStore.remove(atPath: directory.appendingPathComponent("absent.wav").path)
        TranscriptionAudioStore.remove(atPath: nil)
        TranscriptionAudioStore.remove(atPath: "")
    }

    // MARK: - Helpers de lecture binaire

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(readUInt16(data, at: offset)) | (UInt32(readUInt16(data, at: offset + 2)) << 16)
    }

    private func readInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, at: offset))
    }
}
