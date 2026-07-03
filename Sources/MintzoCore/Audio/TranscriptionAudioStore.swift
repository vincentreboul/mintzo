import Foundation

/// Conserve l'audio des transcriptions pour la réécoute et la relance.
///
/// Un fichier WAV par entrée d'historique — PCM 16 bits mono 16 kHz, le format
/// exact des échantillons du pipeline (`CaptureService` / `AudioFileDecoder`) :
/// aucun ré-encodage, relisible tel quel par `AVAudioPlayer` ET re-décodable
/// par `AudioFileDecoder` pour repasser dans whisper.
///
/// - Emplacement : `~/Library/Application Support/Mintzo/Audio/<uuid>.wav`
///   via ``standard()``, répertoire injectable via ``init(directory:)`` (tests).
/// - Écriture atomique (`Data.write(options: .atomic)`) : jamais de WAV
///   tronqué visible, même si l'app meurt en pleine écriture.
/// - Les échecs d'écriture sont l'affaire de l'appelant : ils ne doivent
///   JAMAIS faire échouer la transcription (audioPath nil + log).
public final class TranscriptionAudioStore: Sendable {

    /// Répertoire des fichiers audio (créé paresseusement à la première écriture).
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Store par défaut de l'app : `~/Library/Application Support/Mintzo/Audio/`.
    public static func standard() throws -> TranscriptionAudioStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("Mintzo", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
        return TranscriptionAudioStore(directory: directory)
    }

    // MARK: - Écriture

    /// Écrit les échantillons (PCM Float32 mono 16 kHz, normalisés [-1, 1])
    /// dans un nouveau fichier `<uuid>.wav` et retourne son URL.
    @discardableResult
    public func write(samples: [Float]) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + ".wav")
        try Self.wavData(samples: samples).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Suppression

    /// Supprime un fichier audio conservé — best effort : fichier déjà absent
    /// ou chemin invalide, rien ne lève (la suppression d'une entrée
    /// d'historique ne doit jamais échouer à cause de son audio).
    public static func remove(atPath path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Encodage WAV

    /// Encode des échantillons Float32 [-1, 1] en WAV PCM 16 bits mono.
    /// Format canonique 44 octets d'en-tête RIFF + données little-endian.
    public static func wavData(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        let byteRate = sampleRate * bytesPerSample // mono

        var data = Data(capacity: 44 + dataSize)
        // RIFF chunk
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        // fmt chunk (PCM)
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))                 // taille du chunk fmt
        data.appendLittleEndian(UInt16(1))                  // format PCM
        data.appendLittleEndian(UInt16(1))                  // mono
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(bytesPerSample))     // block align
        data.appendLittleEndian(UInt16(16))                 // bits par échantillon
        // data chunk
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(dataSize))
        var payload = [UInt8]()
        payload.reserveCapacity(dataSize)
        for sample in samples {
            // Clamp avant quantification : un float hors [-1, 1] (bruit, gain)
            // ne doit pas wrapper en Int16.
            let clamped = min(max(sample, -1), 1)
            let value = Int16((clamped * Float(Int16.max)).rounded())
            let bits = UInt16(bitPattern: value)
            payload.append(UInt8(truncatingIfNeeded: bits))
            payload.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        data.append(contentsOf: payload)
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
