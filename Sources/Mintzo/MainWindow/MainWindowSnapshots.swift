#if DEBUG
import SwiftUI
import AppKit
import MintzoCore

/// Harnais de snapshots QA de la fenêtre principale — même famille que les
/// harnais HUD (`MINTZO_HUD_SNAPSHOT_DIR`) et onboarding : il ouvre une
/// vraie fenêtre AppKit (contenu 760 × 560) hébergeant `MainWindowRootView`
/// avec 6 transcriptions seed réalistes (eu + fr) et une file d'attente
/// active, attend le layout, puis capture **`window.contentView.superview`
/// (NSThemeFrame) via `cacheDisplay`** — le PNG inclut donc la barre de
/// titre, les traffic lights, la toolbar unifiée et les coins natifs, ce que
/// les harnais `contentView` seuls ne montraient pas (cause du rendu « web »
/// perçu). États « history » et « empty », puis quitte.
///
/// Lancement recommandé (R2) — un process PAR apparence, via `open` :
/// ```
/// open -W -n Mintzo.app --args -mintzo.hasCompletedOnboarding 1 \
///   -mintzo.windowSnapshotDir <dir> -mintzo.windowSnapshotAppearance light
/// ```
/// Leçons mesurées R1→R3 :
/// - les capsules Liquid Glass des items de toolbar (segmented, recherche)
///   ne rendent PAS leur backdrop dans un dessin offscreen (`cacheDisplay`)
///   → fallback blanc opaque, flagrant en dark. La capture passe donc par le
///   COMPOSITEUR (`CGWindowListCreateImage` sur sa propre fenêtre — exempté
///   de la permission Screen Recording), repli `cacheDisplay` loggé ;
/// - app `LSUIElement` lancée du terminal : l'activation est refusée
///   (`activateIgnoringOtherApps` sans effet depuis macOS 14) → traffic
///   lights gris. `QAWindow` force le rendu « fenêtre active », et `open`
///   lance via LaunchServices comme un vrai lancement utilisateur ;
/// - une apparence PAR process : la bascule à chaud de `NSApp.appearance`
///   reste un facteur d'instabilité de rendu des contrôles bridgés.
///
/// Replis documentés : `MINTZO_WINDOW_SNAPSHOT_DIR=<dir>` (env) reste lu
/// (lancement direct du binaire, les DEUX apparences dans le même process) ;
/// si la fenêtre n'est pas capturable au compositeur, repli `cacheDisplay`
/// du NSThemeFrame, puis `contentView` seul (chrome absent, loggé).
@MainActor
enum MainWindowSnapshots {

    static let environmentKey = "MINTZO_WINDOW_SNAPSHOT_DIR"
    /// Équivalents UserDefaults (`-mintzo.windowSnapshotDir <dir>`) : les
    /// variables d'environnement ne traversent pas `open`/LaunchServices.
    static let directoryDefaultsKey = "mintzo.windowSnapshotDir"
    static let appearanceDefaultsKey = "mintzo.windowSnapshotAppearance"

    private static var scheduled = false

    /// Appelé depuis `MainWindowScene.init` (seul point d'entrée MainWindow
    /// exécuté au lancement — la fenêtre réelle reste supprimée au launch).
    static func scheduleIfRequested() {
        guard !scheduled else { return }
        let defaults = UserDefaults.standard
        let path = defaults.string(forKey: directoryDefaultsKey)
            ?? ProcessInfo.processInfo.environment[environmentKey]
        guard let path else { return }
        scheduled = true
        let appearances: [String] = switch defaults.string(forKey: appearanceDefaultsKey) {
        case "light": ["light"]
        case "dark": ["dark"]
        default: ["light", "dark"]
        }
        // Posés ICI, pendant le launch même (avant `finishLaunching`),
        // avant la création de toute fenêtre :
        // - politique regular (l'app est déclarée `LSUIElement`) ;
        // - rendu « app active » forcé — voir `forceActiveRendering` ;
        // - apparence unique : les contrôles bridgés naissent directement
        //   dans la bonne apparence, aucune bascule à chaud.
        NSApplication.shared.setActivationPolicy(.regular)
        forceActiveRendering()
        if appearances.count == 1, let only = appearances.first {
            NSApplication.shared.appearance =
                NSAppearance(named: only == "dark" ? .darkAqua : .aqua)
        }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        Task { await run(outputDir: dir, appearances: appearances) }
    }

