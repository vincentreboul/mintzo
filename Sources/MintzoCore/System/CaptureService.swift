import AVFoundation
import os

/// Erreurs typées de la capture micro.
public enum CaptureError: Error, Sendable, Equatable {
    /// Permission micro absente (refusée, restreinte ou jamais demandée).
    /// Passer par `PermissionsService` avant de démarrer une session.
    case permissionDenied
    /// Aucun périphérique d'entrée utilisable (format matériel invalide).
    case microphoneUnavailable
    /// Impossible de créer le convertisseur vers 16 kHz mono.
    case converterSetupFailed
    /// L'`AVAudioEngine` n'a pas démarré.
    case engineStartFailed(String)
    /// `start()` appelé alors qu'une session est déjà en cours.
    case alreadyRunning
}

/// Capture micro : `AVAudioEngine` + tap au format natif du device,
/// conversion vers mono 16 kHz Float32 (format d'entrée de Whisper).
///
/// - `start()` retourne un `AsyncStream<CaptureChunk>` : une fenêtre ~66 ms
///   + RMS par élément, pour la waveform du HUD (design-language §4.2-4.3).
///   Le stream droppe les fenêtres les plus anciennes si l'UI ne suit pas —
///   la transcription ne dépend PAS du stream mais de `stop()`.
/// - `stop()` retourne la **totalité** des échantillons 16 kHz de la session,
///   à passer à `WhisperEngine.transcribe(samples:language:)`.
/// - Le convertisseur est recréé sur `AVAudioEngineConfigurationChange`
///   (changement de device, ex. AirPods — sample rate différent).
///
/// Modélisé en `actor` : l'engine et l'état de session sont sérialisés par
/// l'isolation ; le tap temps-réel ne touche que `CapturePipeline` (Mutex).
public actor CaptureService {

    /// Moteur audio. `nonisolated(unsafe)` requis pour l'enregistrement de
    /// l'observer de notification (`object:`) et le `deinit` — même précédent
    /// que `WhisperEngine.ctx`. Sûr : toutes les mutations de l'engine passent
    /// par des méthodes isolées de l'acteur ; la notification ne fait que
    /// re-dispatcher vers l'acteur.
    private nonisolated(unsafe) let engine = AVAudioEngine()

    private let pipeline = CapturePipeline()
    private var continuation: AsyncStream<CaptureChunk>.Continuation?
    /// Token d'observation. `nonisolated(unsafe)` pour le retrait dans le
    /// `deinit` (nonisolated en Swift 6) ; sûr : muté uniquement depuis les
    /// méthodes isolées, lu dans le deinit après la dernière référence.
    private nonisolated(unsafe) var configObserver: (any NSObjectProtocol)?
    private var running = false

    public init() {}

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        engine.stop()
    }

    /// La session est-elle en cours ?
    public var isRunning: Bool { running }

    /// Démarre la capture et retourne le flux de fenêtres (~66 ms, RMS inclus).
    ///
    /// Le flux se termine de lui-même si le device disparaît sans successeur
    /// utilisable ; appeler `stop()` reste nécessaire pour récupérer les
    /// échantillons accumulés.
    public func start() throws -> AsyncStream<CaptureChunk> {
        guard !running else { throw CaptureError.alreadyRunning }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CaptureError.permissionDenied
        }

        pipeline.reset()
        let (stream, continuation) = AsyncStream.makeStream(
            of: CaptureChunk.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation = continuation

        do {
            try installTap()
        } catch {
            teardown()
            throw error
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }

        running = true
        observeConfigurationChanges()
        return stream
    }

    /// Arrête la capture et retourne la totalité des échantillons mono 16 kHz
    /// de la session (queue du convertisseur incluse — le dernier mot n'est
    /// pas tronqué). Idempotent : rappeler après un arrêt rend `[]`.
    public func stop() -> [Float] {
        teardown()
        running = false
        return pipeline.finishSession()
    }

    // MARK: - Interne

    /// Installe le tap au format natif du device et branche le pipeline de
    /// conversion. Ne JAMAIS forcer 16 kHz dans `installTap` (crash si le
    /// device ne le supporte pas) — cf. notes/research/mac-stack.md §4.
    private func installTap() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw CaptureError.microphoneUnavailable
        }
        guard let resampler = AudioResampler(inputFormat: hwFormat) else {
            throw CaptureError.converterSetupFailed
        }
        pipeline.replaceResampler(resampler)

        let pipeline = self.pipeline
        let continuation = self.continuation
        input.installTap(onBus: 0, bufferSize: 2_048, format: hwFormat) { buffer, _ in
            // Thread audio temps-réel : conversion + fenêtrage sous Mutex
            // (verrou bref ; seuls stop()/changement de device le disputent).
            guard let continuation else { return }
            for chunk in pipeline.ingest(buffer) {
                continuation.yield(chunk)
            }
        }
    }

    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleConfigurationChange() }
        }
    }

    /// Changement de configuration (device branché/débranché, sample rate…) :
    /// l'engine s'est mis en pause ; on recrée le convertisseur au nouveau
    /// format et on repart. Si le nouveau device est inutilisable, la session
    /// se termine proprement (stream fini, échantillons conservés pour `stop()`).
    private func handleConfigurationChange() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTap()
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            continuation?.finish()
            continuation = nil
            engine.stop()
            running = false
        }
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }
}

