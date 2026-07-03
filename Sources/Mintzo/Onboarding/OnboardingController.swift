import SwiftUI
import Observation
import MintzoCore

/// État observable de la fenêtre d'onboarding : navigation (`OnboardingJourney`),
/// permissions LIVE (flux de polling de `PermissionsService`), téléchargement du
/// modèle (le `ModelLibraryController` PARTAGÉ du coordinator — un download lancé
/// ici survit à la fermeture de la fenêtre et reste visible dans Réglages >
/// Ereduak), et dictée d'essai (déclenchée par le chemin public du popover,
/// notification `.mintzoDictateToggleRequested`).
@MainActor
@Observable
final class OnboardingController {

    // MARK: Navigation

    private(set) var journey = OnboardingJourney()

    // MARK: Permissions (écran 2)

    private(set) var permissions: PermissionsSnapshot

    // MARK: Modèle (écran 3)

    /// Langue du MODÈLE à télécharger (écran 3) — présélection : eu si le
    /// système est en eu, fr si le système est en fr, sinon eu (Mintzo est
    /// d'abord basque). Ne touche PAS au mode de langue de l'app (auto par
    /// défaut) : elle alimente la langue de REPLI du mode auto.
    ///
    /// Régression historique : `init` écrivait `coordinator.language` — or
    /// SwiftUI évalue la closure de contenu de `Window` à CHAQUE construction
    /// du scene graph, même fenêtre jamais présentée (gate fermé). Résultat :
    /// chaque lancement écrasait la langue choisie par la langue système.
    /// Invariant : la construction de ce contrôleur est SANS effet de bord.
    var selectedLanguage: HUDLanguage {
        didSet {
            guard selectedLanguage != oldValue else { return }
            AppSettings.fallbackLanguage = selectedLanguage == .fr ? .french : .basque
        }
    }

    /// Texte de la zone d'essai — possédé ici (et pas en @State) pour que le
    /// harnais de snapshots QA puisse peupler la zone.
    var trialText = ""

    @ObservationIgnored private let coordinator: AppCoordinator
    @ObservationIgnored private var permissionsTask: Task<Void, Never>?