    /// Force le rendu « app active » : `NSApp.isActive` pilote la couleur
    /// des traffic lights et l'encre de la barre de titre. En batch, macOS
    /// refuse l'activation d'un process qui n'a pas le focus utilisateur
    /// (activation coopérative, macOS 14+) → tout le chrome se dessinait
    /// « fenêtre inactive » (gris), non représentatif de l'app en usage.
    /// Le harnais photographie l'app comme si l'utilisateur l'avait au
    /// premier plan : l'implémentation du getter `isActive` est remplacée
    /// pour retourner `true`. Process QA éphémère, DEBUG uniquement.
    private static func forceActiveRendering() {
        guard let method = class_getInstanceMethod(
            NSApplication.self, #selector(getter: NSApplication.isActive)
        ) else {
            NSLog("MINTZO-WINDOW-SNAPSHOT: getter isActive introuvable — traffic lights possiblement gris")
            return
        }
        let alwaysActive: @convention(block) (NSApplication) -> Bool = { _ in true }
        method_setImplementation(method, imp_implementationWithBlock(alwaysActive))
    }

    private static func run(outputDir: URL, appearances: [String]) async {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Laisser l'app finir son lancement (scènes, menu bar).
        try? await Task.sleep(for: .milliseconds(800))

        // Chrome et microcopy déterministes : euskara par défaut (référence du §6.2),
        // surchargeable pour les tours visuels multilingues via
        // `-mintzo.windowSnapshotLanguage eu|fr|en`.
        switch UserDefaults.standard.string(forKey: "mintzo.windowSnapshotLanguage") {
        case "fr": MzL10n.forced = .fr
        case "en": MzL10n.forced = .en
        default: MzL10n.forced = .eu
        }

        // Activation réelle best-effort (sans conséquence sur le rendu :
        // `forceActiveRendering` l'a rendu indépendant du focus système).
        NSApp.activate()

        // État 1 — historique seedé (3 sections : gaur / atzo / date) + file.
        guard let seeded = makeSeededStore() else {
            NSLog("MINTZO-WINDOW-SNAPSHOT: seed du store impossible")
            exit(1)
        }
        let queue = QASnapshotQueue(items: [
            QueueItem(nomFichier: "ahots-mezua.opus", progress: 0.62, duree: 72, langue: .eu),
            QueueItem(nomFichier: "bilera-osoa.m4a"),
        ])
        await capture(
            state: "history",
            rootView: MainWindowRootView(
                store: seeded.store,
                queue: queue,
                initialTranscriptions: seeded.rows
            ),
            in: outputDir,
            appearances: appearances
        )

        // État 2 — vide (ContentUnavailableView, geste éditorial serif).
        if let emptyStore = try? HistoryStore.inMemory() {
            await capture(
                state: "empty",
                rootView: MainWindowRootView(store: emptyStore),
                in: outputDir,
                appearances: appearances
            )
        }

        // État 3 — détail avec audio conservé : surface de réécoute (lecteur
        // play/pause + progression Gorri + durées) et menu « Berriz sortu ».
        if let detail = makeDetailSeed() {
            // Store injecté : fait apparaître le bouton Supprimer de la toolbar.
            let detailStore = try? HistoryStore.inMemory()
            await capture(
                state: "detail-audio",
                // Même tint que la fenêtre réelle (`MainWindowRootView`) : les
                // contrôles standards héritent de l'accent Gorri (§2.1).
                rootView: NavigationStack {
                    TranscriptionDetailView(transcription: detail, store: detailStore)
                }
                .tint(MzColor.gorri),
                in: outputDir,
                appearances: appearances
            )
        }

        print("WINDOW SNAPSHOTS OK → \(outputDir.path)")
        exit(0)
    }

