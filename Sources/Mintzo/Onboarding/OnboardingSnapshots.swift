#if DEBUG
import SwiftUI
import AppKit
import MintzoCore

/// Harnais de snapshots QA de l'onboarding — même famille que le harnais HUD
/// (`MINTZO_HUD_SNAPSHOT_DIR`) : lancé avec
/// `MINTZO_ONBOARDING_SNAPSHOT_DIR=<dir>` (+ `-mintzo.hasCompletedOnboarding 0`
/// pour présenter la fenêtre), rend les états clefs des 3 écrans en light +
/// dark via `ImageRenderer` (géométrie/typo/couleurs pixel-exactes), puis quitte.
///
/// Limite connue : `TextEditor` (adossé AppKit) peut ne pas rasteriser son
/// contenu dans `ImageRenderer` — l'état « prest » est donc rendu champ vide
/// (placeholder SwiftUI pur), la frappe réelle se vérifie en live.
@MainActor
enum OnboardingSnapshots {

    static let environmentKey = "MINTZO_ONBOARDING_SNAPSHOT_DIR"

    private struct QAState {
        let name: String
        let configure: @MainActor (OnboardingController) -> Void
    }

    static func runIfRequested(controller: OnboardingController) async {
        guard let path = ProcessInfo.processInfo.environment[environmentKey] else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let states: [QAState] = [
            QAState(name: "1-ongi-etorri") {
                $0.qaConfigure(screen: .ongiEtorri, microphone: .notDetermined, accessibility: .denied)
            },
            QAState(name: "2-baimenak-ukatuta") {
                $0.qaConfigure(screen: .baimenak, microphone: .denied, accessibility: .denied)
            },
            QAState(name: "2-baimenak-emanda") {
                $0.qaConfigure(screen: .baimenak, microphone: .granted, accessibility: .granted)
            },
            QAState(name: "3-eredua-deskargatzen") {
                $0.qaConfigure(
                    screen: .eredua, microphone: .granted, accessibility: .granted,
                    modelRow: .init(
                        model: ModelCatalog.whisperEU,
                        isInstalled: false,
                        downloadFraction: 0.43,
                        downloadedBytes: Int64(Double(ModelCatalog.whisperEU.sizeBytes) * 0.43)
                    )
                )
            },
            QAState(name: "3-eredua-errorea") {
                $0.qaConfigure(
                    screen: .eredua, microphone: .granted, accessibility: .granted,
                    modelRow: .init(
                        model: ModelCatalog.whisperEU,
                        isInstalled: false,
                        errorMessage: ModelManagerError.networkFailure(
                            modelID: ModelCatalog.whisperEU.id,
                            detail: "La connexion réseau a été perdue."
                        ).errorDescription ?? ""
                    )
                )
            },
            QAState(name: "3-eredua-prest") {
                $0.qaConfigure(
                    screen: .eredua, microphone: .granted, accessibility: .granted,
                    modelRow: .init(model: ModelCatalog.whisperEU, isInstalled: true)
                )
            },
        ]

        for (appearanceName, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            NSApplication.shared.appearance = NSAppearance(
                named: appearanceName == "dark" ? .darkAqua : .aqua
            )
            try? await Task.sleep(for: .milliseconds(80))
            for state in states {
                state.configure(controller)
                let renderer = ImageRenderer(
                    content: OnboardingContainerView(controller: controller)
                        .environment(\.colorScheme, scheme)
                )
                renderer.scale = 2
                let url = dir.appendingPathComponent(
                    "mintzo-onboarding-\(state.name)-\(appearanceName).png"
                )
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) else {
                    NSLog("MINTZO-ONBOARDING-SNAPSHOT: rendu impossible pour %@", url.lastPathComponent)
                    continue
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                NSLog("MINTZO-ONBOARDING-SNAPSHOT: écrit %@", url.lastPathComponent)
            }
        }

        print("ONBOARDING SNAPSHOTS OK → \(dir.path)")
        exit(0)
    }

    // MARK: - Capture live de la vraie fenêtre

    static let liveEnvironmentKey = "MINTZO_ONBOARDING_LIVE_SNAPSHOT_DIR"

    /// Capture la fenêtre d'onboarding RÉELLE via `cacheDisplay` (comme le
    /// harnais HUD) : rend les contrôles AppKit (segmented, TextEditor,
    /// boutons) que `ImageRenderer` ne rastérise pas — sans permission
    /// d'enregistrement d'écran. Combiner avec `MINTZO_ONBOARDING_SCREEN`
    /// pour choisir l'écran. Light + dark, puis quitte.
    static func runLiveCaptureIfRequested(controller: OnboardingController) async {
        guard let path = ProcessInfo.processInfo.environment[liveEnvironmentKey] else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Laisser la fenêtre se présenter et poser son premier rendu.
        try? await Task.sleep(for: .seconds(1.5))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 600 }) else {
            NSLog("MINTZO-ONBOARDING-SNAPSHOT: fenêtre live introuvable")
            exit(1)
        }
        // Fenêtre key + app active : sinon macOS rend les contrôles en état
        // inactif (boutons proéminents grisés) — capture non représentative.
        // App accessoire lancée du terminal : l'activation coopérative simple
        // est refusée, on force (harnais QA uniquement).
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(600))

        let screenName = switch controller.journey.screen {
        case .ongiEtorri: "1-ongi-etorri"
        case .baimenak: "2-baimenak"
        case .eredua: "3-eredua"
        }

        for appearanceName in ["light", "dark"] {
            window.appearance = NSAppearance(
                named: appearanceName == "dark" ? .darkAqua : .aqua
            )
            try? await Task.sleep(for: .milliseconds(500))
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = dir.appendingPathComponent(
                "mintzo-onboarding-live-\(screenName)-\(appearanceName).png"
            )
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("MINTZO-ONBOARDING-SNAPSHOT: écrit %@", url.lastPathComponent)
        }

        print("ONBOARDING LIVE SNAPSHOTS OK → \(dir.path)")
        exit(0)
    }
}
#endif
