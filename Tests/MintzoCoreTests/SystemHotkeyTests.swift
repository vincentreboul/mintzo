import XCTest
@testable import MintzoCore

/// Tests de la machinerie hotkey par événements injectés — les vrais
/// CGEventTap / KeyboardShortcuts restent derrière les protocoles
/// `FnKeyEventSource` / `ShortcutEventSource`, mockés ici (aucune permission).
@MainActor
final class SystemHotkeyTests: XCTestCase {

    // MARK: - ShortcutActivationMachine (mode a)

    func testPushToTalkMapsDownUpToBeganEnded() {
        var machine = ShortcutActivationMachine(mode: .pushToTalk)
        XCTAssertEqual(machine.process(.down), .pressBegan)
        XCTAssertEqual(machine.process(.up), .pressEnded)
        XCTAssertEqual(machine.process(.down), .pressBegan)
        XCTAssertEqual(machine.process(.up), .pressEnded)
    }

    func testPushToTalkDeduplicatesRepeats() {
        var machine = ShortcutActivationMachine(mode: .pushToTalk)
        XCTAssertEqual(machine.process(.down), .pressBegan)
        XCTAssertNil(machine.process(.down), "auto-repeat keyDown ignoré")
        XCTAssertEqual(machine.process(.up), .pressEnded)
        XCTAssertNil(machine.process(.up), "keyUp orphelin ignoré")
    }

    func testToggleEmitsOnDownOnly() {
        var machine = ShortcutActivationMachine(mode: .toggle)
        XCTAssertEqual(machine.process(.down), .toggled)
        XCTAssertNil(machine.process(.up))
        XCTAssertEqual(machine.process(.down), .toggled)
        XCTAssertNil(machine.process(.up))
    }

    // MARK: - FnHoldMachine (mode b) : hold / tap bref / debounce

    func testFnHoldCrossesThresholdThenEnds() {
        var machine = FnHoldMachine(holdThreshold: 0.15)
        let effects = machine.process(.fnDown(at: 10.0))
        guard case .scheduleHoldTimer(let id, let after)? = effects.first else {
            return XCTFail("fnDown doit planifier le timer de seuil, reçu \(effects)")
        }
        XCTAssertEqual(after, 0.15)
        XCTAssertEqual(machine.process(.holdTimerFired(id: id)), [.emit(.pressBegan)])
        XCTAssertEqual(machine.process(.fnUp(at: 11.0)), [.emit(.pressEnded)])
    }

    func testFnBriefTapIsIgnored() {
        var machine = FnHoldMachine(holdThreshold: 0.15)
        let effects = machine.process(.fnDown(at: 10.0))
        guard case .scheduleHoldTimer(let id, _)? = effects.first else {
            return XCTFail("timer attendu")
        }
        // Relâchement avant le seuil : aucun événement.
        XCTAssertEqual(machine.process(.fnUp(at: 10.05)), [])
        // Le timer périmé arrive quand même : neutralisé par identifiant.
        XCTAssertEqual(machine.process(.holdTimerFired(id: id)), [],
                       "un timer d'un appui terminé ne doit JAMAIS déclencher")
    }

    func testFnDuplicateFlagsChangedAreDeduplicated() {
        var machine = FnHoldMachine(holdThreshold: 0.15)
        XCTAssertEqual(machine.process(.fnDown(at: 10.0)).count, 1)
        // flagsChanged dupliqués pour le même appui perçu.
        XCTAssertEqual(machine.process(.fnDown(at: 10.01)), [])
        XCTAssertEqual(machine.process(.fnDown(at: 10.02)), [])
        // Up orphelin après up.
        _ = machine.process(.fnUp(at: 10.3))
        XCTAssertEqual(machine.process(.fnUp(at: 10.31)), [])
    }

    func testFnReengageBounceIsAbsorbed() {
        var machine = FnHoldMachine(holdThreshold: 0.15, reengageDebounce: 0.05)
        let effects = machine.process(.fnDown(at: 10.0))
        guard case .scheduleHoldTimer(let id, _)? = effects.first else { return XCTFail() }
        _ = machine.process(.holdTimerFired(id: id))
        XCTAssertEqual(machine.process(.fnUp(at: 10.5)), [.emit(.pressEnded)])
        // Rebond < 50 ms après le relâchement : absorbé.
        XCTAssertEqual(machine.process(.fnDown(at: 10.52)), [])
        // Ré-appui légitime après le debounce : nouveau cycle.
        XCTAssertEqual(machine.process(.fnDown(at: 10.7)).count, 1)
    }

    func testFnStaleTimerFromPreviousPressDoesNotFirePress() {
        var machine = FnHoldMachine(holdThreshold: 0.15)
        guard case .scheduleHoldTimer(let firstID, _)? = machine.process(.fnDown(at: 1.0)).first
        else { return XCTFail() }
        _ = machine.process(.fnUp(at: 1.05))  // tap bref
        guard case .scheduleHoldTimer(let secondID, _)? = machine.process(.fnDown(at: 2.0)).first
        else { return XCTFail() }
        XCTAssertNotEqual(firstID, secondID)
        // Le timer du PREMIER appui expire pendant le second : ignoré.
        XCTAssertEqual(machine.process(.holdTimerFired(id: firstID)), [])
        // Celui du second déclenche.
        XCTAssertEqual(machine.process(.holdTimerFired(id: secondID)), [.emit(.pressBegan)])
    }

    // MARK: - Doubles pour le service

    private final class MockShortcutSource: ShortcutEventSource {
        private(set) var continuation: AsyncStream<KeyTransition>.Continuation?
        func events() -> AsyncStream<KeyTransition> {
            let (stream, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
            self.continuation = continuation
            return stream
        }
    }

