import AppKit
import Observation

/// Apparence de l'app : suivre le système (défaut), clair, ou sombre —
/// à la SuperWhisper. « Sombre » force `darkAqua` sur toute l'app : fenêtre
/// principale, Réglages ET capsule HUD (les fenêtres sans apparence propre
/// héritent de `NSApp.appearance`).
public enum AppAppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Backend d'application — abstraction de `NSApplication` (prod) pour la
/// testabilité : `NSApp.appearance` touche le rendu réel et ne se teste pas
/// en CI.
@MainActor
public protocol AppearanceBackend {
    /// `nil` → suivre le système ; sinon l'apparence nommée (aqua / darkAqua).
    func setAppearance(named name: NSAppearance.Name?)
}

extension NSApplication: AppearanceBackend {
    public func setAppearance(named name: NSAppearance.Name?) {
        appearance = name.flatMap(NSAppearance.init(named:))
    }
}

/// Apparence persistée et appliquée à chaud.
///
/// - Au lancement (`applyCurrentMode`) : appelée AVANT la création de toute
///   fenêtre (coordinator init) — le HUD et l'onboarding naissent déjà dans
///   la bonne apparence.
/// - À chaud (`setMode`) : `NSApp.appearance = nil / NSAppearance(named:)`,
///   AppKit répercute immédiatement sur toutes les fenêtres qui héritent.
@MainActor
@Observable
public final class AppearanceService {

    public static let defaultsKey = "mintzo.appearance"

    @ObservationIgnored private let backend: any AppearanceBackend
    @ObservationIgnored private let defaults: UserDefaults

    /// Mode courant. Écriture via `setMode(_:)` uniquement (persistance + application).
    public private(set) var mode: AppAppearanceMode

    public init(
        backend: (any AppearanceBackend)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend ?? NSApplication.shared
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.defaultsKey) ?? ""
        self.mode = AppAppearanceMode(rawValue: raw) ?? .system
    }

    /// Change le mode (action utilisateur) : persiste puis applique à chaud.
    public func setMode(_ newMode: AppAppearanceMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.defaultsKey)
        apply()
    }

    /// Applique le mode persisté sans le changer — appelé au lancement.
    public func applyCurrentMode() {
        apply()
    }

    private func apply() {
        let name: NSAppearance.Name? = switch mode {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        backend.setAppearance(named: name)
    }
}
