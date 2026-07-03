import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers
import MintzoCore

/// `MenuBarPopoverView` (vague 2) référence le modèle sous ce nom — conservé.
typealias AppModel = AppCoordinator

/// Coordinator applicatif : possède les services (hotkey, capture, transcription,
/// correction, insertion, permissions, historique, modèles), le HUD (view model +
/// panel) et l'état du menu bar. Fait circuler : hotkey → `DictationFlow` → HUD /
/// insertion / historique, et (vague fichiers) drop → file de transcription.
///
/// Reprend intégralement l'ancien `AppModel` (animations icône menu bar, flash
/// langue, harnais DEBUG preview/snapshots) — mêmes comportements, mêmes specs
/// (§4, §5 du design language).
@MainActor
@Observable
final class AppCoordinator {

    // MARK: HUD

    let hud = HUDViewModel()
    @ObservationIgnored private(set) var hudPanel: HUDPanelController?

    // MARK: Services (usage interne, hors observation)

    @ObservationIgnored let historyStore: HistoryStore
    @ObservationIgnored let modelManager = ModelManager()
    @ObservationIgnored let permissions = PermissionsService()
    @ObservationIgnored private let hotkeys = HotkeyService()
    @ObservationIgnored private let captureService = CaptureService()
    @ObservationIgnored private let transcriptionService: TranscriptionService
    @ObservationIgnored private let insertionService = InsertionService()
    @ObservationIgnored private(set) var flow: DictationFlow!
    @ObservationIgnored private var latxaLoader: LatxaEngineLoader?

    /// File d'affichage des transcriptions de fichiers (fenêtre principale §6.3).
    let fileQueue: FileTranscriptionQueue

    /// Bibliothèque de modèles (onglet Ereduak) : whisper eu/fr/tiny + Latxa.
    let modelLibrary: ModelLibraryController

    // MARK: Actions fenêtres (injectées par la scène au premier rendu)

    @ObservationIgnored private var openMainWindowAction: () -> Void = {}
    @ObservationIgnored private var openSettingsWindowAction: () -> Void = {}
    @ObservationIgnored private var bootstrapped = false

    // MARK: État menu bar

    /// Bascule de langue hors session : le glyphe menu bar affiche « eu »/« fr » 1 s (§5.2).
    private(set) var languageFlash: HUDLanguage?
    /// Frame courante des animations de l'icône menu bar (cycle 900 ms / pulse 1,6 s).
    private(set) var menuBarFrame = 0
    /// Échec d'un fichier de la file : badge erreur temporaire sur l'icône (§5.2).
    private(set) var fileErrorFlash = false
    @ObservationIgnored private var iconAnimationInterval: TimeInterval?
    @ObservationIgnored private var iconAnimationTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var fileErrorTask: Task<Void, Never>?
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var notificationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var escapeMonitors: [Any] = []
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

    /// État de l'icône menu bar (§5.2) : la dictée (HUD) prime, puis l'échec
    /// fichier (badge 4 s), puis l'activité de la file, sinon repos.
    var menuBarState: MenuBarState {
        switch hud.state {
        case .listening: return .recording
        case .transcribing, .correcting: return .processing
        case .error: return .error
        case .idle, .success:
            if fileErrorFlash { return .error }
            return fileQueue.isWorking ? .processing : .idle
        }
    }

    /// Langue courante — liaison du segmented du popover (§5.3).
    var language: HUDLanguage {
        get { hud.language }
        set { setLanguage(newValue) }
    }

    // MARK: - Init

