import Foundation
import AVFoundation
import Observation
import MintzoCore

/// File de transcription de fichiers : consomme `TranscriptionService.enqueue`
/// (FIFO strict côté service) et projette les événements dans les `QueueItem`
/// affichés en tête de la fenêtre principale (§6.3). À la fin d'un fichier :
/// correction (selon réglage, budget élargi) → post-processing → historique
/// (source `.fichier`). Pas d'ouverture de fenêtre imposée à la fin — calme ;
/// l'échec se signale par le badge menu bar via `onFailure`.
@MainActor
@Observable
final class FileTranscriptionQueue: QueueDisplaying {

    private(set) var items: [QueueItem] = []

    /// Au moins un fichier en attente ou en cours (icône menu bar → processing).
    var isWorking: Bool { !items.isEmpty }

    /// Budget de correction par fichier — plus large qu'en dictée (textes longs),
    /// borné quand même : au-delà, texte brut.
    var correctionTimeout: Duration = .seconds(60)

    @ObservationIgnored private let transcriber: TranscriptionService
    @ObservationIgnored private let history: any DictationHistoryWriting

    /// Correcteur du moment (`nil` = passe désactivée) — lu au moment du fichier.
    @ObservationIgnored var makeCorrector: @MainActor () -> (any DictationCorrecting)? = { nil }
    /// Échec d'un fichier : (nom, message) — le coordinator badge le menu bar.
    @ObservationIgnored var onFailure: @MainActor (String, String) -> Void = { _, _ in }

    init(transcriber: TranscriptionService, history: any DictationHistoryWriting) {
        self.transcriber = transcriber
        self.history = history
    }

    // MARK: - Enfilage

    func enqueue(url: URL, language: Language) {
        let item = QueueItem(
            nomFichier: url.lastPathComponent,
            progress: nil, // « zain »
            duree: nil,
            langue: language == .basque ? .eu : .fr
        )
        items.append(item)
        probeDuration(of: url, itemID: item.id)

        Task { [weak self] in
            guard let self else { return }
            let events = await self.transcriber.enqueue(url: url, language: language.rawValue)
            for await event in events {
                await self.handle(event, itemID: item.id, url: url, language: language)
            }
        }
    }

    // MARK: - Événements du job

    private func handle(
        _ event: TranscriptionJobEvent,
        itemID: UUID,
        url: URL,
        language: Language
    ) async {
        switch event {
        case .queued:
            break // progress nil = « zain » (§6.3)
        case .started:
            update(itemID) { $0.progress = 0.05 }
        case .progress(let phase):
            // Pas de progression fine exposée par whisper.cpp : fractions par
            // étape réelle du pipeline (décodage → chargement modèle → calcul).
            let fraction: Double = switch phase {
            case .decodingAudio: 0.15
            case .loadingModel: 0.30
            case .transcribing: 0.60
            }
            update(itemID) { $0.progress = fraction }
        case .done(let result):
            update(itemID) { $0.progress = 1.0 }
            await finalize(result, url: url, language: language)
            removeSoon(itemID) // laisse la barre pleine se voir (~0,6 s)
        case .failed(let message):
            remove(itemID)
            onFailure(url.lastPathComponent, message)
        }
    }

    /// Correction (optionnelle, bornée) → post-processing → historique.
    private func finalize(_ result: TranscriptionResult, url: URL, language: Language) async {
        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            onFailure(url.lastPathComponent, "aucun texte reconnu")
            return
        }

        var finalText = raw
        if let corrector = makeCorrector() {
            finalText = await DictationFlow.correct(
                raw, language: language, corrector: corrector, timeout: correctionTimeout
            )
        }
        finalText = DictationFlow.postProcess(finalText)

        let record = Transcription(
            texteBrut: raw,
            texteCorrige: finalText != raw ? finalText : nil,
            dureeAudio: result.audioDuration,
            langue: language == .basque ? .eu : .fr,
            source: .fichier,
            nomFichier: url.lastPathComponent
        )
        do {
            try history.insert(record)
        } catch {
            // Le texte ne doit pas disparaître en silence : signalé comme échec.
            NSLog("Mintzo: écriture historique (fichier) échouée — %@", error.localizedDescription)
            onFailure(url.lastPathComponent, "écriture historique échouée")
        }
    }

    // MARK: - Items

    private func update(_ id: UUID, _ mutate: (inout QueueItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    private func removeSoon(_ id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.remove(id)
        }
    }

    /// Durée audio du fichier (lecture d'en-tête, hors main actor) — best effort.
    private func probeDuration(of url: URL, itemID: UUID) {
        Task.detached(priority: .utility) { [weak self] in
            guard let file = try? AVAudioFile(forReading: url) else { return }
            let rate = file.processingFormat.sampleRate
            guard rate > 0 else { return }
            let duration = Double(file.length) / rate
            await self?.setDuration(duration, for: itemID)
        }
    }

    private func setDuration(_ duration: TimeInterval, for id: UUID) {
        update(id) { $0.duree = duration }
    }
}
