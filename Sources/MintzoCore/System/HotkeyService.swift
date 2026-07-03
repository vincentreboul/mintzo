import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Raccourci de dictée configurable (l'app expose `KeyboardShortcuts.Recorder`
    /// sur ce nom dans ses réglages). Défaut : ⌥Espace.
    public static let dictation = Self("dictation", initial: .init(.space, modifiers: [.option]))

    /// Raccourci global de bascule de langue (§4.4) : cycle eu → fr → auto,
    /// y compris pendant l'écoute. Configurable dans les réglages. Défaut : ⌃⌥L.
    public static let languageCycle = Self("languageCycle", initial: .init(.l, modifiers: [.control, .option]))
}

/// Source des transitions du raccourci configurable — protocole pour injecter
/// un mock dans les tests, KeyboardShortcuts (Carbon, zéro permission) en réel.
@MainActor
public protocol ShortcutEventSource {
    func events() -> AsyncStream<KeyTransition>
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

/// Hotkey global de dictée — **raccourci configurable** (KeyboardShortcuts,
/// défaut ⌥Espace, aucune permission système) : toggle (défaut — appui simple,
/// anti-rebond 300 ms) OU push-to-talk selon `Configuration.activationMode`.
///
/// `start()` rend un `AsyncStream<HotkeyEvent>` (`.pressBegan` / `.pressEnded`
/// / `.toggled`). La machine d'état est pure (`HotkeyMachines.swift`) et testée
/// par événements injectés.
@MainActor
public final class HotkeyService {

    public struct Configuration: Sendable {
        /// Comportement du raccourci configurable. Défaut : `.toggle` — appui
        /// simple, comme SuperWhisper (préférence explicite du retour client).
        public var activationMode: ActivationMode
        /// Anti-rebond du mode toggle : un ré-appui < 300 ms après le dernier
        /// toggle est ignoré. Exposé pour les tests.
        public var toggleDebounce: TimeInterval

        public init(
            activationMode: ActivationMode = .toggle,
            toggleDebounce: TimeInterval = 0.3
        ) {
            self.activationMode = activationMode
            self.toggleDebounce = toggleDebounce
        }
    }

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
    private var pumpTasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    public init(
        shortcutSource: any ShortcutEventSource = KeyboardShortcutsEventSource()
    ) {
        self.shortcutSource = shortcutSource
    }

    /// Démarre l'écoute du raccourci et rend le flux d'événements.
    /// Rappeler `start()` remplace la session précédente (stop implicite).
    public func start(configuration: Configuration = Configuration()) -> AsyncStream<HotkeyEvent> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        self.continuation = continuation

        startShortcutPump(
            mode: configuration.activationMode,
            toggleDebounce: configuration.toggleDebounce,
            into: continuation
        )
        return stream
    }

    public func stop() {
        for task in pumpTasks { task.cancel() }
        pumpTasks = []
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Pompes

    private func startShortcutPump(
        mode: ActivationMode,
        toggleDebounce: TimeInterval,
        into continuation: AsyncStream<HotkeyEvent>.Continuation
    ) {
        let transitions = shortcutSource.events()
        pumpTasks.append(Task { @MainActor in
            var machine = ShortcutActivationMachine(mode: mode, toggleDebounce: toggleDebounce)
            for await transition in transitions {
                // Horloge CFAbsoluteTime — le timestamp sert uniquement à
                // l'anti-rebond du mode toggle.
                if let event = machine.process(transition, at: CFAbsoluteTimeGetCurrent()) {
                    continuation.yield(event)
                }
            }
        })
    }
}

/// Raccourci global de bascule de langue (§4.4) — cycle eu → fr → auto,
/// y compris pendant l'écoute. Écoute `.languageCycle` (KeyboardShortcuts,
/// zéro permission) et déclenche `onCycle` à chaque appui (`.down`) ;
/// le relâchement est ignoré. La logique de cycle reste chez l'appelant
/// (`HUDLanguage.next`), ce service ne fait que pomper le raccourci.
@MainActor
public final class LanguageCycleHotkey {

    /// Identifiant du raccourci de langue (stockage UserDefaults de
    /// KeyboardShortcuts). Exposé pour les couches qui ne linkent pas le
    /// package (tests, diagnostics).
    public static var shortcutID: String {
        KeyboardShortcuts.Name.languageCycle.rawValue
    }

    /// Un raccourci par défaut (⌃⌥L) est-il déclaré pour la bascule de langue ?
    public static var hasDefaultShortcut: Bool {
        KeyboardShortcuts.Name.languageCycle.initialShortcut != nil
    }

    /// Description native du raccourci par défaut (« ⌃⌥L ») — tests, tooltips.
    public static var defaultShortcutDescription: String? {
        KeyboardShortcuts.Name.languageCycle.initialShortcut?.description
    }

    private let source: any ShortcutEventSource
    private var pumpTask: Task<Void, Never>?

    public init(source: any ShortcutEventSource = KeyboardShortcutsEventSource(name: .languageCycle)) {
        self.source = source
    }

    /// Démarre l'écoute — chaque appui du raccourci appelle `onCycle`.
    /// Rappeler `start(onCycle:)` remplace la pompe précédente (stop implicite).
    public func start(onCycle: @escaping @MainActor () -> Void) {
        stop()
        let transitions = source.events()
        pumpTask = Task { @MainActor in
            for await transition in transitions where transition == .down {
                // `AsyncStream` draine son buffer même après `cancel()` : sans ce
                // garde, des appuis déjà en file déclencheraient après `stop()`.
                guard !Task.isCancelled else { break }
                onCycle()
            }
        }
    }

    public func stop() {
        pumpTask?.cancel()
        pumpTask = nil
    }
}
