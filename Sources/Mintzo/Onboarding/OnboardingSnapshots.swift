#if DEBUG
import SwiftUI
import AppKit
import MintzoCore

/// Harnais de snapshots QA de l'onboarding — capture la fenêtre RÉELLE, chrome
/// compris. Lancé avec `MINTZO_ONBOARDING_SNAPSHOT_DIR=<dir>` (+
/// `-mintzo.hasCompletedOnboarding 0` pour présenter la fenêtre) : fige les
/// états clefs des 3 écrans (qaConfigure, sans polling) et écrit un PNG par
/// état en light + dark, puis quitte.
///
/// Pourquoi la capture passe par `window.contentView.superview` : cette vue
/// (la frame view AppKit, `NSThemeFrame`) dessine la barre de titre, les
/// traffic lights et les coins arrondis de la fenêtre — un `cacheDisplay`
/// dessus produit un PNG AVEC le chrome, exactement ce que voit l'utilisateur
/// (l'ancien rendu `ImageRenderer`/`contentView` produisait un rectangle nu,
/// cause majeure du feel « app web » des revues précédentes). `cacheDisplay`
/// rend aussi les contrôles AppKit (segmented, TextField, boutons) sans
/// permission d'enregistrement d'écran.
///
/// Fallback documenté : si la hiérarchie AppKit change et que `superview`
/// devient indisponible, on capture le `contentView` seul (PNG sans chrome)
/// et on le signale dans le log — la capture reste utilisable, le verdict
/// chrome se fait alors à la main sur la fenêtre live.
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
                $0.qaConfigure(screen: .ongiEtorri, microphone: .notDetermined, accessibility: .notDetermined)
            },
            // Un état mixte montre les deux rendus : accordée (coche) + à faire (bouton).
            QAState(name: "2-baimenak") {
                $0.qaConfigure(screen: .baimenak, microphone: .granted, accessibility: .notDetermined)
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
                    modelRow: .init(model: ModelCatalog.whisperEU, isInstalled: true),
                    trialPhase: .idle,
                    trialText: "Kaixo Maite, bihar goizean elkartuko gara bulegoan."
                )
            },
        ]

        // Laisser la fenêtre se présenter et poser son premier rendu.
        try? await Task.sleep(for: .seconds(1))
        var window: NSWindow?
        for _ in 0..<10 {
            window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 600 })
            if window != nil { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let window else {
            NSLog("MINTZO-ONBOARDING-SNAPSHOT: fenêtre live introuvable")
            exit(1)
        }

        // Fenêtre key + app active : sinon macOS rend contrôles ET traffic
        // lights à l'état inactif (gris) — capture non représentative. App
        // accessoire (LSUIElement) lancée du terminal : l'activation
        // coopérative est refusée → on passe temporairement en politique
        // `.regular` et on force (harnais QA uniquement).
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(600))

        for (appearanceName, appearance) in [
            ("light", NSAppearance(named: .aqua)),
            ("dark", NSAppearance(named: .darkAqua)),
        ] {
            // Apparence posée au niveau APP (pas seulement fenêtre) : le
            // contenu SwiftUI hébergé ne suit pas window.appearance seul.
            NSApplication.shared.appearance = appearance
            window.appearance = appearance
            try? await Task.sleep(for: .milliseconds(600))
            for state in states {
                state.configure(controller)
                try? await Task.sleep(for: .milliseconds(450))
                capture(window: window, to: dir.appendingPathComponent(
                    "mintzo-onboarding-\(state.name)-\(appearanceName).png"
                ))
            }
        }

        print("ONBOARDING SNAPSHOTS OK → \(dir.path)")
        exit(0)
    }

    /// PNG de la fenêtre entière, chrome compris (voir doc du type).
    private static func capture(window: NSWindow, to url: URL) {
        let frameView = window.contentView?.superview
        guard let view = frameView ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("MINTZO-ONBOARDING-SNAPSHOT: rendu impossible pour %@", url.lastPathComponent)
            return
        }
        if frameView == nil {
            NSLog("MINTZO-ONBOARDING-SNAPSHOT: superview indisponible — capture contentView SANS chrome (%@)",
                  url.lastPathComponent)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSLog("MINTZO-ONBOARDING-SNAPSHOT: écrit %@", url.lastPathComponent)
    }
}
#endif
