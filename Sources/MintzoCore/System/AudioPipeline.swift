import AVFoundation

/// Une fenêtre d'audio convertie, prête pour l'UI et l'accumulation :
/// échantillons mono 16 kHz Float32 + niveau RMS de la fenêtre.
///
/// Le RMS alimente la waveform du HUD (design-language §4.2 : une barre
/// toutes les ~66 ms, amplitude = RMS de la fenêtre, mappée log côté UI).
public struct CaptureChunk: Sendable, Equatable {
    /// Échantillons PCM normalisés [-1, 1], mono, 16 kHz (~66 ms par fenêtre).
    public let samples: [Float]
    /// Niveau RMS de la fenêtre, dans [0, 1] pour un signal normalisé.
    public let rms: Float

    public init(samples: [Float], rms: Float) {
        self.samples = samples
        self.rms = rms
    }
}

/// Découpe un flux d'échantillons en fenêtres de taille fixe (~66 ms à 16 kHz)
/// et calcule le RMS de chaque fenêtre.
///
/// Pure Swift, aucune dépendance audio : testable headless avec des buffers
/// synthétiques. Conserve le reliquat entre deux appels (`consume` peut être
/// nourri par paquets de taille arbitraire).
struct RMSChunker: Sendable {
    /// 66 ms à 16 kHz — cadence des barres de la waveform HUD.
    static let defaultWindowSize = 1_056

    let windowSize: Int
    private var pending: [Float] = []

    init(windowSize: Int = RMSChunker.defaultWindowSize) {
        precondition(windowSize > 0, "windowSize doit être strictement positif")
        self.windowSize = windowSize
    }

    /// Absorbe des échantillons et rend toutes les fenêtres complètes disponibles.
    mutating func consume(_ samples: [Float]) -> [CaptureChunk] {
        pending.append(contentsOf: samples)
        guard pending.count >= windowSize else { return [] }
        var chunks: [CaptureChunk] = []
        var start = 0
        while pending.count - start >= windowSize {
            let window = Array(pending[start ..< start + windowSize])
            chunks.append(CaptureChunk(samples: window, rms: Self.rms(of: window)))
            start += windowSize
        }
        pending.removeFirst(start)
        return chunks
    }

    /// Vide la fenêtre partielle restante (fin de session), ou `nil` si rien en attente.
    mutating func drain() -> CaptureChunk? {
        guard !pending.isEmpty else { return nil }
        let window = pending
        pending = []
        return CaptureChunk(samples: window, rms: Self.rms(of: window))
    }

    /// RMS = racine de la moyenne des carrés. Sinus d'amplitude A → A/√2 ; DC → |A|.
    static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var acc: Float = 0
        for s in samples { acc += s * s }
        return (acc / Float(samples.count)).squareRoot()
    }
}

/// Convertit des buffers au format matériel (ex. 48 kHz stéréo) vers mono
/// 16 kHz Float32 via `AVAudioConverter`.
///
/// Non thread-safe : une instance est possédée par un seul tap à la fois et
/// doit être **recréée à chaque changement de device** (les AirPods et autres
/// périphériques changent le sample rate d'entrée — cf. notes/research/mac-stack.md §4).
/// Ne jamais imposer 16 kHz directement dans `installTap` : on tape au format
/// natif puis on convertit ici.
final class AudioResampler {
    static let targetSampleRate = 16_000.0

    private let converter: AVAudioConverter
    private let inputSampleRate: Double
    private let outputFormat: AVAudioFormat
    private let feeder = Feeder()

    /// Boîte pour l'input block d'`AVAudioConverter` (typé `@Sendable` dans le SDK,
    /// il ne peut donc pas capturer un `AVAudioPCMBuffer` directement).
    /// Sûr : `convert(to:error:withInputFrom:)` invoque le block de façon
    /// synchrone sur le thread appelant — aucun accès concurrent possible.
    private final class Feeder: @unchecked Sendable {
        var pending: AVAudioPCMBuffer?
    }

    /// `nil` si le format d'entrée est inutilisable ou si le convertisseur
    /// ne peut pas être créé.
    init?(inputFormat: AVAudioFormat) {
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.targetSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }
        self.converter = converter
        self.inputSampleRate = inputFormat.sampleRate
        self.outputFormat = outputFormat
    }

    /// Convertit un buffer complet et retourne les échantillons mono 16 kHz produits.
    ///
    /// L'input block ne fournit le buffer qu'une seule fois par appel (piège
    /// classique du convert block-based) ; la boucle draine le convertisseur
    /// tant qu'il remplit entièrement le buffer de sortie. Le filtre de
    /// rééchantillonnage retient quelques frames de latence interne —
    /// négligeable pour la dictée.
    func resample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        let ratio = Self.targetSampleRate / inputSampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        feeder.pending = buffer

        let feeder = self.feeder
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            guard let pending = feeder.pending else {
                outStatus.pointee = .noDataNow
                return nil
            }
            feeder.pending = nil
            outStatus.pointee = .haveData
            return pending
        }

        var result: [Float] = []
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError, withInputFrom: inputBlock)
            if out.frameLength > 0, let channel = out.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            }
            // .haveData avec buffer de sortie plein → il peut rester des frames
            // bufferisées en interne, on reboucle. Tout autre statut = terminé.
            guard status == .haveData, out.frameLength == capacity else { break }
        }
        return result
    }

    /// Draine la queue interne du convertisseur (fin de session).
    ///
    /// En mode streaming (`.noDataNow`), le filtre de rééchantillonnage retient
    /// plusieurs centaines d'échantillons (~15-45 ms mesurés) : sans flush, la
    /// fin du dernier mot dicté serait tronquée. Après flush, le convertisseur
    /// ne doit plus être réutilisé (une session = un resampler neuf).
    func flush() -> [Float] {
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        var result: [Float] = []
        let capacity: AVAudioFrameCount = 1_024
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError, withInputFrom: inputBlock)
            if out.frameLength > 0, let channel = out.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            }
            guard status == .haveData, out.frameLength == capacity else { break }
        }
        return result
    }
}
