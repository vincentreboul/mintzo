import XCTest
@testable import MintzoCore

/// Tests d'attaque QA indépendants du raccourci de bascule de langue (§4.4).
///
/// Cible le cycle d'états de `LanguageCycleHotkey` sous séquences dégradées :
/// double `start()`, restart après `stop()`, rafales de `.down` sans `.up`,
/// `stop()` avec événements en vol, source qui se termine, rétention mémoire.
/// Attaque aussi le double-`start()` de `HotkeyService` (dictée), non couvert
/// par la suite existante — un mock à continuation unique ne PEUT PAS prouver
/// l'absence de double pompe : celui-ci conserve toutes les sessions créées.
@MainActor
final class LanguageCycleHotkeyAttackTests: XCTestCase {

    // MARK: - Doubles

    /// Conserve TOUTES les continuations créées — indispensable pour yielder
    /// sur une session REMPLACÉE et prouver qu'elle est bien morte.
    private final class MultiSessionSource: ShortcutEventSource {
        private(set) var continuations: [AsyncStream<KeyTransition>.Continuation] = []

        func events() -> AsyncStream<KeyTransition> {
            let (stream, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
            continuations.append(continuation)
            return stream
        }
    }

    @MainActor
    private final class Counter {
        private(set) var count = 0
        func increment() { count += 1 }

        func waitForCount(_ target: Int, timeout: TimeInterval = 2) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while count < target, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return count >= target
        }

        /// Vrai si le compteur reste EXACTEMENT à `value` pendant `window` —
        /// détecte les déclenchements tardifs/parasites, pas seulement absents.
        func staysAt(_ value: Int, window: TimeInterval = 0.15) async -> Bool {
            let deadline = Date().addingTimeInterval(window)
            while Date() < deadline {
                if count != value { return false }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return count == value
        }
    }

    @MainActor
    private final class EventCollector {
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

    // MARK: - Double start : jamais deux pompes

    func testDoubleStartKeepsSingleActivePump() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }
        hotkey.start { counter.increment() }  // doit REMPLACER, pas cumuler
        defer { hotkey.stop() }

        XCTAssertEqual(source.continuations.count, 2, "deux sessions doivent avoir été ouvertes")

        // Un appui sur la session ACTIVE (la 2e) = exactement UN cran.
        source.continuations[1].yield(.down)
        let one = await counter.waitForCount(1)
        XCTAssertTrue(one, "l'appui sur la session active doit cycler")
        let exactlyOne = await counter.staysAt(1)
        XCTAssertTrue(exactlyOne,
                      "double start ⇒ double pompe ? \(counter.count) cran(s) pour 1 appui")

        // La session REMPLACÉE est morte : un appui dessus ne fait RIEN.
        source.continuations[0].yield(.down)
        let silent = await counter.staysAt(1)
        XCTAssertTrue(silent,
                      "la pompe remplacée par le 2e start() a re-déclenché (count=\(counter.count))")
    }

    func testStartStopStartUsesOnlyFreshSession() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()

        hotkey.start { counter.increment() }
        hotkey.stop()
        hotkey.start { counter.increment() }
        defer { hotkey.stop() }

        XCTAssertEqual(source.continuations.count, 2)

        // L'ancienne session (stoppée) ne déclenche plus.
        source.continuations[0].yield(.down)
        let deadOld = await counter.staysAt(0)
        XCTAssertTrue(deadOld, "la session stoppée a déclenché après stop() → start()")

