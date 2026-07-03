import Foundation
import MintzoCore

// Relance d'une entrée d'historique sur son audio conservé — logique PURE
// (Foundation + MintzoCore), compilée aussi dans MintzoCoreTests (symlink
// Tests/MintzoCoreTests/ReplayService.swift) pour être testée avec un
// transcripteur stub, sans moteur whisper.

/// Repasse l'audio conservé d'une transcription dans le pipeline complet —
/// transcription → correction (optionnelle, bornée) → post-pass vocabulaire →
/// post-processing — et met à jour l'entrée EN PLACE (brut + corrigé + langue).
///
/// RÉUTILISE le chemin de la dictée (`DictationFlow.correct`,
/// `VocabularyPostPass`, `DictationFlow.postProcess`) : pas de second pipeline.
/// Date, durée, source et audio de l'entrée sont conservés.
@MainActor
final class ReplayService {

    /// Raison d'échec d'une relance — la vue la traduit en microcopy sobre.
    enum Failure: Error, Equatable {
        /// L'entrée n'a pas d'audio conservé (antérieure à la v2).
        case noAudio
        /// Le WAV conservé est introuvable ou illisible.
        case audioUnreadable
        /// Aucun modèle whisper pour la langue demandée.
        case modelMissing
        /// Le moteur n'a reconnu aucun texte.
        case noText
        /// La transcription a échoué (détail technique au log).
        case transcriptionFailed
        /// L'écriture en base a échoué.
        case saveFailed
    }

    private let transcriber: any DictationTranscribing
    private let history: HistoryStore

    /// Correcteur du moment (`nil` = passe désactivée) — lu au moment de la relance.
    var makeCorrector: @MainActor () -> (any DictationCorrecting)? = { nil }
    /// Remplacements du dictionnaire — même post-pass déterministe que la dictée.
    var vocabularyReplacements: @MainActor () -> [VocabularyReplacement] = { [] }
    /// Langue de repli si la relance « auto » ne détermine rien.
    var fallbackLanguage: @MainActor () -> Language = { .basque }
    /// Budget de correction — celui des fichiers (textes potentiellement longs).
    var correctionTimeout: Duration = .seconds(60)
    /// Décodage du WAV conservé (injectable en test).
    var decode: @Sendable (URL) throws -> [Float] = { try AudioFileDecoder.decode(url: $0) }

    /// Service courant de l'app, posé par l'AppCoordinator. La scène de la
    /// fenêtre principale est construite dans MintzoApp, hors du périmètre du
    /// coordinator — le détail lit ici plutôt que d'enfiler la dépendance à
    /// travers toute la hiérarchie de vues.
    static weak var shared: ReplayService?

    init(transcriber: any DictationTranscribing, history: HistoryStore) {
        self.transcriber = transcriber
        self.history = history
    }

    /// Relance la génération de `transcription` sur son audio conservé.
    ///
    /// - Parameter language: langue imposée (eu/fr), ou nil = auto — la
    ///   détection est celle du service de transcription (whisper-tiny).
    /// - Returns: l'entrée mise à jour (mêmes id/date/durée/source/audio).
    func replay(_ transcription: Transcription, language: Language?) async -> Result<Transcription, Failure> {
        guard let id = transcription.id, let audioPath = transcription.audioPath else {
            return .failure(.noAudio)
        }

        // Décodage hors main actor — le WAV conservé repasse par le même
        // décodeur que les fichiers importés.
        let decode = self.decode
        let url = URL(fileURLWithPath: audioPath)
        let samples: [Float]
        do {
            samples = try await Task.detached(priority: .userInitiated) { try decode(url) }.value
        } catch {
            NSLog("Mintzo: relance — audio illisible (%@) : %@", audioPath, error.localizedDescription)
            return .failure(.audioUnreadable)
        }

        let result: TranscriptionResult
        do {
            result = try await transcriber.transcribe(samples: samples, language: language?.rawValue)
        } catch TranscriptionServiceError.noModelInstalled {
            return .failure(.modelMissing)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("Mintzo: relance — transcription échouée : %@", detail)
            return .failure(.transcriptionFailed)
        }

        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .failure(.noText) }

        // Langue effective : imposée, sinon détectée par le service, sinon
        // celle que l'entrée portait déjà, sinon le repli utilisateur.
        let effective = language
            ?? result.language.flatMap(Language.init(rawValue:))
            ?? Language(rawValue: transcription.langue.rawValue)
            ?? fallbackLanguage()

        // Le MÊME pipeline aval que la dictée et les fichiers.
        var finalText = raw
        if let corrector = makeCorrector() {
            finalText = await DictationFlow.correct(
                raw, language: effective, corrector: corrector, timeout: correctionTimeout
            )
        }
        finalText = VocabularyPostPass.apply(finalText, replacements: vocabularyReplacements())
        finalText = DictationFlow.postProcess(finalText)

        var updated = transcription
        updated.texteBrut = raw
        updated.texteCorrige = finalText != raw ? finalText : nil
        updated.langue = effective == .basque ? .eu : .fr
        do {
            try history.update(
                id: id,
                texteBrut: updated.texteBrut,
                texteCorrige: updated.texteCorrige,
                langue: updated.langue
            )
        } catch {
            NSLog("Mintzo: relance — écriture historique échouée : %@", error.localizedDescription)
            return .failure(.saveFailed)
        }
        return .success(updated)
    }
}