    private final class MockFnSource: FnKeyEventSource {
        var available = true
        private(set) var continuation: AsyncStream<FnKeyTransition>.Continuation?
        private(set) var stopCount = 0

        func start() -> AsyncStream<FnKeyTransition>? {
            guard available else { return nil }
            let (stream, continuation) = AsyncStream.makeStream(of: FnKeyTransition.self)
            self.continuation = continuation
            return stream
        }

        func stop() {
            stopCount += 1
            continuation?.finish()
        }
    }

    /// Collecte le flux du service ; les tests attendent par polling court
    /// (pas de `next()` bloquant → jamais de suite suspendue).
    @MainActor
    private final class Collector {
        private(set) var events: [HotkeyEvent] = []
        private var task: Task<Void, Never>?

        func attach(_ stream: AsyncStream<HotkeyEvent>) {
            task = Task { @MainActor in
                for await event in stream {
                    self.events.append(event)
                }
            }
        }

        func waitForCount(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while events.count < count, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return events.count >= count
        }

        func cancel() { task?.cancel() }
    }

    // MARK: - Service : câblage bout-en-bout par événements injectés

    func testServicePushToTalkEmitsBeganEnded() async {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        fn.available = false
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        let collector = Collector()
        collector.attach(service.start(configuration: .init(activationMode: .pushToTalk)))
        defer { service.stop(); collector.cancel() }

        shortcut.continuation?.yield(.down)
        shortcut.continuation?.yield(.up)

        let ok = await collector.waitForCount(2)
        XCTAssertTrue(ok, "attendu 2 événements, reçu \(collector.events)")
        XCTAssertEqual(collector.events, [.pressBegan, .pressEnded])
    }

    func testServiceToggleModeEmitsToggled() async {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        fn.available = false
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        let collector = Collector()
        collector.attach(service.start(configuration: .init(activationMode: .toggle)))
        defer { service.stop(); collector.cancel() }

        shortcut.continuation?.yield(.down)
        shortcut.continuation?.yield(.up)
        shortcut.continuation?.yield(.down)

        let ok = await collector.waitForCount(2)
        XCTAssertTrue(ok, "attendu 2 événements, reçu \(collector.events)")
        XCTAssertEqual(collector.events, [.toggled, .toggled])
    }

    func testServiceFnHoldEmitsPushToTalkAfterThreshold() async {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        let collector = Collector()
        // Seuil court pour un test rapide mais non-flaky.
        collector.attach(service.start(configuration: .init(fnHoldThreshold: 0.05)))
        defer { service.stop(); collector.cancel() }

        XCTAssertTrue(service.isFnMonitorActive)
        let now = Date().timeIntervalSinceReferenceDate
        fn.continuation?.yield(.down(at: now))

        // Le pressBegan arrive au franchissement du seuil (~50 ms), AVANT le relâchement.
        let began = await collector.waitForCount(1)
        XCTAssertTrue(began, "pressBegan attendu après le seuil de maintien")
        XCTAssertEqual(collector.events.first, .pressBegan)

        fn.continuation?.yield(.up(at: now + 0.5))
        let ended = await collector.waitForCount(2)
        XCTAssertTrue(ended)
        XCTAssertEqual(collector.events, [.pressBegan, .pressEnded])
    }

    func testServiceFnBriefTapEmitsNothing() async {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        let collector = Collector()
        collector.attach(service.start(configuration: .init(fnHoldThreshold: 0.05)))
        defer { service.stop(); collector.cancel() }

        let now = Date().timeIntervalSinceReferenceDate
        fn.continuation?.yield(.down(at: now))
        fn.continuation?.yield(.up(at: now + 0.01))  // tap bref, sous le seuil

        // Laisse largement passer le seuil : rien ne doit sortir.
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(collector.events.isEmpty,
                      "un tap bref ne doit rien émettre, reçu \(collector.events)")
    }

    func testServiceWithoutAccessibilityFallsBackToShortcutOnly() async {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        fn.available = false  // Accessibility absente → source Fn indisponible
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        let collector = Collector()
        collector.attach(service.start())
        defer { service.stop(); collector.cancel() }

        XCTAssertFalse(service.isFnMonitorActive,
                       "sans Accessibility, le monitor Fn doit se déclarer inactif")

        // Le raccourci configurable reste pleinement fonctionnel.
        shortcut.continuation?.yield(.down)
        shortcut.continuation?.yield(.up)
        let ok = await collector.waitForCount(2)
        XCTAssertTrue(ok)
        XCTAssertEqual(collector.events, [.pressBegan, .pressEnded])
    }

    func testServiceStopTearsDownFnSource() {
        let shortcut = MockShortcutSource()
        let fn = MockFnSource()
        let service = HotkeyService(shortcutSource: shortcut, fnSource: fn)
        _ = service.start()
        XCTAssertTrue(service.isFnMonitorActive)

        service.stop()

        XCTAssertFalse(service.isFnMonitorActive)
        XCTAssertGreaterThanOrEqual(fn.stopCount, 1, "stop() doit arrêter le tap Fn")
    }

    // MARK: - Nom du raccourci

    func testDictationShortcutNameAndDefault() {
        // Via les accesseurs MintzoCore : le module de test ne linke pas
        // KeyboardShortcuts directement.
        XCTAssertEqual(HotkeyService.dictationShortcutID, "dictation")
        XCTAssertTrue(HotkeyService.dictationHasDefaultShortcut,
                      "le raccourci par défaut (option+espace) doit être déclaré")
    }
}
