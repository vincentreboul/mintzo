import Foundation
import AVFoundation
import Observation

// Contrôleur du lecteur audio du détail de transcription — logique PURE
// (Foundation + AVFoundation, pas de SwiftUI). Compilé aussi dans
// MintzoCoreTests (symlink Tests/MintzoCoreTests/AudioPlayerController.swift)
// pour tester les états play / pause / fin avec un backend mock.

/// Moteur de lecture abstrait — `AVAudioPlayer` en prod, mock dans les tests.
@MainActor
protocol AudioPlaybackBackend: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get }
    /// Fin de lecture naturelle (le fichier est arrivé au bout).
    var onFinish: (() -> Void)? { get set }
    func play()
    func pause()
    /// Stop + retour au début.
    func stop()
}

/// Contrôleur d'écoute d'un WAV conservé. Un seul lecteur actif dans l'app :
/// démarrer une lecture stoppe celle qui serait en cours ailleurs (autre
/// fenêtre de détail). L'appelant DOIT appeler ``stop()`` au dismiss de la vue.
@MainActor
@Observable
final class AudioPlayerController {

    enum PlaybackState: Equatable {
        case idle       // au repos, position 0
        case playing
        case paused
    }

    // MARK: État observé

    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    /// Durée du fichier une fois le backend chargé, sinon durée de repli
    /// (celle de l'entrée d'historique) — l'UI a toujours un total à afficher.
    private(set) var duration: TimeInterval
    /// Fichier illisible : le bouton lecture se désactive, pas d'erreur modale.
    private(set) var unavailable = false

    var progress: Double {
        duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    // MARK: Dépendances

    let url: URL
    private let makeBackend: @MainActor (URL) throws -> any AudioPlaybackBackend
    private var backend: (any AudioPlaybackBackend)?
    private var tickTask: Task<Void, Never>?

    /// Lecteur actif de l'app — exclusivité : `play()` stoppe le précédent.
    private static weak var active: AudioPlayerController?

    /// Cadence de rafraîchissement de la position pendant la lecture.
    static let tickInterval: Duration = .milliseconds(100)

    init(
        url: URL,
        fallbackDuration: TimeInterval = 0,
        makeBackend: @escaping @MainActor (URL) throws -> any AudioPlaybackBackend = {
            try AVAudioPlayerBackend(url: $0)
        }
    ) {
        self.url = url
        self.duration = fallbackDuration
        self.makeBackend = makeBackend
    }

    // MARK: Commandes

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .idle, .paused: play()
        }
    }

    func play() {
        guard state != .playing, !unavailable else { return }
        guard let backend = loadBackendIfNeeded() else { return }
        // Un seul lecteur actif : le précédent s'arrête proprement.
        if let other = Self.active, other !== self {
            other.stop()
        }
        Self.active = self
        backend.play()
        state = .playing
        startTicking()
    }

    func pause() {
        guard state == .playing, let backend else { return }
        backend.pause()
        stopTicking()
        currentTime = backend.currentTime
        state = .paused
    }

    /// Arrêt complet, position remise à zéro — appelé par la croix de la vue
    /// au dismiss, et par l'exclusivité quand un autre lecteur démarre.
    func stop() {
        stopTicking()
        backend?.stop()
        currentTime = 0
        state = .idle
        if Self.active === self { Self.active = nil }
    }

    // MARK: Interne

    private func loadBackendIfNeeded() -> (any AudioPlaybackBackend)? {
        if let backend { return backend }
        do {
            let backend = try makeBackend(url)
            backend.onFinish = { [weak self] in self?.handleFinish() }
            if backend.duration > 0 { duration = backend.duration }
            self.backend = backend
            return backend
        } catch {
            NSLog("Mintzo: lecteur — audio illisible (%@) : %@", url.path, error.localizedDescription)
            unavailable = true
            return nil
        }
    }

    private func handleFinish() {
        // Fin naturelle : prêt à réécouter depuis le début.
        stopTicking()
        currentTime = 0
        state = .idle
        if Self.active === self { Self.active = nil }
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled, let self, self.state == .playing else { return }
                self.currentTime = self.backend?.currentTime ?? 0
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}

// MARK: - Backend AVAudioPlayer (prod)

/// Adaptateur `AVAudioPlayer` — délégué de fin relayé sur le main actor.
@MainActor
final class AVAudioPlayerBackend: NSObject, AudioPlaybackBackend, AVAudioPlayerDelegate {

    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval { player.currentTime }

    func play() { player.play() }
    func pause() { player.pause() }

    func stop() {
        player.stop()
        player.currentTime = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish?() }
    }
}
