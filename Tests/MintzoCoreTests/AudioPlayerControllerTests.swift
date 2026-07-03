import XCTest
@testable import MintzoCore

// Tests du contrôleur du lecteur (AudioPlayerController.swift, compilé ici
// via symlink) avec un backend mock : play / pause / fin, exclusivité du
// lecteur actif, fichier illisible.

// MARK: - Backend mock

@MainActor
private final class MockBackend: AudioPlaybackBackend {
    var duration: TimeInterval = 10
    var currentTime: TimeInterval = 0
    var onFinish: (() -> Void)?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }

    func stop() {
        stopCallCount += 1
        currentTime = 0
    }

    /// Simule la fin naturelle du fichier (délégué AVAudioPlayer).
    func finishNaturally() {
        currentTime = duration
        onFinish?()
    }
}

// MARK: - Tests

@MainActor
final class AudioPlayerControllerTests: XCTestCase {

    private func makeController(
        backend: MockBackend = MockBackend(),
        fallbackDuration: TimeInterval = 0
    ) -> (AudioPlayerController, MockBackend) {
        let controller = AudioPlayerController(
            url: URL(fileURLWithPath: "/tmp/mintzo-player-test.wav"),
            fallbackDuration: fallbackDuration,
            makeBackend: { _ in backend }
        )
        return (controller, backend)
    }

    // MARK: Play / pause

    func testInitialStateIsIdleWithFallbackDuration() {
        let (controller, _) = makeController(fallbackDuration: 42)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertEqual(controller.duration, 42)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertFalse(controller.unavailable)
    }

    func testPlayStartsBackendAndAdoptsItsDuration() {
        let (controller, backend) = makeController(fallbackDuration: 42)
        backend.duration = 7.5

        controller.play()

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertEqual(controller.duration, 7.5, "la vraie durée du fichier remplace le repli")
    }

    func testPauseFreezesPositionAndKeepsIt() {
        let (controller, backend) = makeController()
        controller.play()
        backend.currentTime = 3.2

        controller.pause()

        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(backend.pauseCallCount, 1)
        XCTAssertEqual(controller.currentTime, 3.2)
        XCTAssertEqual(controller.progress, 0.32, accuracy: 0.001)
    }

    func testTogglePlayPauseCyclesStates() {
        let (controller, _) = makeController()
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .playing)
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .paused)
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .playing)
    }

    func testResumeAfterPauseDoesNotRewind() {
        let (controller, backend) = makeController()
        controller.play()
        backend.currentTime = 5
        controller.pause()

        controller.play()

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(backend.playCallCount, 2)
        XCTAssertEqual(backend.stopCallCount, 0, "reprendre n'est pas repartir de zéro")
    }

    func testTickUpdatesCurrentTimeWhilePlaying() async throws {
        let (controller, backend) = makeController()
        controller.play()
        backend.currentTime = 1.5

        // Deux ticks (100 ms) suffisent pour rafraîchir la position.
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(controller.currentTime, 1.5)
    }

    // MARK: Fin de lecture

    func testNaturalFinishResetsToIdleAtZero() {
        let (controller, backend) = makeController()
        controller.play()
        backend.currentTime = 9.9

        backend.finishNaturally()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.currentTime, 0, "prêt à réécouter depuis le début")
        XCTAssertEqual(controller.progress, 0)
    }

    func testReplayAfterFinishStartsAgain() {
        let (controller, backend) = makeController()
        controller.play()
        backend.finishNaturally()

        controller.play()

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(backend.playCallCount, 2)
    }

    // MARK: Stop (dismiss de la vue)

    func testStopResetsEverything() {
        let (controller, backend) = makeController()
        controller.play()
        backend.currentTime = 4

        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertEqual(backend.stopCallCount, 1)
    }

    // MARK: Exclusivité — un seul lecteur actif

    func testStartingSecondPlayerStopsTheFirst() {
        let (first, firstBackend) = makeController()
        let (second, _) = makeController(backend: MockBackend())

        first.play()
        XCTAssertEqual(first.state, .playing)

        second.play()

        XCTAssertEqual(second.state, .playing)
        XCTAssertEqual(first.state, .idle, "le lecteur précédent s'arrête")
        XCTAssertEqual(firstBackend.stopCallCount, 1)

        second.stop() // nettoyage du lecteur actif statique
    }

    // MARK: Fichier illisible

    func testUnreadableFileMarksUnavailableWithoutCrash() {
        struct Unreadable: Error {}
        let controller = AudioPlayerController(
            url: URL(fileURLWithPath: "/tmp/absent.wav"),
            makeBackend: { _ in throw Unreadable() }
        )

        controller.play()

        XCTAssertTrue(controller.unavailable)
        XCTAssertEqual(controller.state, .idle)

        // Les commandes suivantes restent inertes, pas de nouvel essai bruyant.
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Backend réel — un WAV conservé se charge dans AVAudioPlayer

    func testAVBackendLoadsStoredWav() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-player-av-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionAudioStore(directory: directory)
        let samples: [Float] = (0..<16_000).map { 0.3 * sin(2 * .pi * 440 * Float($0) / 16_000) }
        let url = try store.write(samples: samples)

        let backend = try AVAudioPlayerBackend(url: url)

        XCTAssertEqual(backend.duration, 1.0, accuracy: 0.05, "1 s d'audio à 16 kHz")
        XCTAssertEqual(backend.currentTime, 0)
    }
}
