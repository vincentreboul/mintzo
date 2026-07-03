import Foundation
import Observation
import MintzoCore

/// État d'affichage de la bibliothèque de modèles (onglet Ereduak) : installé /
/// téléchargement en cours (fraction) / absent, branché sur `ModelManager`
/// (download AsyncThrowingStream avec SHA256 + install atomique, remove).
@MainActor
@Observable
final class ModelLibraryController {

    struct Entry: Identifiable {
        let model: WhisperModel
        var isInstalled = false
        /// Fraction 0…1 du téléchargement en cours, `nil` sinon.
        var downloadFraction: Double?
        /// Dernière erreur de téléchargement/suppression, effacée au retry.
        var errorMessage: String?

        var id: String { model.id }
    }

    private(set) var entries: [Entry]
    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]

    init(manager: ModelManager, models: [WhisperModel]) {
        self.manager = manager
        self.entries = models.map { Entry(model: $0) }
    }

    /// Modèles whisper du catalogue + Latxa (correction).
    static func standard(manager: ModelManager) -> ModelLibraryController {
        ModelLibraryController(
            manager: manager,
            models: ModelCatalog.all + [ModelCatalog.latxaCorrection]
        )
    }

    /// Re-sonde le disque (ouverture de l'onglet, fin de download/suppression).
    func refresh() async {
        for index in entries.indices {
            let installed = await manager.isInstalled(entries[index].model)
            entries[index].isInstalled = installed
        }
    }

    func download(_ model: WhisperModel) {
        guard downloadTasks[model.id] == nil else { return }
        update(model.id) {
            $0.errorMessage = nil
            $0.downloadFraction = 0
        }
        downloadTasks[model.id] = Task { [weak self, manager] in
            do {
                for try await progress in manager.download(model) {
                    guard !Task.isCancelled else { return }
                    self?.update(model.id) { $0.downloadFraction = progress.fraction }
                }
                self?.update(model.id) {
                    $0.downloadFraction = nil
                    $0.isInstalled = true
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self?.update(model.id) {
                    $0.downloadFraction = nil
                    $0.errorMessage = message
                }
            }
            self?.downloadTasks[model.id] = nil
        }
    }

    func remove(_ model: WhisperModel) async {
        do {
            try await manager.remove(model)
            update(model.id) {
                $0.isInstalled = false
                $0.errorMessage = nil
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            update(model.id) { $0.errorMessage = message }
        }
    }

    private func update(_ id: String, _ mutate: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
    }
}