/// État partagé entre le thread audio (tap) et l'acteur : convertisseur,
/// fenêtrage RMS et accumulation des échantillons de la session.
///
/// `OSAllocatedUnfairLock` + APIs `unchecked` : l'état contient un
/// `AVAudioConverter` non-Sendable et la conversion consomme un
/// `AVAudioPCMBuffer` task-isolated — les variantes vérifiées (`Mutex`,
/// `withLock @Sendable`) refusent ce mélange de régions. Sûr : TOUT accès à
/// l'état passe par le verrou ; le buffer n'est que lu pendant la conversion,
/// jamais stocké. Le tap tient le verrou brièvement (conversion + append) ;
/// les seuls autres accès (`reset`/`replaceResampler`/`drainSession`) sont
/// rares et hors temps-réel.
final class CapturePipeline: Sendable {
    private struct State {
        var resampler: AudioResampler?
        var chunker = RMSChunker()
        var sessionSamples: [Float] = []
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// Repart de zéro (nouvelle session).
    func reset() {
        state.withLockUnchecked {
            $0.chunker = RMSChunker()
            $0.sessionSamples = []
        }
    }

    /// Remplace le convertisseur (installation du tap, changement de device).
    /// Le fenêtrage et l'accumulation de session sont préservés.
    func replaceResampler(_ resampler: AudioResampler) {
        state.withLockUnchecked { $0.resampler = resampler }
    }

    /// Convertit un buffer natif, accumule les échantillons de session et
    /// retourne les fenêtres complètes prêtes pour le HUD.
    func ingest(_ buffer: AVAudioPCMBuffer) -> [CaptureChunk] {
        state.withLockUnchecked { s in
            guard let resampler = s.resampler else { return [] }
            let samples = resampler.resample(buffer)
            guard !samples.isEmpty else { return [] }
            s.sessionSamples.append(contentsOf: samples)
            return s.chunker.consume(samples)
        }
    }

    /// Rend la totalité des échantillons de la session — queue interne du
    /// convertisseur drainée incluse — et vide l'état. Le resampler flushé est
    /// mis au rebut (chaque session en réinstalle un neuf).
    func finishSession() -> [Float] {
        state.withLockUnchecked { s in
            var all = s.sessionSamples
            if let resampler = s.resampler {
                all.append(contentsOf: resampler.flush())
                s.resampler = nil
            }
            s.sessionSamples = []
            s.chunker = RMSChunker()
            return all
        }
    }
}
