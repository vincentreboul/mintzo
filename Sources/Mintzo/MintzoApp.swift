import SwiftUI
import Observation

@main
struct MintzoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(model: model)
        } label: {
            MenuBarIconView(state: model.menuBarState, languageFlash: model.languageFlash)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Modèle applicatif (menu bar + HUD)

@MainActor
@Observable
final class AppModel {
    let hud = HUDViewModel()
    @ObservationIgnored private(set) var hudPanel: HUDPanelController?
    /// Bascule de langue hors session : le glyphe menu bar affiche « eu »/« fr » 1 s (§5.2).
    private(set) var languageFlash: HUDLanguage?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?

    /// État de l'icône menu bar, dérivé de la machine d'états du HUD (§5.2).
    var menuBarState: MenuBarState {
        switch hud.state {
        case .listening: .recording
        case .transcribing, .correcting: .processing
        case .error: .error
        case .idle, .success: .idle
        }
    }

    /// Langue courante — liaison du segmented du popover (§5.3).
    var language: HUDLanguage {
        get { hud.language }
        set { setLanguage(newValue) }
    }

    init() {
        hudPanel = HUDPanelController(viewModel: hud)
        #if DEBUG
        if ProcessInfo.processInfo.environment["MINTZO_HUD_PREVIEW"] == "1" {
            startHUDPreview()
        }
        #endif
    }

    func setLanguage(_ newLanguage: HUDLanguage) {
        guard newLanguage != hud.language else { return }
        hud.setLanguage(newLanguage)
        // Feedback icône menu bar uniquement hors session (§4.4, §5.2).
        guard !hud.state.isVisible else { return }
        languageFlash = newLanguage
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MenuBarGlyph.languageFlashDuration))
            guard !Task.isCancelled else { return }
            self?.languageFlash = nil
        }
    }

    // MARK: Mode preview DEBUG (validation visuelle sans moteur audio)

    #if DEBUG
    /// `MINTZO_HUD_PREVIEW=1` : HUD en écoute avec waveform simulée (sinus + bruit),
    /// cycle des états toutes les 3 s. `MINTZO_HUD_PREVIEW_STATE=<état>` : fige un état.
    private func startHUDPreview() {
        hud.onStopRequested = { [weak self] in self?.hud.transition(to: .transcribing) }

        // Voix simulée : enveloppe sinusoïdale lente × porteuse + bruit, avec respirations.
        // Alimente le RMS toutes les ~30 ms (le tick 66 ms du ViewModel échantillonne ce niveau).
        feedTask = Task { [hud] in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                let envelope = 0.5 + 0.5 * sin(2 * .pi * 0.35 * t)          // phrasé lent
                let carrier = 0.5 + 0.5 * sin(2 * .pi * 1.4 * t)            // modulation voix
                let noise = Double.random(in: 0...0.22)
                let breathing = envelope < 0.18                              // pauses de souffle
                let rms = breathing ? Double.random(in: 0...0.015)
                                    : min(1, 0.05 + 0.55 * envelope * carrier + noise)
                hud.ingest(rms: rms)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }

        previewTask = Task { [hud] in
            if let fixed = ProcessInfo.processInfo.environment["MINTZO_HUD_PREVIEW_STATE"] {
                Self.enterFixedPreviewState(fixed, hud: hud)
            } else {
                await Self.cyclePreviewStates(hud: hud)
            }
        }
    }

    /// Fige un état pour screenshot : listening / transcribing / correcting / success / error.
    private static func enterFixedPreviewState(_ name: String, hud: HUDViewModel) {
        hud.autoDismissEnabled = false
        hud.transition(to: .listening)
        switch name {
        case "listening":
            break
        case "transcribing":
            hud.transition(to: .transcribing)
        case "correcting":
            hud.transition(to: .transcribing)
            hud.transition(to: .correcting)
        case "success":
            hud.transition(to: .transcribing)
            hud.transition(to: .success)
        case "error":
            hud.transition(to: .error(message: "Euskarazko eredua falta da."))
        default:
            break
        }
    }

    /// Cycle complet toutes les 3 s : écoute → transcription → correction → succès → écoute → erreur.
    private static func cyclePreviewStates(hud: HUDViewModel) async {
        let dwell: Duration = .seconds(3)
        while !Task.isCancelled {
            hud.transition(to: .listening)
            try? await Task.sleep(for: dwell)
            hud.transition(to: .transcribing)
            try? await Task.sleep(for: dwell)
            hud.transition(to: .correcting)
            try? await Task.sleep(for: dwell)
            hud.transition(to: .success)          // auto-dismiss 600 ms → idle
            try? await Task.sleep(for: dwell)
            hud.transition(to: .listening)
            try? await Task.sleep(for: dwell)
            hud.transition(to: .error(message: "Euskarazko eredua falta da."))
            try? await Task.sleep(for: dwell)
        }
    }
    #endif
}