    init() {
        #if DEBUG
        // QA : force l'apparence de l'app (audit light/dark sans toucher au système).
        if let forced = ProcessInfo.processInfo.environment["MINTZO_APPEARANCE"] {
            NSApplication.shared.appearance = NSAppearance(
                named: forced == "dark" ? .darkAqua : .aqua
            )
        }
        #endif

        AppSettings.registerDefaults()
        historyStore = Self.makeHistoryStore()
        transcriptionService = TranscriptionService(modelManager: modelManager)
        fileQueue = FileTranscriptionQueue(transcriber: transcriptionService, history: historyStore)
        modelLibrary = ModelLibraryController.standard(manager: modelManager)

        hudPanel = HUDPanelController(viewModel: hud)
        flow = makeFlow()
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

    /// La fenêtre historique doit toujours pouvoir s'ouvrir : disque, sinon mémoire.
    private static func makeHistoryStore() -> HistoryStore {
        if let store = try? HistoryStore.standard() { return store }
        guard let fallback = try? HistoryStore.inMemory() else {
            preconditionFailure("SQLite indisponible : impossible d'ouvrir l'historique, même en mémoire")
        }
        NSLog("Mintzo: historique sur disque indisponible — repli en mémoire (non persistant)")
        return fallback
    }

    /// Démarre les services réels. Appelé une fois par la scène (label menu bar)
    /// qui fournit les actions d'ouverture de fenêtres. Inactif en mode preview /
    /// snapshots DEBUG : ces harnais simulent le moteur, pas question d'ouvrir le micro.
    func bootstrap(openMainWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        guard !bootstrapped else { return }
        bootstrapped = true
        openMainWindowAction = openMainWindow
        openSettingsWindowAction = openSettings

        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["MINTZO_HUD_PREVIEW"] == "1" || env["MINTZO_HUD_SNAPSHOT_DIR"] != nil {
            return
        }
        #endif

        hud.setLanguage(AppSettings.language)
        wireFlowCallbacks()
        wireFileQueueCallbacks()
        startHotkeyPump()
        observeLanguageChanges()
        subscribeToMenuBarNotifications()
    }

    // MARK: - Flow de dictée

    private func makeFlow() -> DictationFlow {
        var availability = WhisperModelAvailability(manager: modelManager)
        #if DEBUG
        // Smoke test manuel avec whisper-tiny sans télécharger 3 Go.
        if ProcessInfo.processInfo.environment["MINTZO_ALLOW_FALLBACK_MODEL"] == "1" {
            availability.allowAnyInstalledModel = true
        }
        #endif
        return DictationFlow(
            capture: captureService,
            transcriber: transcriptionService,
            inserter: insertionService,
            history: historyStore,
            models: availability
        )
    }

    private func wireFlowCallbacks() {
        flow.makeCorrector = { [weak self] in self?.makeCorrector() }
        flow.autoInsertEnabled = { AppSettings.autoInsert }
        flow.writeClipboard = { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        flow.onPhaseChange = { [weak self] phase in self?.handlePhaseChange(phase) }
        flow.onLevel = { [weak self] rms in self?.hud.ingest(rms: Double(rms)) }
        flow.onOutcome = { [weak self] outcome in self?.handleOutcome(outcome) }

        // Clic capsule pendant l'écoute = stop (§4.1) ; clic erreur = fenêtre principale.
        hud.onStopRequested = { [weak self] in
            guard let self else { return }
            self.flow.handle(.pressEnded, language: self.dictationLanguage)
        }
        hud.onErrorTapped = { [weak self] in self?.openMainWindow() }
    }

    /// Langue de dictée effective (le badge V1 cycle eu → fr ; auto coercé).
    private var dictationLanguage: Language {
        hud.language == .fr ? .french : .basque
    }

    private func handlePhaseChange(_ phase: DictationFlow.Phase) {
        switch phase {
        case .idle:
            removeEscapeMonitors() // l'état final du HUD est posé par l'outcome
        case .listening:
            hud.transition(to: .listening)
            installEscapeMonitors()
        case .transcribing:
            removeEscapeMonitors()
            hud.transition(to: .transcribing)
        case .correcting:
            hud.transition(to: .correcting)
        }
    }

    private func handleOutcome(_ outcome: DictationFlow.Outcome) {
        switch outcome {
        case .inserted:
            hud.transition(to: .success(message: nil))
        case .clipboardOnly:
            // Mode « clipboard seul » (réglage ou repli) : un succès, pas une
            // erreur — message custom « Arbelean — sakatu ⌘V », tenu 1,5 s.
            hud.transition(to: .success(message: AppStrings.clipboardSuccess))
        case .cancelled:
            hud.transition(to: .idle)
        case .failed(let failure):
            switch failure {
            case .modelMissing(let language):
                showHUDError(AppStrings.modelMissing(for: language))
            case .microphonePermissionDenied:
                showHUDError(AppStrings.microphoneNeeded)
            case .captureFailed:
                showHUDError(AppStrings.captureFailed)
            case .transcriptionFailed(let detail):
                NSLog("Mintzo: transcription échouée — %@", detail)
                showHUDError(AppStrings.transcriptionFailed)
            }
        }
    }

    /// La machine HUD n'a pas de transition idle → erreur : les erreurs pré-écoute
    /// (modèle absent, permission) passent par l'état armé le temps d'un tour (§4.3).
    private func showHUDError(_ message: String) {
        if hud.state == .idle {
            hud.transition(to: .listening)
        }
        hud.transition(to: .error(message: message))
    }

    // MARK: - Hotkeys

    private func startHotkeyPump() {
        hotkeyTask?.cancel()
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.hotkeys.start(configuration: self.hotkeyConfiguration())
            for await event in stream {
                await self.handleHotkey(event)
            }
        }
    }

    private func hotkeyConfiguration() -> HotkeyService.Configuration {
        HotkeyService.Configuration(
            activationMode: .pushToTalk,
            fnKeyEnabled: AppSettings.fnKeyEnabled
        )
    }

    /// À appeler quand le réglage « touche Fn » change — remplace la session hotkey.
    func hotkeySettingsChanged() {
        guard bootstrapped else { return }
        startHotkeyPump()
    }

    private func handleHotkey(_ event: HotkeyEvent) async {
        // Première utilisation : prompt micro système AVANT d'ouvrir la session.
        let opensSession = event == .pressBegan || (event == .toggled && flow.phase == .idle)
        if opensSession, permissions.snapshot().microphone == .notDetermined {
            _ = await permissions.requestMicrophoneAccess()
        }
        flow.handle(event, language: dictationLanguage)
    }

    // MARK: - Échap = annulation pendant l'écoute (§4.1)

    private func installEscapeMonitors() {
        guard escapeMonitors.isEmpty else { return }
        // Moniteur global (autres apps au premier plan) : listen-only, exige
        // Accessibility — déjà requise pour l'insertion. Sans elle : pas d'Échap global.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                AppCoordinatorEscapeRelay.shared?.escapePressed()
            }
        }) {
            escapeMonitors.append(global)
        }
        // Moniteur local (Mintzo actif) : consomme la touche.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in
                AppCoordinatorEscapeRelay.shared?.escapePressed()
            }
            return nil
        }) {
            escapeMonitors.append(local)
        }
        AppCoordinatorEscapeRelay.shared = self
    }

    private func removeEscapeMonitors() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors = []
        AppCoordinatorEscapeRelay.shared = nil
    }

    fileprivate func escapePressed() {
        guard flow.phase == .listening else { return }
        flow.cancel()
    }

    // MARK: - Correction (réglage Zuzenketa)

    private func makeCorrector() -> (any DictationCorrecting)? {
        switch AppSettings.correctionMode {
        case .off:
            return nil
        case .latxa:
            let url = modelManager.expectedLocalURL(for: ModelCatalog.latxaCorrection)
            guard FileManager.default.fileExists(atPath: url.path) else {
                NSLog("Mintzo: correction Latxa active mais modèle absent — passe sautée")
                return nil
            }
            if latxaLoader == nil {
                latxaLoader = LatxaEngineLoader(modelURL: url)
            }
            guard let latxaLoader else { return nil }
            return CorrectionService(corrector: LazyLatxaCorrector(loader: latxaLoader))
        case .cloud:
            // BYOK : clé lue dans le trousseau au moment de la requête. Si elle
            // manque, le correcteur lève → CorrectionService retombe sur le brut.
            return CorrectionService(
                corrector: AnthropicCorrector(keyProvider: KeychainKeyStore())
            )
        }
    }

    // MARK: - Fenêtres

    func openMainWindow() {
        openMainWindowAction()
        NSApp.activate()
    }

    func openSettingsWindow() {
        openSettingsWindowAction()
        NSApp.activate()
    }

    // MARK: - Fichiers (drop fenêtre, NSOpenPanel menu bar)

    private func wireFileQueueCallbacks() {
        fileQueue.makeCorrector = { [weak self] in self?.makeCorrector() }
        fileQueue.onFailure = { [weak self] fileName, message in
            NSLog("Mintzo: transcription de « %@ » échouée — %@", fileName, message)
            self?.flashFileError()
        }
    }

    /// Point d'entrée du drop fenêtre entière (§6.3) et du picker menu bar.
    func enqueueFiles(_ urls: [URL]) {
        let language = dictationLanguage
        for url in urls {
            fileQueue.enqueue(url: url, language: language)
        }
    }

    func presentFilePicker() {
        Task { [weak self] in
            NSApp.activate()
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.audio]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            let response = await panel.begin()
            guard response == .OK, let self else { return }
            self.enqueueFiles(panel.urls)
        }
    }

    /// Badge erreur discret sur l'icône menu bar pendant 4 s — pas de fenêtre
    /// imposée, pas de son (calme §1) ; le détail est dans le log.
    private func flashFileError() {
        fileErrorFlash = true
        fileErrorTask?.cancel()
        fileErrorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.fileErrorFlash = false
        }
    }

    // MARK: - Notifications menu bar (popover §5.3 → actions réelles)

    private func subscribeToMenuBarNotifications() {
        subscribe(.mintzoDictateToggleRequested) { coordinator in
            await coordinator.handleHotkey(.toggled)
        }
        subscribe(.mintzoOpenMainWindowRequested) { coordinator in
            coordinator.openMainWindow()
        }
        subscribe(.mintzoTranscribeFileRequested) { coordinator in
            coordinator.presentFilePicker()
        }
        subscribe(.mintzoOpenSettingsRequested) { coordinator in
            coordinator.openSettingsWindow()
        }
    }

    private func subscribe(
        _ name: Notification.Name,
        perform action: @escaping @MainActor (AppCoordinator) async -> Void
    ) {
        notificationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard let self else { return }
                await action(self)
            }
        })
    }

    // MARK: - Langue (§4.4, §5.2)

    func setLanguage(_ newLanguage: HUDLanguage) {
        // Auto masqué V1 : l'auto-détection attend l'exposition de whisper_full_lang_id.
        let effective = newLanguage == .auto ? .eu : newLanguage
        guard effective != hud.language else { return }
        hud.setLanguage(effective)
        AppSettings.language = effective
        // Feedback icône menu bar uniquement hors session (§4.4, §5.2).
        guard !hud.state.isVisible else { return }
        languageFlash = effective
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MenuBarGlyph.languageFlashDuration))
            guard !Task.isCancelled else { return }
            self?.languageFlash = nil
        }
    }

    /// Le badge du HUD (fichier vague 2) cycle encore eu → fr → auto : on coerce
    /// auto → eu ici, et on persiste chaque bascule.
    private func observeLanguageChanges() {
        withObservationTracking {
            _ = hud.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.hud.language == .auto {
                    self.hud.setLanguage(.eu)
                }
                AppSettings.language = self.hud.language
                self.observeLanguageChanges()
            }
        }
    }

    // MARK: - Animation icône menu bar (cadence pilotée modèle, jamais dans le label)

    private func observeIconAnimation() {
        withObservationTracking {
            _ = menuBarState
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

    // MARK: - Mode preview DEBUG (validation visuelle sans moteur audio)

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
            hud.transition(to: .success(message: nil))
        case "success-clipboard":
            hud.transition(to: .transcribing)
            hud.transition(to: .success(message: AppStrings.clipboardSuccess))
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
            hud.transition(to: .success(message: nil))   // auto-dismiss 600 ms → idle
            try? await Task.sleep(for: dwell)
            hud.transition(to: .listening)
            try? await Task.sleep(for: dwell)
            hud.transition(to: .transcribing)
            hud.transition(to: .success(message: AppStrings.clipboardSuccess)) // 1,5 s → idle
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
                hud.transition(to: .success(message: nil))
                try? await Task.sleep(for: .milliseconds(800))
                shoot("success")
                hud.transition(to: .listening)
                hud.transition(to: .transcribing)
                hud.transition(to: .success(message: AppStrings.clipboardSuccess))
                try? await Task.sleep(for: .milliseconds(800))
                shoot("success-clipboard")
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

/// Relais faible vers le coordinator pour les moniteurs clavier NSEvent : leurs
/// closures ne sont pas `@Sendable` et ne peuvent pas capturer une classe MainActor
/// en Swift 6 strict — le relais statique MainActor contourne proprement.
@MainActor
private enum AppCoordinatorEscapeRelay {
    static weak var shared: AppCoordinator?

    static func escapePressed() {
        shared?.escapePressed()
    }
}