        // La nouvelle fonctionne normalement.
        source.continuations[1].yield(.down)
        let one = await counter.waitForCount(1)
        XCTAssertTrue(one, "après restart, la nouvelle session doit cycler")
        let stable = await counter.staysAt(1)
        XCTAssertTrue(stable)
    }

    // MARK: - Rafales / séquences dégradées

    func testBurstOfDownsWithoutUpsCyclesOncePerDown() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }
        defer { hotkey.stop() }

        // 3 .down consécutifs sans .up : contrat = un cran PAR .down (Carbon
        // n'auto-répète pas les hotkeys ; chaque .down délivré est un appui).
        source.continuations[0].yield(.down)
        source.continuations[0].yield(.down)
        source.continuations[0].yield(.down)

        let three = await counter.waitForCount(3)
        XCTAssertTrue(three, "3 appuis = 3 crans, reçu \(counter.count)")
        let noExtra = await counter.staysAt(3)
        XCTAssertTrue(noExtra, "crans parasites au-delà des 3 appuis (count=\(counter.count))")
    }

    func testUpStormAloneNeverCycles() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }
        defer { hotkey.stop() }

        for _ in 0..<5 { source.continuations[0].yield(.up) }

        let silent = await counter.staysAt(0, window: 0.2)
        XCTAssertTrue(silent, "une rafale de .up seuls a déclenché \(counter.count) cran(s)")
    }

    func testInterleavedRapidPressesCountExactly() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }
        defer { hotkey.stop() }

        for _ in 0..<3 {
            source.continuations[0].yield(.down)
            source.continuations[0].yield(.up)
        }

        let three = await counter.waitForCount(3)
        XCTAssertTrue(three, "3 appuis complets = 3 crans, reçu \(counter.count)")
        let exact = await counter.staysAt(3)
        XCTAssertTrue(exact, "sur-comptage après la rafale (count=\(counter.count))")
    }

    // MARK: - Stop avec événements en vol

    func testStopInSameTurnAsBurstNeverFiresLate() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }

        // Rafale puis stop() dans le MÊME tour MainActor : la pompe (Task
        // MainActor) n'a pas pu s'exécuter entre les deux — elle est annulée
        // avant sa première itération. AUCUN cran ne doit partir, ni
        // immédiatement, ni en retard.
        for _ in 0..<5 { source.continuations[0].yield(.down) }
        hotkey.stop()

        let silent = await counter.staysAt(0, window: 0.25)
        XCTAssertTrue(silent,
                      "événements en vol exécutés APRÈS stop() : \(counter.count) cran(s) tardifs")
    }

    // MARK: - Source qui se termine

    func testSourceFinishLeavesCounterStableAndStopSafe() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()
        hotkey.start { counter.increment() }

        source.continuations[0].yield(.down)
        let one = await counter.waitForCount(1)
        XCTAssertTrue(one)

        // La source se termine (ex. désenregistrement du raccourci côté lib).
        source.continuations[0].finish()
        // Yield post-finish : no-op par contrat AsyncStream — rien ne doit bouger.
        source.continuations[0].yield(.down)

        let stable = await counter.staysAt(1, window: 0.2)
        XCTAssertTrue(stable, "cran après la fin de la source (count=\(counter.count))")

        // stop() après une source déjà terminée : pas de crash, toujours stable.
        hotkey.stop()
        let still = await counter.staysAt(1)
        XCTAssertTrue(still)
    }

    // MARK: - Idempotence stop / redémarrage

    func testStopWithoutStartAndDoubleStopAreSafe() async {
        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)
        let counter = Counter()

        hotkey.stop()  // stop sans start : no-op
        hotkey.stop()

        hotkey.start { counter.increment() }
        source.continuations[0].yield(.down)
        let one = await counter.waitForCount(1)
        XCTAssertTrue(one, "après des stop() à vide, start() doit fonctionner normalement")

        hotkey.stop()
        hotkey.stop()  // double stop : no-op
        let silent = await counter.staysAt(1)
        XCTAssertTrue(silent)
    }

    // MARK: - Rétention mémoire

    func testStopReleasesCallbackCaptures() async {
        final class Token {}

        let source = MultiSessionSource()
        let hotkey = LanguageCycleHotkey(source: source)

        var token: Token? = Token()
        weak var weakToken = token
        hotkey.start { [token] in _ = token }
        token = nil

        XCTAssertNotNil(weakToken, "la pompe active doit retenir la closure")

        hotkey.stop()

        // La Task annulée libère ses captures de façon asynchrone : polling court.
        let deadline = Date().addingTimeInterval(2)
        while weakToken != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(weakToken,
                     "après stop(), la closure onCycle doit être libérée — fuite de Task/callback")
    }

    // MARK: - Identité des raccourcis (anti copier-coller)

    func testLanguageCycleIdentityDistinctFromDictation() {
        XCTAssertEqual(LanguageCycleHotkey.shortcutID, "languageCycle")
        XCTAssertNotEqual(LanguageCycleHotkey.shortcutID, HotkeyService.dictationShortcutID,
                          "le raccourci de langue partage l'identifiant de la dictée")
        XCTAssertTrue(LanguageCycleHotkey.hasDefaultShortcut)
        XCTAssertEqual(LanguageCycleHotkey.defaultShortcutDescription, "⌃⌥L",
                       "défaut ⌃⌥L (§4.4) — et distinct du ⌥Espace de la dictée")
    }

    // MARK: - HotkeyService : double start (voie dictée, trou de la suite existante)

    func testHotkeyServiceDoubleStartKeepsSingleShortcutPump() async {
        let source = MultiSessionSource()
        let service = HotkeyService(shortcutSource: source)
        let first = EventCollector()
        let second = EventCollector()

        first.attach(service.start(configuration: .init(activationMode: .pushToTalk)))
        second.attach(service.start(configuration: .init(activationMode: .pushToTalk)))
        defer {
            service.stop()
            first.cancel()
            second.cancel()
        }

        XCTAssertEqual(source.continuations.count, 2)

        // Appui complet sur la session ACTIVE : exactement une paire began/ended.
        source.continuations[1].yield(.down)
        source.continuations[1].yield(.up)
        let pair = await second.waitForCount(2)
        XCTAssertTrue(pair, "began/ended attendus sur le flux actif, reçu \(second.events)")
        XCTAssertEqual(second.events, [.pressBegan, .pressEnded])

        // La session remplacée ne délivre plus rien (flux fini par le restart).
        source.continuations[0].yield(.down)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(second.events, [.pressBegan, .pressEnded],
                       "événements parasites après restart : \(second.events)")
        XCTAssertTrue(first.events.isEmpty,
                      "le flux du 1er start() (fini par le restart) a délivré : \(first.events)")
    }
}
