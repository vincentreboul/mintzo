import AppKit
import SwiftUI

// Fenêtre du HUD — spec : docs/design/design-language.md §4.1.
// NSPanel non-activant, level .statusBar, tous les Spaces + fullscreen,
// SANS ombre système (l'ombre spec y 8 / blur 24 est dessinée par la vue),
// et qui ne vole JAMAIS le focus (canBecomeKey = false, aucun makeKey).

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Un panel borderless refuse par défaut les événements souris sans être key ;
    // la capsule doit rester cliquable (clic = stop) sans jamais prendre le focus.
    override var acceptsFirstResponder: Bool { false }
}

/// NSHostingView dont la zone cliquable est restreinte à la capsule :
/// les marges transparentes du panel (halo, ombre) laissent passer les clics
/// vers les fenêtres en dessous.
final class HUDHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: () -> NSRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect().contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Possède le panel, le positionne bas-centre de l'écran du pointeur (V1),
/// et le montre/masque en observant la machine d'états du ViewModel.
@MainActor
final class HUDPanelController {
    private let panel: HUDPanel
    private let viewModel: HUDViewModel
    private var hideTask: Task<Void, Never>?

    init(viewModel: HUDViewModel) {
        self.viewModel = viewModel

        panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: HUDLayout.panelWidth, height: HUDLayout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                    // ombre custom spec (y 8, blur 24) côté SwiftUI
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none            // apparition/sortie animées par la vue (§7)
        panel.acceptsMouseMovedEvents = false

        let hostingView = HUDHostingView(rootView: HUDContentView(viewModel: viewModel))
        hostingView.interactiveRect = { [weak viewModel, weak hostingView] in
            guard let viewModel, let hostingView, viewModel.state.isVisible else { return .zero }
            return Self.capsuleRect(for: viewModel.state, in: hostingView)
        }
        panel.contentView = hostingView

        observeState()
    }

    #if DEBUG
    /// QA : accès au contentView pour les snapshots (MINTZO_HUD_SNAPSHOT_DIR).
    var panelContentView: NSView? { panel.contentView }
    #endif

    // MARK: Zone interactive = capsule seulement

    private static func capsuleRect(for state: HUDState, in view: NSView) -> NSRect {
        let width = state.fixedWidth ?? state.maxWidth
        let bounds = view.bounds
        let x = bounds.midX - width / 2
        let yFromBottom = HUDLayout.panelBottomInset
        let y = view.isFlipped
            ? bounds.height - yFromBottom - MzHUD.height
            : yFromBottom
        return NSRect(x: x, y: y, width: width, height: MzHUD.height)
    }

    // MARK: Position bas-centre (§4.1)

    /// Écran du pointeur (V1 ; l'écran du champ texte actif via AX viendra ensuite).
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func reposition() {
        guard let screen = Self.targetScreen() else { return }
        let visible = screen.visibleFrame
        // Bas de la capsule à visibleFrame.minY + 24 (24 pt au-dessus du Dock ou du bord).
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + MzHUD.bottomOffset - HUDLayout.panelBottomInset
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: Visibilité pilotée par la machine d'états

    private func observeState() {
        withObservationTracking {
            _ = viewModel.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleStateChange()
                self.observeState()
            }
        }
    }

    private func handleStateChange() {
        if viewModel.state.isVisible {
            hideTask?.cancel()
            hideTask = nil
            show()
        } else {
            scheduleHide()
        }
    }

    private func show() {
        if !panel.isVisible { reposition() }
        // orderFrontRegardless, jamais makeKey : le HUD ne vole pas le focus (§4.1).
        panel.orderFrontRegardless()
    }

    /// Laisse l'animation de sortie (220 ms) se jouer avant de masquer la fenêtre.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }
}
