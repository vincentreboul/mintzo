import SwiftUI
import AppKit
import Observation

@main
struct MintzoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(model: model)
        } label: {
            MenuBarIconView(state: model.menuBarState,
                            frame: model.menuBarFrame,
                            languageFlash: model.languageFlash)
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
    /// Frame courante des animations de l'icône menu bar (cycle 900 ms / pulse 1,6 s).
    private(set) var menuBarFrame = 0
    @ObservationIgnored private var iconAnimationInterval: TimeInterval?
    @ObservationIgnored private var iconAnimationTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

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
        #if DEBUG
        // QA : force l'apparence de l'app (audit light/dark sans toucher au système).
        if let forced = ProcessInfo.processInfo.environment["MINTZO_APPEARANCE"] {
            NSApplication.shared.appearance = NSAppearance(
                named: forced == "dark" ? .darkAqua : .aqua
            )
        }
        #endif
        hudPanel = HUDPanelController(viewModel: hud)
        observeIconAnimation()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MINTZO_HUD_PREVIEW"] == "1" {
            startHUDPreview()
        }
        if let snapshotDir = ProcessInfo.processInfo.environment["MINTZO_HUD_SNAPSHOT_DIR"] {
            startSnapshotRun(directory: snapshotDir)
        }
        #endif
    }

    // MARK: Animation icône menu bar (cadence pilotée modèle, jamais dans le label)

    private func observeIconAnimation() {
        withObservationTracking {
            _ = hud.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateIconAnimation()
                self.observeIconAnimation()
            }
        }
        updateIconAnimation()
    }

    private func updateIconAnimation() {
        let interval: TimeInterval? = switch menuBarState {
        case .recording: MenuBarGlyph.recordingFrameInterval               // cycle 900 ms / 3 frames
        case .processing: MenuBarGlyph.processingPulseDuration / 8         // pulse 1,6 s / 8 frames
        case .idle, .error: nil
        }
        guard interval != iconAnimationInterval else { return }
        iconAnimationInterval = interval
        iconAnimationTask?.cancel()
        iconAnimationTask = nil
        menuBarFrame = 0
        guard let interval else { return }
        iconAnimationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.menuBarFrame += 1
            }
        }
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
        startSimulatedVoiceFeed()

        previewTask = Task { [hud] in
            if let fixed = ProcessInfo.processInfo.environment["MINTZO_HUD_PREVIEW_STATE"] {
                Self.enterFixedPreviewState(fixed, hud: hud)
            } else {
                await Self.cyclePreviewStates(hud: hud)
            }
        }
    }

    /// Voix simulée : enveloppe sinusoïdale lente × porteuse + bruit, avec respirations.
    /// Alimente le RMS toutes les ~30 ms (le tick 66 ms du ViewModel échantillonne ce niveau).
    private func startSimulatedVoiceFeed() {
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

    // MARK: Harnais de snapshots QA (MINTZO_HUD_SNAPSHOT_DIR=<dir>)

    /// Rend chaque état du HUD (light + dark), les glyphes menu bar et le popover en PNG,
    /// puis quitte. Rendu via cacheDisplay du contentView du panel : géométrie/couleurs
    /// pixel-exactes, MAIS le sampling « verre » derrière la fenêtre n'est pas composité.
    private func startSnapshotRun(directory: String) {
        NSLog("MINTZO-SNAPSHOT: run demandé → %@", directory)
        hud.autoDismissEnabled = false
        startSimulatedVoiceFeed()
        let dir = URL(fileURLWithPath: directory, isDirectory: true)

        snapshotTask = Task { [self] in
            NSLog("MINTZO-SNAPSHOT: task démarrée")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Un run par apparence (MINTZO_APPEARANCE) : l'apparence est posée dans init
            // AVANT la création du panel — résolution des couleurs fiable dès le 1er rendu.
            let appearances = ProcessInfo.processInfo.environment["MINTZO_APPEARANCE"]
                .map { [$0] } ?? ["light", "dark"]
            for appearanceName in appearances {
                let appearance = NSAppearance(named: appearanceName == "dark" ? .darkAqua : .aqua)
                NSApplication.shared.appearance = appearance
                hudPanel?.panelContentView?.window?.appearance = appearance
                let shoot: @MainActor (String) -> Void = { [self] state in
                    snapshotPanel(to: dir.appendingPathComponent("mintzo-hud-\(state)-\(appearanceName).png"))
                }
                hud.transition(to: .listening)
                try? await Task.sleep(for: .seconds(2.2))   // timer 0:02, waveform vivante
                shoot("listening")
                hud.transition(to: .transcribing)
                try? await Task.sleep(for: .milliseconds(800))
                shoot("transcribing")
                hud.transition(to: .correcting)
                try? await Task.sleep(for: .milliseconds(500))
                shoot("correcting")
                hud.transition(to: .success)
                try? await Task.sleep(for: .milliseconds(800))
                shoot("success")
                hud.transition(to: .listening)
                hud.transition(to: .error(message: "Euskarazko eredua falta da."))
                try? await Task.sleep(for: .milliseconds(800))
                shoot("error")
                hud.transition(to: .idle)
                try? await Task.sleep(for: .milliseconds(500))
            }

            snapshotMenuBarGlyphs(to: dir)
            snapshotPopover(to: dir)
            print("SNAPSHOTS OK → \(dir.path)")
            exit(0)
        }
    }

    private func snapshotPanel(to url: URL) {
        guard let view = hudPanel?.panelContentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("MINTZO-SNAPSHOT: contentView/rep indisponible pour %@", url.lastPathComponent)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("MINTZO-SNAPSHOT: écrit %@", url.lastPathComponent)
        } catch {
            NSLog("MINTZO-SNAPSHOT: échec écriture %@ — %@", url.lastPathComponent, "\(error)")
        }
    }

    /// Glyphes menu bar rasterisés à 4× sur fond simulé menu bar (light + dark).
    private func snapshotMenuBarGlyphs(to dir: URL) {
        let variants: [(String, NSImage)] = [
            ("idle", MenuBarGlyph.idle),
            ("recording-f0", MenuBarGlyph.recordingFrames[0]),
            ("recording-f1", MenuBarGlyph.recordingFrames[1]),
            ("recording-f2", MenuBarGlyph.recordingFrames[2]),
            ("processing", MenuBarGlyph.processingFrames[2]),
            ("error", MenuBarGlyph.error),
        ]
        for appearanceName in ["light", "dark"] {
            guard let appearance = NSAppearance(
                named: appearanceName == "dark" ? .darkAqua : .aqua
            ) else { continue }
            for (name, image) in variants {
                let side = 72   // 18 pt × 4
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ), let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                appearance.performAsCurrentDrawingAppearance {
                    let background: NSColor = appearanceName == "dark"
                        ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
                    background.setFill()
                    NSRect(x: 0, y: 0, width: side, height: side).fill()
                    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
                }
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("mintzo-menubar-\(name)-\(appearanceName).png"))
            }
        }
    }

    /// Popover rendu hors fenêtre (layout/typo seulement — le matériau vibrancy est système).
    private func snapshotPopover(to dir: URL) {
        for (appearanceName, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            NSApplication.shared.appearance = NSAppearance(
                named: appearanceName == "dark" ? .darkAqua : .aqua
            )
            let renderer = ImageRenderer(
                content: MenuBarPopoverView(model: self)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { continue }
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("mintzo-popover-\(appearanceName).png"))
        }
    }
    #endif
}
