import SwiftUI
import UniformTypeIdentifiers
import MintzoCore

/// Scène de la fenêtre principale — design-language.md §6, amendement v1.2 :
/// chrome 100 % natif (fond de fenêtre système, toolbar unifiée, matériaux
/// Tahoe standard) ; l'identité éditoriale vit dans les surfaces de lecture.
/// Défaut 760 × 560 pt, min 560 × 400. Le câblage dans `MintzoApp`
/// arrive en vague 3 : `MainWindowScene(store:queue:onFilesDropped:)`.
struct MainWindowScene: Scene {
    let store: HistoryStore
    var queue: (any QueueDisplaying)?
    var onFilesDropped: ([URL]) -> Void

    init(
        store: HistoryStore,
        queue: (any QueueDisplaying)? = nil,
        onFilesDropped: @escaping ([URL]) -> Void = { _ in }
    ) {
        self.store = store
        self.queue = queue
        self.onFilesDropped = onFilesDropped
    }

    /// Convenience : store standard sur disque, repli mémoire si le disque
    /// est indisponible (la fenêtre doit toujours pouvoir s'ouvrir).
    init() {
        let store = (try? HistoryStore.standard()) ?? (try? HistoryStore.inMemory())
        guard let store else {
            preconditionFailure("SQLite indisponible : impossible d'ouvrir l'historique, même en mémoire")
        }
        self.init(store: store)
    }

    var body: some Scene {
        Window("Mintzo", id: "main") {
            MainWindowRootView(
                store: store,
                queue: queue,
                onFilesDropped: onFilesDropped
            )
            .frame(minWidth: 560, minHeight: 400)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
    }
}

/// Vue racine : liste + zone de drop fenêtre entière (§6.3).
/// Aucun fond custom — la fenêtre hérite du look système ; les contrôles
/// standards sont teintés par l'accent Gorri (§2.1).
struct MainWindowRootView: View {
    let store: HistoryStore
    var queue: (any QueueDisplaying)?
    var onFilesDropped: ([URL]) -> Void = { _ in }
    var initialTranscriptions: [Transcription] = []

    @State private var isDropTargeted = false

    var body: some View {
        HistoryListView(
            store: store,
            queue: queue,
            initialTranscriptions: initialTranscriptions
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                DropOverlayView()
                    .transition(.opacity)
            }
        }
        .animation(MzMotion.enter, value: isDropTargeted)
        .tint(MzColor.gorri)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let loadable = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !loadable.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in loadable {
                let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty {
                onFilesDropped(urls)
            }
        }
        return true
    }
}