    #if DEBUG
    /// Surcharges du harnais de snapshots QA (états permissions/download figés).
    /// OBSERVABLES (pas `@ObservationIgnored`) : le harnais capture la fenêtre
    /// LIVE — la mutation d'une surcharge doit invalider la vue, sinon la
    /// capture montre l'état précédent (bug R1 : eredua-errorea/prest figés
    /// sur l'état deskargatzen).
    var qaModelRowOverride: ModelRowState?
    var qaTrialPhaseOverride: OnboardingTrial.Phase?
    #endif

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.permissions = coordinator.permissions.snapshot()
        // Présélection locale UNIQUEMENT — aucun effet de bord ici (cf. doc
        // de `selectedLanguage` : cet init s'exécute à chaque scene graph).
        self.selectedLanguage = MzStrings.ui == .fr ? .fr : .eu
    }

    // MARK: - Cycle de vie

    /// Démarre le suivi LIVE des permissions (polling 2 s existant, ralenti ×5
    /// quand tout est accordé). À appeler à l'apparition de la fenêtre.
    func start() {
        guard permissionsTask == nil else { return }
        let service = coordinator.permissions
        permissionsTask = Task { [weak self] in
            for await snapshot in service.changes() {
                guard let self, !Task.isCancelled else { return }
                self.permissions = snapshot
            }
        }
    }

    /// Arrête le polling (fermeture de la fenêtre).
    func stop() {
        permissionsTask?.cancel()
        permissionsTask = nil
    }

    // MARK: - Navigation
    // Mutations pures — l'animation (morph, ou crossfade si Reduce Motion) est
    // choisie par la vue, seule à connaître l'environnement d'accessibilité.

    func advance() {
        journey.advance()
    }

    func goBack() {
        journey.goBack()
    }

    /// « Amaitu » : marque l'onboarding terminé — la fenêtre ne se représentera
    /// plus au lancement. La fermeture est du ressort de la vue (dismiss).
    /// Le choix de modèle (même jamais touché : présélection système) devient
    /// la langue de repli du mode auto — action utilisateur explicite, ici oui.
    func finish() {
        AppSettings.fallbackLanguage = selectedLanguage == .fr ? .french : .basque
        OnboardingGate.markCompleted()
    }

    // MARK: - Permissions (écran 2)

    /// Prompt système micro (si jamais demandée) ; le flux `changes()` reflète
    /// le résultat.
    func requestMicrophone() {
        Task { _ = await coordinator.permissions.requestMicrophoneAccess() }
    }

    func openMicrophoneSettings() {
        coordinator.permissions.openMicrophoneSettings()
    }

    /// Accessibilité : enregistre l'app dans la liste TCC (prompt système) ET
    /// ouvre le panneau Réglages — un seul clic mène au bon endroit, l'octroi
    /// effectif est détecté par le polling.
    func requestAccessibility() {
        coordinator.permissions.requestAccessibilityAccess()
        coordinator.permissions.openAccessibilitySettings()
    }

    // MARK: - Modèle (écran 3)

    /// État d'affichage de la rangée modèle — découplé de `ModelLibraryController`
    /// pour rester rendable avec des états figés (QA).
    struct ModelRowState: Equatable {
        var model: WhisperModel
        var isInstalled = false
        var downloadFraction: Double?
        var downloadedBytes: Int64?
        var errorMessage: String?
    }

    var selectedModel: WhisperModel {
        selectedLanguage == .fr ? ModelCatalog.whisperFR : ModelCatalog.whisperEU
    }

    var modelRow: ModelRowState {
        #if DEBUG
        if let qaModelRowOverride { return qaModelRowOverride }
        #endif
        let model = selectedModel
        guard let entry = coordinator.modelLibrary.entries.first(where: { $0.id == model.id }) else {
            return ModelRowState(model: model)
        }
        return ModelRowState(
            model: model,
            isInstalled: entry.isInstalled,
            downloadFraction: entry.downloadFraction,
            downloadedBytes: entry.downloadFraction.map {
                Int64(Double(model.sizeBytes) * $0)
            },
            errorMessage: entry.errorMessage
        )
    }

    func downloadSelectedModel() {
        coordinator.modelLibrary.download(selectedModel)
    }

    /// Re-sonde le disque (ouverture de l'écran 3).
    func refreshModels() async {
        await coordinator.modelLibrary.refresh()
    }

    // MARK: - Dictée d'essai (écran 3)

    var trialAvailability: OnboardingTrial.Availability {
        OnboardingTrial.availability(
            microphone: permissions.microphone,
            modelInstalled: modelRow.isInstalled
        )
    }

    var trialPhase: OnboardingTrial.Phase {
        #if DEBUG
        if let qaTrialPhaseOverride { return qaTrialPhaseOverride }
        #endif
        return OnboardingTrial.phase(for: coordinator.hud.state)
    }

    /// Une vraie dictée, par le chemin public du popover : le coordinator gère
    /// le prompt micro au vol, le HUD, l'insertion (champ local focus = cible ;
    /// sans Accessibilité le texte reste sur le clipboard, le HUD le dit).
    func toggleTrialDictation() {
        NotificationCenter.default.post(name: .mintzoDictateToggleRequested, object: nil)
    }

    // MARK: - Harnais QA (snapshots)

    #if DEBUG
    /// Fige un état complet pour une capture de la fenêtre live (OnboardingSnapshots).
    func qaConfigure(
        screen: OnboardingScreen,
        microphone: PermissionStatus,
        accessibility: PermissionStatus,
        modelRow: ModelRowState? = nil,
        trialPhase: OnboardingTrial.Phase? = nil,
        trialText: String = ""
    ) {
        journey = OnboardingJourney()
        while journey.screen != screen { journey.advance() }
        permissions = PermissionsSnapshot(microphone: microphone, accessibility: accessibility)
        // Cohérence picker ↔ carte : la surcharge fixe le modèle affiché, la
        // langue sélectionnée doit raconter la même histoire.
        if let modelRow {
            selectedLanguage = modelRow.model.id == ModelCatalog.whisperFR.id ? .fr : .eu
        }
        qaModelRowOverride = modelRow
        qaTrialPhaseOverride = trialPhase
        self.trialText = trialText
    }
    #endif
}