    /// Entrée de détail avec un VRAI WAV conservé (3 s de signal modulé,
    /// écrit dans un répertoire temporaire) : la surface de réécoute rend
    /// exactement comme en production.
    private static func makeDetailSeed() -> Transcription? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mintzo-snapshot-audio-\(ProcessInfo.processInfo.processIdentifier)",
                                    isDirectory: true)
        let audioStore = TranscriptionAudioStore(directory: directory)
        let samples: [Float] = (0..<48_000).map { index in
            let t = Float(index) / 16_000
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 0.35 * t)
            return 0.4 * envelope * sin(2 * .pi * 220 * t)
        }
        guard let url = try? audioStore.write(samples: samples) else { return nil }
        return Transcription(
            id: 1,
            texteBrut: "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ekarri azken aurrekontua mesedez",
            texteCorrige: "Kaixo Maite, bihar goizean elkartuko gara bulegoan proiektua ixteko. Ekarri azken aurrekontua, mesedez.",
            date: .now,
            dureeAudio: 3,
            langue: .eu,
            source: .dictee,
            audioPath: url.path
        )
    }

    // MARK: - Fenêtre réelle + capture du frame natif

    /// Une fenêtre FRAÎCHE par apparence : basculer `NSApp.appearance` sur
    /// une fenêtre vivante laisse des contrôles de toolbar bridgés avec leur
    /// rendu de l'apparence précédente (blobs blancs observés R1 en dark —
    /// et même sur fenêtre fraîche, R2 : d'où le mode « une apparence par
    /// process » du lancement recommandé).
    private static func capture(
        state: String, rootView: some View, in dir: URL, appearances: [String]
    ) async {
        for appearanceName in appearances {
            // Apparence posée au niveau APP AVANT de créer la fenêtre : le
            // contenu SwiftUI hébergé ne suit pas window.appearance seul.
            let appearance = NSAppearance(named: appearanceName == "dark" ? .darkAqua : .aqua)
            NSApplication.shared.appearance = appearance
            try? await Task.sleep(for: .milliseconds(200))

            let window = QAWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Mintzo"
            window.toolbarStyle = .unified
            window.appearance = appearance

            let hosting = NSHostingView(rootView: AnyView(rootView))
            // La toolbar SwiftUI (titre, filtre segmented, .searchable) pilote
            // la vraie NSToolbar de la fenêtre — indispensable au chrome unifié.
            hosting.sceneBridgingOptions = [.toolbars, .title]
            // Ne jamais laisser la vue hébergée redimensionner la fenêtre à sa
            // taille idéale (observé R1 : fenêtre rétrécie sur l'état vide).
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setContentSize(NSSize(width: 760, height: 560))
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)

            // Layout + bridging de la toolbar : asynchrones.
            try? await Task.sleep(for: .seconds(1.2))

            guard let rep = compositorRep(of: window) ?? cacheDisplayRep(of: window, state: state) else {
                NSLog("MINTZO-WINDOW-SNAPSHOT: aucune vue capturable pour %@", state)
                continue
            }
            let url = dir.appendingPathComponent("mintzo-window-\(state)-\(appearanceName).png")
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                NSLog("MINTZO-WINDOW-SNAPSHOT: écrit %@", url.lastPathComponent)
            } catch {
                NSLog("MINTZO-WINDOW-SNAPSHOT: échec écriture %@ — %@", url.lastPathComponent, "\(error)")
            }

            window.orderOut(nil)
        }
    }

    /// Capture au COMPOSITEUR : le rendu réel affiché à l'écran, capsules
    /// Liquid Glass des items de toolbar comprises. Capturer SA PROPRE
    /// fenêtre est exempté de la permission Screen Recording ;
    /// ScreenCaptureKit, lui, l'exige même pour soi (prompt TCC →
    /// inacceptable pour un harnais silencieux). `CGWindowListCreateImage`
    /// est marquée `unavailable` en Swift sur le SDK macOS 26 mais la
    /// fonction C est toujours présente et fonctionnelle dans CoreGraphics :
    /// résolue via `dlsym`, harnais DEBUG uniquement. Si Apple retire le
    /// symbole un jour, le harnais loggue et replie sur `cacheDisplay`.
    private typealias WindowImageFn =
        @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static let windowImageFn: WindowImageFn? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    private static func compositorRep(of window: NSWindow) -> NSBitmapImageRep? {
        guard window.windowNumber > 0, let windowImageFn else {
            NSLog("MINTZO-WINDOW-SNAPSHOT: capture compositeur indisponible — repli cacheDisplay")
            return nil
        }
        let listOption: UInt32 = 1 << 3       // kCGWindowListOptionIncludingWindow
        let imageOptions: UInt32 = 1 | 1 << 3 // BoundsIgnoreFraming | BestResolution
        guard let image = windowImageFn(
            .null, listOption, UInt32(window.windowNumber), imageOptions
        )?.takeRetainedValue(), image.width > 1, image.height > 1 else {
            NSLog("MINTZO-WINDOW-SNAPSHOT: capture compositeur vide — repli cacheDisplay")
            return nil
        }
        return NSBitmapImageRep(cgImage: image)
    }

    /// Repli hors compositeur : NSThemeFrame via `cacheDisplay` (chrome
    /// complet mais verre des items de toolbar en fallback opaque — cause
    /// des blobs blancs R1/R2), sinon `contentView` seul.
    private static func cacheDisplayRep(of window: NSWindow, state: String) -> NSBitmapImageRep? {
        let target: NSView
        if let frameView = window.contentView?.superview, frameView.bounds.width > 0 {
            target = frameView
        } else if let contentView = window.contentView {
            NSLog("MINTZO-WINDOW-SNAPSHOT: NSThemeFrame indisponible — repli contentView (chrome absent)")
            target = contentView
        } else {
            return nil
        }
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return nil }
        target.cacheDisplay(in: target.bounds, to: rep)
        return rep
    }

    // MARK: - Données seed (6 transcriptions réalistes eu + fr)

    private static func makeSeededStore() -> (store: HistoryStore, rows: [Transcription])? {
        guard let store = try? HistoryStore.inMemory() else { return nil }

        let calendar = Calendar.current
        func at(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let seeds: [Transcription] = [
            Transcription(
                texteBrut: "Kaixo Maite, bihar goizean elkartuko gara bulegoan proiektua ixteko. Ekarri azken aurrekontua, mesedez.",
                date: at(daysAgo: 0, 14, 32), dureeAudio: 42, langue: .eu, source: .dictee
            ),
            Transcription(
                texteBrut: "le devis part ce soir je t'appelle après la réunion pour valider les délais",
                texteCorrige: "Le devis part ce soir, je t\u{2019}appelle après la réunion pour valider les délais.",
                date: at(daysAgo: 0, 11, 5), dureeAudio: 31, langue: .fr, source: .dictee
            ),
            Transcription(
                texteBrut: "Bileraren laburpena: aurrekontua onartuta dago, eta datorren astean lehen fasearekin hasiko gara.",
                date: at(daysAgo: 0, 9, 12), dureeAudio: 206, langue: .eu, source: .fichier,
                nomFichier: "bilera-astelehena.m4a"
            ),
            Transcription(
                texteBrut: "N\u{2019}oublie pas d\u{2019}envoyer la facture à Ander avant vendredi, avec le récapitulatif des heures du mois.",
                date: at(daysAgo: 1, 18, 47), dureeAudio: 58, langue: .fr, source: .dictee
            ),
            Transcription(
                texteBrut: "Arratsaldean deituko dizut kontratuaren azken xehetasunak zehazteko. Prestatu zirriborroa, mesedez.",
                date: at(daysAgo: 1, 10, 3), dureeAudio: 72, langue: .eu, source: .dictee
            ),
            Transcription(
                texteBrut: "L\u{2019}important, c\u{2019}est que la langue vive dans les usages quotidiens — au travail, dans les messages, pas seulement à l\u{2019}école.",
                date: at(daysAgo: 3, 16, 20), dureeAudio: 727, langue: .fr, source: .fichier,
                nomFichier: "elkarrizketa-irratia.mp3"
            ),
        ]

        var rows: [Transcription] = []
        for seed in seeds {
            guard let inserted = try? store.insert(seed) else { return nil }
            rows.append(inserted)
        }
        return (store, rows.sorted { $0.date > $1.date })
    }
}

/// File d'attente figée pour les rendus QA.
@MainActor
private final class QASnapshotQueue: QueueDisplaying {
    let items: [QueueItem]
    init(items: [QueueItem]) { self.items = items }
}

/// Fenêtre de harnais : se déclare key/main quel que soit l'état d'activation
/// réel du process — traffic lights et contrôles se dessinent « fenêtre
/// active » même quand macOS refuse l'activation (app `LSUIElement` lancée
/// en batch, `activateIgnoringOtherApps` sans effet depuis macOS 14).
/// Technique standard de snapshot-testing AppKit ; harnais QA uniquement.
private final class QAWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
#endif
