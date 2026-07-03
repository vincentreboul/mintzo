import AVFoundation
import Foundation

/// Erreurs de décodage audio, typées et parlantes.
public enum AudioDecodingError: Error, LocalizedError, Sendable {
    /// Le fichier n'existe pas sur le disque.
    case fileNotFound(path: String)
    /// CoreAudio ne reconnaît pas ce format/conteneur (ex. fichier texte, codec exotique).
    case unsupportedFormat(path: String, detail: String)
    /// Conteneur reconnu mais données illisibles (fichier tronqué, corrompu).
    case corruptedFile(path: String, detail: String)
    /// Le fichier ne contient aucun échantillon audio.
    case emptyAudio(path: String)
    /// La conversion vers mono 16 kHz Float32 a échoué.
    case conversionFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Fichier audio introuvable : \(path)"
        case .unsupportedFormat(let path, let detail):
            return "Format audio non supporté (\(path)) : \(detail)"
        case .corruptedFile(let path, let detail):
            return "Fichier audio illisible ou corrompu (\(path)) : \(detail)"
        case .emptyAudio(let path):
            return "Le fichier ne contient aucun échantillon audio : \(path)"
        case .conversionFailed(let detail):
            return "Conversion audio vers mono 16 kHz échouée : \(detail)"
        }
    }
}

/// Décode un fichier audio en PCM Float32 mono 16 kHz — le format d'entrée de WhisperEngine.
///
/// S'appuie sur CoreAudio (`AVAudioFile`) pour la lecture : tous les formats lus
/// nativement par macOS sont supportés (.wav, .m4a, .mp3, .aac, .flac, et
/// .opus/.ogg — Ogg Opus/Vorbis lus nativement par CoreAudio sur macOS 26,
/// vérifié par `afinfo` et par les tests). Le resampling est systématique :
/// Opus, par exemple, est toujours décodé en 48 kHz par CoreAudio quel que soit
/// son taux d'encodage, d'où conversion 48 kHz → 16 kHz via `AVAudioConverter`.
///
/// La conversion se fait en streaming par blocs de 64k frames : la mémoire ne
/// dépend pas de la taille du fichier d'entrée (hors tableau de sortie).
public struct AudioFileDecoder {

    /// Taux d'échantillonnage attendu par whisper.cpp.
    public static let targetSampleRate: Double = 16_000

    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Décode `url` en échantillons PCM Float32 normalisés [-1, 1], mono, 16 kHz.
    public static func decode(url: URL) throws -> [Float] {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioDecodingError.fileNotFound(path: path)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Self.mapOpenError(error, path: path)
        }

