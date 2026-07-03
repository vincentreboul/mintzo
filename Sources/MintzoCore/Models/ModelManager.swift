import CryptoKit
import Foundation

/// Erreurs du gestionnaire de modèles.
public enum ModelManagerError: Error, LocalizedError, Sendable {
    /// Échec réseau (connexion coupée, timeout, annulation…).
    case networkFailure(modelID: String, detail: String)
    /// Le serveur a répondu avec un statut HTTP d'erreur.
    case httpError(modelID: String, statusCode: Int)
    /// Le SHA256 du fichier téléchargé ne correspond pas au catalogue.
    case checksumMismatch(modelID: String, expected: String, actual: String)
    /// Espace disque insuffisant pour télécharger le modèle.
    case insufficientDiskSpace(modelID: String, requiredBytes: Int64, availableBytes: Int64)
    /// Erreur du système de fichiers (déplacement, suppression, création de dossier).
    case fileSystemError(detail: String)

    public var errorDescription: String? {
        switch self {
        case .networkFailure(let id, let detail):
            return "Téléchargement de \(id) échoué (réseau) : \(detail)"
        case .httpError(let id, let statusCode):
            return "Téléchargement de \(id) refusé par le serveur : HTTP \(statusCode)"
        case .checksumMismatch(let id, let expected, let actual):
            return "Intégrité de \(id) invalide : SHA256 attendu \(expected), obtenu \(actual)"
        case .insufficientDiskSpace(let id, let required, let available):
            return "Espace disque insuffisant pour \(id) : requis \(required) octets, disponible \(available)"
        case .fileSystemError(let detail):
            return "Erreur disque : \(detail)"
        }
    }
}

/// Progression d'un téléchargement de modèle.
public struct DownloadProgress: Sendable, Equatable {
    public let bytesReceived: Int64
    public let totalBytes: Int64

    /// Fraction [0, 1] ; 0 si la taille totale est inconnue.
    public var fraction: Double {
        totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0
    }
}

