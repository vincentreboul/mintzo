import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Raccourci de dictée configurable (l'app expose `KeyboardShortcuts.Recorder`
    /// sur ce nom dans ses réglages). Défaut : ⌥Espace.
    public static let dictation = Self("dictation", initial: .init(.space, modifiers: [.option]))
}

/// Source des transitions du raccourci configurable — protocole pour injecter
/// un mock dans les tests, KeyboardShortcuts (Carbon, zéro permission) en réel.
@MainActor
public protocol ShortcutEventSource {
    func events() -> AsyncStream<KeyTransition>
}

/// Source des transitions de la touche Fn — protocole pour injecter un mock,
/// CGEventTap (`FnKeyMonitor`) en réel. `start()` rend `nil` si indisponible.
@MainActor
public protocol FnKeyEventSource {
    func start() -> AsyncStream<FnKeyTransition>?
    func stop()
}

/// Implémentation réelle du raccourci via KeyboardShortcuts v3
/// (module isolé MainActor ; `events(for:)` gère l'enregistrement Carbon).
public struct KeyboardShortcutsEventSource: ShortcutEventSource {
    private let name: KeyboardShortcuts.Name

    public init(name: KeyboardShortcuts.Name = .dictation) {
        self.name = name
    }

    public func events() -> AsyncStream<KeyTransition> {
        let (stream, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
        let name = self.name
        let pump = Task { @MainActor in
            for await event in KeyboardShortcuts.events(for: name) {
                continuation.yield(event == .keyDown ? .down : .up)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }
}

/// Hotkey global de dictée — deux modes cumulables :
///
/// (a) **Raccourci configurable** (KeyboardShortcuts, défaut ⌥Espace, aucune
///     permission) : push-to-talk OU toggle selon `Configuration.activationMode`.
/// (b) **Touche Fn maintenue** (CGEventTap, exige Accessibility) :
///     maintien ≥ 150 ms = push-to-talk, tap bref ignoré. Si la permission
///     manque ou le tap échoue → mode (a) seul, `isFnMonitorActive == false`,
///     jamais de crash.
///
/// `start()` fusionne les deux sources en un seul `AsyncStream<HotkeyEvent>`
/// (`.pressBegan` / `.pressEnded` / `.toggled`). Les machines d'état sont
/// pures (`HotkeyMachines.swift`) et testées par événements injectés.
@MainActor
public final class HotkeyService {

    public struct Configuration: Sendable {
        /// Comportement du raccourci configurable (le mode Fn est toujours push-to-talk).
        public var activationMode: ActivationMode
        /// Active le mode « touche Fn maintenue » (si Accessibility disponible).
        public var fnKeyEnabled: Bool
        /// Seuil de maintien de la touche Fn (150 ms par défaut).
        public var fnHoldThreshold: TimeInterval

        public init(
            activationMode: ActivationMode = .pushToTalk,
            fnKeyEnabled: Bool = true,
            fnHoldThreshold: TimeInterval = 0.15
        ) {
            self.activationMode = activationMode
            self.fnKeyEnabled = fnKeyEnabled
            self.fnHoldThreshold = fnHoldThreshold
        }
    }

    /// Le monitoring Fn est-il effectivement actif ? (`false` = Accessibility
    /// manquante ou tap refusé — l'écran santé des permissions s'appuie dessus.)
    public private(set) var isFnMonitorActive = false

    /// Identifiant du raccourci de dictée (stockage UserDefaults de
    /// KeyboardShortcuts). Exposé pour les couches qui ne linkent pas le
    /// package (tests, diagnostics).
    public static var dictationShortcutID: String {
        KeyboardShortcuts.Name.dictation.rawValue
    }

    /// Un raccourci par défaut (⌥Espace) est-il déclaré pour la dictée ?
    public static var dictationHasDefaultShortcut: Bool {
        KeyboardShortcuts.Name.dictation.initialShortcut != nil
    }

    private let shortcutSource: any ShortcutEventSource
    private let fnSource: any FnKeyEventSource
    private var pumpTasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    public init(
        shortcutSource: any ShortcutEventSource = KeyboardShortcutsEventSource(),
        fnSource: any FnKeyEventSource = FnKeyMonitor()
    ) {
        self.shortcutSource = shortcutSource
        self.fnSource = fnSource
    }

    /// Démarre l'écoute des deux modes et rend le flux fusionné d'événements.
    /// Rappeler `start()` remplace la session précédente (stop implicite).
    public func start(configuration: Configuration = Configuration()) -> AsyncStream<HotkeyEvent> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        self.continuation = continuation

        startShortcutPump(mode: configuration.activationMode, into: continuation)
        if configuration.fnKeyEnabled {
            startFnPump(holdThreshold: configuration.fnHoldThreshold, into: continuation)
        }
        return stream
    }

    public func stop() {
        for task in pumpTasks { task.cancel() }
        pumpTasks = []
        fnSource.stop()
        isFnMonitorActive = false
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Pompes

    private func startShortcutPump(
        mode: ActivationMode,
        into continuation: AsyncStream<HotkeyEvent>.Continuation
    ) {
        let transitions = shortcutSource.events()
        pumpTasks.append(Task { @MainActor in
            var machine = ShortcutActivationMachine(mode: mode)
            for await transition in transitions {
                if let event = machine.process(transition) {
                    continuation.yield(event)
                }
            }
        })
    }

    private func startFnPump(
        holdThreshold: TimeInterval,
        into continuation: AsyncStream<HotkeyEvent>.Continuation
    ) {
        guard let fnTransitions = fnSource.start() else {
            isFnMonitorActive = false
            return
        }
        isFnMonitorActive = true

        // Les transitions du tap ET les échéances de timer passent par le
        // MÊME flux d'inputs : la machine est consommée par une seule boucle,
        // donc strictement sérialisée et ordonnée (FIFO d'AsyncStream).
        let (inputs, inputContinuation) = AsyncStream.makeStream(of: FnHoldMachine.Input.self)

        pumpTasks.append(Task { @MainActor in
            for await transition in fnTransitions {
                switch transition {
                case .down(let at): inputContinuation.yield(.fnDown(at: at))
                case .up(let at): inputContinuation.yield(.fnUp(at: at))
                }
            }
            inputContinuation.finish()
        })

        pumpTasks.append(Task { @MainActor in
            var machine = FnHoldMachine(holdThreshold: holdThreshold)
            for await input in inputs {
                for effect in machine.process(input) {
                    switch effect {
                    case .emit(let event):
                        continuation.yield(event)
                    case .scheduleHoldTimer(let id, let after):
                        // Timer hors machine : s'il devient périmé (tap bref,
                        // nouvel appui), la machine l'ignore par identifiant.
                        Task {
                            try? await Task.sleep(for: .seconds(after))
                            guard !Task.isCancelled else { return }
                            inputContinuation.yield(.holdTimerFired(id: id))
                        }
                    }
                }
            }
        })
    }
}