        let inputFormat = file.processingFormat
        guard file.length > 0, inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioDecodingError.emptyAudio(path: path)
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioDecodingError.conversionFailed(detail: "format cible 16 kHz mono invalide")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioDecodingError.unsupportedFormat(
                path: path,
                detail: "aucun convertisseur \(inputFormat) → mono 16 kHz Float32"
            )
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.chunkFrames) else {
            throw AudioDecodingError.conversionFailed(detail: "allocation du buffer d'entrée impossible")
        }

        // Estimation de la taille de sortie pour éviter les réallocations.
        let estimatedFrames = Int(Double(file.length) * Self.targetSampleRate / inputFormat.sampleRate)
        var samples: [Float] = []
        samples.reserveCapacity(estimatedFrames + Int(Self.chunkFrames))

        // `AVAudioConverterInputBlock` est `@Sendable` dans le SDK, mais
        // `convert(to:error:withInputFrom:)` l'appelle de façon SYNCHRONE sur le
        // thread appelant — aucun accès concurrent réel. La box `@unchecked
        // Sendable` sert uniquement à satisfaire le vérificateur Swift 6.
        let reader = FileReaderBox(file: file, buffer: inputBuffer)

        let inputBlock: AVAudioConverterInputBlock = { _, statusPtr in
            // Guard EOF AVANT read : `AVAudioFile.read(into:)` à framePosition == length
            // jette `_GenericObjCError 0` (nilError) au lieu de rendre 0 frame
            // (vérifié empiriquement sur macOS 26).
            if reader.reachedEndOfFile || reader.file.framePosition >= reader.file.length {
                reader.reachedEndOfFile = true
                statusPtr.pointee = .endOfStream
                return nil
            }
            reader.buffer.frameLength = 0
            do {
                try reader.file.read(into: reader.buffer)
            } catch {
                reader.readError = error
                reader.reachedEndOfFile = true
                statusPtr.pointee = .endOfStream
                return nil
            }
            if reader.buffer.frameLength == 0 {
                reader.reachedEndOfFile = true
                statusPtr.pointee = .endOfStream
                return nil
            }
            statusPtr.pointee = .haveData
            return reader.buffer
        }

        conversion: while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: Self.chunkFrames
            ) else {
                throw AudioDecodingError.conversionFailed(detail: "allocation du buffer de sortie impossible")
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

            if let readError = reader.readError {
                throw AudioDecodingError.corruptedFile(
                    path: path,
                    detail: "lecture interrompue : \(readError.localizedDescription)"
                )
            }

            switch status {
            case .haveData:
                Self.append(outputBuffer, to: &samples)
            case .endOfStream:
                Self.append(outputBuffer, to: &samples)
                break conversion
            case .inputRanDry:
                Self.append(outputBuffer, to: &samples)
                if reader.reachedEndOfFile && outputBuffer.frameLength == 0 { break conversion }
            case .error:
                throw AudioDecodingError.conversionFailed(
                    detail: conversionError?.localizedDescription ?? "erreur AVAudioConverter inconnue"
                )
            @unknown default:
                throw AudioDecodingError.conversionFailed(detail: "statut AVAudioConverter inattendu")
            }
        }

        guard !samples.isEmpty else {
            throw AudioDecodingError.emptyAudio(path: path)
        }
        return samples
    }

    /// État de lecture partagé avec l'input block du converter.
    ///
    /// `@unchecked Sendable` justifié : le block `@Sendable` qui capture cette box
    /// est invoqué exclusivement de façon synchrone par
    /// `AVAudioConverter.convert(to:error:withInputFrom:)` sur le thread appelant
    /// de `decode(url:)` — jamais deux accès simultanés.
    private final class FileReaderBox: @unchecked Sendable {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        var reachedEndOfFile = false
        var readError: Error?

        init(file: AVAudioFile, buffer: AVAudioPCMBuffer) {
            self.file = file
            self.buffer = buffer
        }
    }

    /// Ajoute le contenu d'un buffer mono Float32 au tableau de sortie.
    private static func append(_ buffer: AVAudioPCMBuffer, to samples: inout [Float]) {
        guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Traduit l'erreur CoreAudio d'ouverture en erreur typée parlante.
    private static func mapOpenError(_ error: Error, path: String) -> AudioDecodingError {
        let nsError = error as NSError
        let detail = "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
        switch nsError.code {
        case Int(kAudioFileUnsupportedFileTypeError),   // 'typ?' — conteneur inconnu
             Int(kAudioFileUnsupportedDataFormatError), // 'fmt?' — codec non supporté
             Int(kAudioFileUnsupportedPropertyError):   // 'pty?'
            return .unsupportedFormat(path: path, detail: detail)
        case Int(kAudioFileInvalidFileError),           // 'dta?' — données invalides
             Int(kAudioFileInvalidPacketOffsetError),
             Int(kAudioFileEndOfFileError):
            return .corruptedFile(path: path, detail: detail)
        default:
            // Par défaut : fichier présent mais illisible → corrompu ou format inconnu,
            // le détail CoreAudio est conservé pour le diagnostic.
            return .unsupportedFormat(path: path, detail: detail)
        }
    }
}