/// Gestionnaire des modèles Whisper sur disque : inventaire, téléchargement
/// avec vérification d'intégrité, suppression.
///
/// Répertoire par défaut : `~/Library/Application Support/Mintzo/Models`
/// (paramétrable pour les tests). Écriture atomique : le fichier n'apparaît
/// sous son nom final qu'après vérification du SHA256 — un download interrompu
/// ou corrompu ne laisse jamais un modèle invalide en place.
public actor ModelManager {

    public let modelsDirectory: URL

    /// - Parameter modelsDirectory: répertoire des modèles ; par défaut
    ///   `~/Library/Application Support/Mintzo/Models`.
    public init(modelsDirectory: URL? = nil) {
        if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]
            self.modelsDirectory = appSupport
                .appendingPathComponent("Mintzo", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
    }

    // MARK: - Inventaire

    /// Chemin où le modèle est (ou serait) installé.
    public nonisolated func expectedLocalURL(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    /// Un modèle est installé si le fichier existe ET a exactement la taille
    /// du catalogue (garde-fou léger contre les fichiers tronqués).
    public func isInstalled(_ model: WhisperModel) -> Bool {
        let url = expectedLocalURL(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return false
        }
        return size == model.sizeBytes
    }

    /// Modèles du catalogue effectivement installés.
    public func installedModels() -> [WhisperModel] {
        ModelCatalog.all.filter { isInstalled($0) }
    }

    /// URL locale du modèle, ou `nil` s'il n'est pas installé.
    public func localURL(for model: WhisperModel) -> URL? {
        isInstalled(model) ? expectedLocalURL(for: model) : nil
    }

    /// Supprime le modèle du disque (idempotent : silencieux s'il est absent).
    public func remove(_ model: WhisperModel) throws {
        let url = expectedLocalURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw ModelManagerError.fileSystemError(
                detail: "suppression de \(url.path) : \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Téléchargement

    /// Télécharge et installe un modèle.
    ///
    /// Flux de progression : émet des `DownloadProgress`, se termine sans valeur
    /// quand le modèle est installé et vérifié, ou se termine en erreur typée
    /// (`ModelManagerError`). Note : `AsyncThrowingStream` plutôt que
    /// l'`AsyncStream` du brief pour propager les erreurs typées demandées.
    /// Annulation : abandonner l'itération annule le téléchargement.
    public nonisolated func download(_ model: WhisperModel) -> AsyncThrowingStream<DownloadProgress, Error> {
        let directory = modelsDirectory
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.performDownload(of: model, into: directory) { progress in
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pipeline complet : pré-check disque → download → SHA256 → move atomique.
    private static func performDownload(
        of model: WhisperModel,
        into directory: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ModelManagerError.fileSystemError(
                detail: "création de \(directory.path) : \(error.localizedDescription)"
            )
        }

        // Pré-check espace disque.
        if let available = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage, available < model.sizeBytes {
            throw ModelManagerError.insufficientDiskSpace(
                modelID: model.id, requiredBytes: model.sizeBytes, availableBytes: available
            )
        }

        // Staging DANS le répertoire cible : même volume ⇒ rename final atomique.
        let stagingURL = directory.appendingPathComponent(".download-\(model.id)-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try await downloadFile(of: model, to: stagingURL, onProgress: onProgress)
        try Task.checkCancellation()

        // Vérification d'intégrité.
        let actualSHA = try sha256Hex(of: stagingURL, modelID: model.id)
        guard actualSHA == model.sha256.lowercased() else {
            throw ModelManagerError.checksumMismatch(
                modelID: model.id, expected: model.sha256, actual: actualSHA
            )
        }

        // Installation atomique (remplace une éventuelle version précédente).
        let destination = directory.appendingPathComponent(model.fileName)
        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: stagingURL)
        } catch {
            throw ModelManagerError.fileSystemError(
                detail: "installation de \(model.fileName) : \(error.localizedDescription)"
            )
        }
    }

    /// Téléchargement URLSession vers `stagingURL`, progression via delegate.
    private static func downloadFile(
        of model: WhisperModel,
        to stagingURL: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        let delegate = DownloadDelegateBox(
            modelID: model.id,
            expectedBytes: model.sizeBytes,
            stagingURL: stagingURL,
            onProgress: onProgress
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.start(continuation: continuation)
                session.downloadTask(with: model.downloadURL).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    /// SHA256 hex en streaming (blocs de 8 Mo) — mémoire constante, adapté aux
    /// modèles de plusieurs Go.
    private static func sha256Hex(of url: URL, modelID: String) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ModelManagerError.fileSystemError(
                detail: "lecture de \(url.lastPathComponent) : \(error.localizedDescription)"
            )
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool {
                try handle.read(upToCount: 8 * 1024 * 1024)
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Delegate URLSession d'un téléchargement unique.
///
/// `@unchecked Sendable` justifié : tout l'état mutable est protégé par `lock`,
/// et la continuation n'est reprise qu'une seule fois (flag `finished`).
private final class DownloadDelegateBox: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let modelID: String
    private let expectedBytes: Int64
    private let stagingURL: URL
    private let onProgress: @Sendable (DownloadProgress) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    init(
        modelID: String,
        expectedBytes: Int64,
        stagingURL: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) {
        self.modelID = modelID
        self.expectedBytes = expectedBytes
        self.stagingURL = stagingURL
        self.onProgress = onProgress
    }

    func start(continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    /// Reprend la continuation exactement une fois.
    private func resume(with result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        onProgress(DownloadProgress(bytesReceived: totalBytesWritten, totalBytes: total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Un 404/500 « réussit » le download de son corps : vérifier le statut HTTP.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            resume(with: .failure(ModelManagerError.httpError(modelID: modelID, statusCode: http.statusCode)))
            return
        }
        // `location` est supprimé au retour de ce callback : déplacement SYNCHRONE.
        do {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try FileManager.default.removeItem(at: stagingURL)
            }
            try FileManager.default.moveItem(at: location, to: stagingURL)
            resume(with: .success(()))
        } catch {
            resume(with: .failure(ModelManagerError.fileSystemError(
                detail: "déplacement du téléchargement : \(error.localizedDescription)"
            )))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            resume(with: .failure(ModelManagerError.networkFailure(
                modelID: modelID, detail: error.localizedDescription
            )))
        }
        // error == nil : didFinishDownloadingTo a déjà repris la continuation.
    }
}
