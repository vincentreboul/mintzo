import Foundation
import Observation

// ViewModel du HUD — orchestre la machine d'états pure (HUDStateMachine.swift),
// le timer m:ss, le buffer waveform (une barre / 66 ms) et les auto-transitions
// (succès 600 ms — 1,5 s si message custom —, erreur 4 s).
// Spec : docs/design/design-language.md §4.

@MainActor
@Observable
final class HUDViewModel {

    // MARK: État observable

    private(set) var state: HUDState = .idle
    private(set) var language: HUDLanguage = .eu
    /// Langue résolue par l'auto-détection (badge « a→ » → langue en Gorri).
    private(set) var detectedLanguage: HUDLanguage?
    private(set) var elapsedSeconds: Int = 0
    /// 26 barres visibles + 1 barre entrante (défilement continu du sismographe).
    private(set) var waveform = WaveformBuffer(capacity: MzHUD.waveformBarCount + 1)
    /// Date de la dernière barre ajoutée — la vue en dérive la phase de défilement.
    private(set) var lastBarDate = Date.distantPast
    /// Niveau lissé courant (jauge statique Reduce Motion).
    private(set) var currentLevel: CGFloat = WaveformMapper.minHeight
    /// S'incrémente à chaque bascule de langue — déclenche le pulse du badge (§4.4).
    private(set) var languagePulse = 0
    /// Limite technique de durée (s) — décompte Gorri sur les 30 dernières secondes. nil = illimité.
    var maxDuration: Int?
    /// Tenue du succès à message custom (clipboard seul) : le temps de LIRE le
    /// message, vs `MzMotion.successHoldDuration` (600 ms) pour « Itsatsita ».
    static let customSuccessHoldDuration: TimeInterval = 1.5
    /// Désactivable pour figer succès/erreur (tests, previews). true en production.
    @ObservationIgnored var autoDismissEnabled = true

    var timerDisplay: HUDTimerFormatter.Display {
        HUDTimerFormatter.display(elapsed: elapsedSeconds, maxDuration: maxDuration)
    }

    /// Badge : langue détectée (auto résolu) sinon langue choisie.
    var badgeLanguage: HUDLanguage { language == .auto ? (detectedLanguage ?? .auto) : language }

    // MARK: Callbacks (câblés vague 3 — moteur audio / insertion)

    var onStopRequested: (@MainActor () -> Void)?
    var onErrorTapped: (@MainActor () -> Void)?
    /// Croix d'annulation / Échap : abandon de la session, aucun texte inséré.
    var onCancelRequested: (@MainActor () -> Void)?

    // MARK: Privé

    private var startDate: Date?
    private var currentRMS: Double = 0
    private var tickTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?

    // MARK: Transitions

    /// Transition validée par la machine d'états ; ignore (et signale) les transitions interdites.
    @discardableResult
    func transition(to newState: HUDState) -> Bool {
        guard state.canTransition(to: newState) else { return false }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        state = newState

        switch newState {
        case .listening:
            startDate = Date()
            elapsedSeconds = 0
            currentRMS = 0
            currentLevel = WaveformMapper.minHeight
            waveform.reset()
            detectedLanguage = nil
            startTicking()
        case .success(let message):
            stopTicking()
            if autoDismissEnabled {
                // Message custom (ex. « Arbelean — sakatu ⌘V ») : 1,5 s, le temps
                // de lire — vs 600 ms pour « Itsatsita » (§4.3 état 4).
                let hold = message == nil
                    ? MzMotion.successHoldDuration
                    : Self.customSuccessHoldDuration
                autoDismissTask = autoDismiss(after: hold)
            }
        case .error:
            stopTicking()
            if autoDismissEnabled {
                autoDismissTask = autoDismiss(after: MzMotion.errorHoldDuration)
            }
        case .idle:
            stopTicking()
            startDate = nil
        case .transcribing, .correcting:
            stopTicking()
        }
        return true
    }

    private func autoDismiss(after delay: TimeInterval) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.transition(to: .idle)
        }
    }

    // MARK: Interactions (§4.1, §4.3 état 5)

    /// Clic n'importe où sur la capsule : stop en écoute, dismiss + détail en erreur.
    func capsuleTapped() {
        switch state {
        case .listening:
            onStopRequested?()
        case .error:
            onErrorTapped?()
            transition(to: .idle)
        default:
            break
        }
    }

    /// Clic sur la croix : abandon PROPRE de la session dans tous les états
    /// actifs (écoute, transcription, correction) — contrairement au clic
    /// capsule qui, en écoute, signifie « stop et transcris » (§4.1).
    func cancelTapped() {
        guard state == .listening || state.isProcessing else { return }
        onCancelRequested?()
    }

    /// Clic badge / raccourci ⌃⌥L : cycle eu → fr → auto → eu, pulse unique du badge.
    func cycleLanguage() {
        language = language.next
        detectedLanguage = nil
        languagePulse += 1
    }

    func setLanguage(_ newLanguage: HUDLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        detectedLanguage = nil
        languagePulse += 1
    }

    /// Auto-détection résolue (vague 3 : whisper) — le badge passe de « a→ » à la langue en Gorri.
    func setDetectedLanguage(_ detected: HUDLanguage) {
        guard language == .auto, detected != .auto else { return }
        detectedLanguage = detected
    }

    // MARK: Niveau audio

    /// Niveau RMS entrant (0…1), fourni par le moteur audio (vague 3) ou la simulation DEBUG.
    /// Consommé par le tick 66 ms — la forme dessinée est la voix, jamais du décoratif.
    func ingest(rms: Double) {
        currentRMS = max(0, rms)
    }

    // MARK: Tick 66 ms (une barre entre à droite, §4.2)

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                next = next.advanced(by: .milliseconds(66))
                try? await clock.sleep(until: next)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard state == .listening else { return }
        waveform.append(rms: currentRMS)
        currentLevel = waveform.bars.last ?? WaveformMapper.minHeight
        lastBarDate = Date()
        if let startDate {
            elapsedSeconds = Int(Date().timeIntervalSince(startDate))
        }
    }
}
