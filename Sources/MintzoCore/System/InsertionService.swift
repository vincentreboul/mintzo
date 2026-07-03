import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Résultat typé d'une insertion.
public enum InsertionResult: Sendable, Equatable {
    /// Le texte a été collé au curseur (Cmd+V simulé), clipboard restauré.
    case inserted
    /// Frappe simulée impossible : le texte est resté sur le clipboard pour un
    /// Cmd+V manuel — le clipboard n'est PAS restauré dans ce mode.
    case clipboardOnly(reason: ClipboardOnlyReason)
    /// Texte vide : aucune action (ni clipboard, ni frappe).
    case nothingToInsert
}

/// Pourquoi l'insertion est retombée en mode clipboard-seul.
public enum ClipboardOnlyReason: Sendable, Equatable {
    /// Un champ sécurisé (mot de passe) est actif : les CGEvents clavier sont
    /// bloqués par le système (TN2150) — on ne tente JAMAIS la frappe.
    case secureInputActive
    /// Permission Accessibility absente : impossible de poster des CGEvents.
    case accessibilityNotGranted
    /// La création/le post des CGEvents a échoué.
    case keystrokeSimulationFailed
}

/// Simulation de frappe clavier, isolée derrière un protocole : la vraie
/// simulation CGEvent exige la permission Accessibility et n'est pas testable
/// unitairement — les tests injectent un mock, l'intégration exerce le réel.
@MainActor
public protocol KeystrokeSimulating {
    /// Simule Cmd+V (keyDown puis keyUp). Lève si l'événement ne peut pas être créé.
    func simulatePaste() throws
}

/// Implémentation réelle : CGEvent keycode V + maskCommand postés sur le
/// session event tap. Requiert Accessibility (vérifié par l'appelant).
public struct CGEventKeystrokeSimulator: KeystrokeSimulating {
    public enum SimulationError: Error, Sendable, Equatable {
        case eventCreationFailed
    }

    public init() {}

    public func simulatePaste() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { throw SimulationError.eventCreationFailed }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

/// Sondes système injectables (testabilité de la matrice de décision).
public struct InsertionEnvironment: Sendable {
    /// Un champ sécurisé (saisie mot de passe) est-il actif ? (`IsSecureEventInputEnabled`)
    public var isSecureInputActive: @Sendable () -> Bool
    /// Le process est-il approuvé en Accessibility ? (`AXIsProcessTrusted`)
    public var isAccessibilityTrusted: @Sendable () -> Bool

    public init(
        isSecureInputActive: @escaping @Sendable () -> Bool,
        isAccessibilityTrusted: @escaping @Sendable () -> Bool
    ) {
        self.isSecureInputActive = isSecureInputActive
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    /// Sondes réelles.
    public static let live = InsertionEnvironment(
        isSecureInputActive: { IsSecureEventInputEnabled() },
        isAccessibilityTrusted: { AXIsProcessTrusted() }
    )
}

/// Délais du cycle pasteboard (injectés : quasi-nuls dans les tests).
public struct InsertionTiming: Sendable {
    /// Le pasteboard doit « prendre » avant la frappe (~50 ms empiriques).
    public var pasteboardSettle: Duration
    /// Attente avant restauration : laisse l'app cible consommer le paste
    /// (apps Electron lentes) sans écraser le collage (~250 ms).
    public var restoreDelay: Duration

    public init(pasteboardSettle: Duration, restoreDelay: Duration) {
        self.pasteboardSettle = pasteboardSettle
        self.restoreDelay = restoreDelay
    }

    public static let standard = InsertionTiming(
        pasteboardSettle: .milliseconds(50),
        restoreDelay: .milliseconds(250)
    )

    /// Pour les tests : aucun délai.
    public static let immediate = InsertionTiming(
        pasteboardSettle: .zero,
        restoreDelay: .zero
    )
}

/// Insertion du texte transcrit au curseur de l'app active.
///
/// Séquence (pattern de toute la catégorie — Speak2, VoiceInk, Wispr Flow) :
/// 1. snapshot des types courants du pasteboard,
/// 2. écriture du texte,
/// 3. Cmd+V simulé via CGEvent,
/// 4. restauration de l'ancien contenu après ~250 ms — seulement si personne
///    (clipboard manager, copie utilisateur) n'a écrit entre-temps.
///
/// Garde-fous vérifiés AVANT toute frappe : champ sécurisé actif ou
/// Accessibility manquante → mode clipboard-seul (le texte RESTE sur le
/// clipboard pour un Cmd+V manuel, aucune restauration).
///
/// `@MainActor` : NSPasteboard et le post d'événements vivent avec l'UI.
/// Le pasteboard est injecté — les tests utilisent un pasteboard nommé privé,
/// jamais `.general`.
@MainActor
public final class InsertionService {
    private let pasteboard: NSPasteboard
    private let keystrokes: any KeystrokeSimulating
    private let environment: InsertionEnvironment
    private let timing: InsertionTiming

    public init(
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokeSimulating = CGEventKeystrokeSimulator(),
        environment: InsertionEnvironment = .live,
        timing: InsertionTiming = .standard
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.environment = environment
        self.timing = timing
    }

    /// Insère `text` au curseur de l'app active. Ne lève jamais : tout échec
    /// dégrade en `.clipboardOnly` (le texte n'est jamais perdu).
    public func insert(_ text: String) async -> InsertionResult {
        guard !text.isEmpty else { return .nothingToInsert }

        guard environment.isAccessibilityTrusted() else {
            replaceClipboard(with: text)
            return .clipboardOnly(reason: .accessibilityNotGranted)
        }
        guard !environment.isSecureInputActive() else {
            replaceClipboard(with: text)
            return .clipboardOnly(reason: .secureInputActive)
        }

        let snapshot = PasteboardSnapshot(of: pasteboard)
        replaceClipboard(with: text)
        let changeCountAfterWrite = pasteboard.changeCount

        try? await Task.sleep(for: timing.pasteboardSettle)

        do {
            try keystrokes.simulatePaste()
        } catch {
            // Le texte reste sur le clipboard : l'utilisateur peut coller à la main.
            return .clipboardOnly(reason: .keystrokeSimulationFailed)
        }

        try? await Task.sleep(for: timing.restoreDelay)

        // Race clipboard managers (Raycast, Maccy…) : si le compteur a bougé
        // depuis notre écriture, quelqu'un d'autre a pris la main — ne pas
        // écraser son contenu.
        if pasteboard.changeCount == changeCountAfterWrite {
            snapshot.restore(to: pasteboard)
        }
        return .inserted
    }

    private func replaceClipboard(with text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Copie au niveau data de tous les types présents sur le pasteboard.
///
/// Limite documentée : certains types riches (fichiers, promesses) ne se
/// re-snapshotent pas parfaitement — restauration au mieux, fidèle pour les
/// types data-backed (string, rtf, png…).
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            return payload
        }
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
