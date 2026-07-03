import XCTest
@testable import MintzoCore

/// Tests du PermissionsService avec sondes injectées — aucun accès TCC réel.
@MainActor
final class SystemPermissionsTests: XCTestCase {

    /// Sonde mutable thread-safe (les probes sont des closures @Sendable).
    private final class ProbeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var mic: PermissionStatus
        private var ax: Bool

        init(mic: PermissionStatus, ax: Bool) {
            self.mic = mic
            self.ax = ax
        }

        var microphone: PermissionStatus {
            get { lock.withLock { mic } }
            set { lock.withLock { mic = newValue } }
        }

        var accessibility: Bool {
            get { lock.withLock { ax } }
            set { lock.withLock { ax = newValue } }
        }

        var probes: PermissionProbes {
            PermissionProbes(
                microphoneStatus: { [weak self] in self?.microphone ?? .denied },
                accessibilityTrusted: { [weak self] in self?.accessibility ?? false }
            )
        }
    }

    func testSnapshotMapsProbes() {
        let box = ProbeBox(mic: .notDetermined, ax: false)
        let service = PermissionsService(probes: box.probes)

        var snapshot = service.snapshot()
        XCTAssertEqual(snapshot.microphone, .notDetermined)
        XCTAssertEqual(snapshot.accessibility, .denied)
        XCTAssertFalse(snapshot.allGranted)

        box.microphone = .granted
        box.accessibility = true
        snapshot = service.snapshot()
        XCTAssertEqual(snapshot.microphone, .granted)
        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertTrue(snapshot.allGranted)
    }

    func testChangesStreamYieldsInitialThenOnlyChanges() async {
        let box = ProbeBox(mic: .denied, ax: false)
        // Intervalle court : le test reste rapide.
        let service = PermissionsService(probes: box.probes, pollInterval: .milliseconds(25))

        let collected = CollectedSnapshots()
        let stream = service.changes()
        let pump = Task { @MainActor in
            for await snapshot in stream {
                collected.append(snapshot)
            }
        }
        defer { pump.cancel() }

        // 1. État initial publié immédiatement.
        var ok = await collected.waitForCount(1)
        XCTAssertTrue(ok, "l'état initial doit être publié")
        XCTAssertEqual(collected.snapshots.first,
                       PermissionsSnapshot(microphone: .denied, accessibility: .denied))

        // 2. Pas de changement → pas de publication (on laisse plusieurs polls passer).
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(collected.snapshots.count, 1,
                       "sans changement, le flux ne doit rien republier")

        // 3. La permission micro arrive → publication du nouvel état.
        box.microphone = .granted
        ok = await collected.waitForCount(2)
        XCTAssertTrue(ok, "le changement micro doit être détecté par le polling")
        XCTAssertEqual(collected.snapshots.last?.microphone, .granted)

        // 4. Révocation détectée aussi quand tout était accordé (poll ralenti ×5).
        box.accessibility = true
        ok = await collected.waitForCount(3)
        XCTAssertTrue(ok)
        XCTAssertTrue(collected.snapshots.last?.allGranted ?? false)

        box.accessibility = false
        ok = await collected.waitForCount(4, timeout: 3)
        XCTAssertTrue(ok, "une révocation doit être détectée même après allGranted")
        XCTAssertEqual(collected.snapshots.last?.accessibility, .denied)
    }

    func testChangesStreamStopsWhenConsumerCancels() async {
        let box = ProbeBox(mic: .denied, ax: false)
        let service = PermissionsService(probes: box.probes, pollInterval: .milliseconds(20))

        let collected = CollectedSnapshots()
        let pump = Task { @MainActor in
            for await snapshot in service.changes() {
                collected.append(snapshot)
            }
        }
        _ = await collected.waitForCount(1)
        pump.cancel()
        // Laisse le temps à l'annulation de se propager.
        try? await Task.sleep(for: .milliseconds(80))

        let countAfterCancel = collected.snapshots.count
        box.microphone = .granted
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(collected.snapshots.count, countAfterCancel,
                       "après annulation, plus aucune publication")
    }
}

/// Accumulateur MainActor pour les flux de snapshots.
@MainActor
private final class CollectedSnapshots {
    private(set) var snapshots: [PermissionsSnapshot] = []

    func append(_ snapshot: PermissionsSnapshot) {
        snapshots.append(snapshot)
    }

    func waitForCount(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while snapshots.count < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return snapshots.count >= count
    }
}
