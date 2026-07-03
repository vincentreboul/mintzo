import SwiftUI
import MintzoCore

/// Fenêtre principale — le « journal composé » (design-language.md §6).
/// Une seule colonne : file d'attente épinglée (si active), sections par jour
/// (gaur / atzo / dates), cellules serif dans des conteneurs `MzSurface`.
struct HistoryListView: View {

    enum SourceFilter: Hashable, CaseIterable {
        case dena, diktaketak, fitxategiak
    }

    let store: HistoryStore
    private let queue: (any QueueDisplaying)?
    private let onOpenDetail: ((Transcription) -> Void)?

    @State private var transcriptions: [Transcription]
    @State private var searchText = ""
    @State private var searchResults: [Transcription] = []
    @State private var filter: SourceFilter = .dena
    @State private var selection: Transcription?

    /// - Parameters:
    ///   - store: store d'historique (observé en continu).
    ///   - queue: source d'affichage de la file d'attente (câblage vague 3).
    ///   - initialTranscriptions: contenu affiché avant la première émission
    ///     de l'observation (previews, rendus QA).
    init(
        store: HistoryStore,
        queue: (any QueueDisplaying)? = nil,
        initialTranscriptions: [Transcription] = [],
        onOpenDetail: ((Transcription) -> Void)? = nil
    ) {
        self.store = store
        self.queue = queue
        self.onOpenDetail = onOpenDetail
        _transcriptions = State(initialValue: initialTranscriptions)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MzColor.paper)
                .navigationTitle("Mintzo")
                .navigationDestination(item: $selection) { transcription in
                    TranscriptionDetailView(transcription: transcription)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        filterPicker
                    }
                }
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: Text(MzL10n.searchPrompt)
                )
        }
        .task { await observeStore() }
        .task(id: searchText) { runSearch() }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchContent
        } else if visibleTranscriptions.isEmpty && queueItems.isEmpty {
            EmptyHistoryView()
        } else {
            listContent
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !queueItems.isEmpty {
                    QueueSectionView(items: queueItems)
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(MzL10n.sectionTitle(for: section.day))
                            .font(MzFont.sectionHeader)
                            .tracking(MzFont.sectionHeaderTracking)
                            .foregroundStyle(MzColor.inkSecondary)
                        cellGroup(section.items)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if visibleSearchResults.isEmpty {
            Text(MzL10n.searchNoResults)
                .font(.system(size: 13))
                .foregroundStyle(MzColor.inkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    // Résultats classés bm25 : un seul groupe, pas de sections par jour.
                    cellGroup(visibleSearchResults, highlightTerms: searchTerms)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
        }
    }

    /// Groupe de cellules dans un conteneur `MzSurface` rayon 10, hairline,
    /// séparateurs inset 14 entre cellules seulement (§6.3).
    private func cellGroup(
        _ items: [Transcription],
        highlightTerms: [String] = []
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, transcription in
                if index > 0 {
                    MzHairlineDivider()
                }
                HistoryCellView(
                    transcription: transcription,
                    highlightTerms: highlightTerms
                ) {
                    if let onOpenDetail {
                        onOpenDetail(transcription)
                    } else {
                        selection = transcription
                    }
                }
            }
        }
        .background(MzColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(MzColor.hairline, lineWidth: 0.5)
        }
    }

    private var filterPicker: some View {
        Picker("", selection: $filter) {
            Text(MzL10n.filterDena).tag(SourceFilter.dena)
            Text(MzL10n.filterDiktaketak).tag(SourceFilter.diktaketak)
            Text(MzL10n.filterFitxategiak).tag(SourceFilter.fitxategiak)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: - Données

    private var queueItems: [QueueItem] { queue?.items ?? [] }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchTerms: [String] {
        trimmedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var visibleTranscriptions: [Transcription] {
        applyFilter(to: transcriptions)
    }

    private var visibleSearchResults: [Transcription] {
        applyFilter(to: searchResults)
    }

    private func applyFilter(to items: [Transcription]) -> [Transcription] {
        switch filter {
        case .dena: items
        case .diktaketak: items.filter { $0.source == .dictee }
        case .fitxategiak: items.filter { $0.source == .fichier }
        }
    }

    private struct DaySection: Identifiable {
        let day: Date
        let items: [Transcription]
        var id: Date { day }
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTranscriptions) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(day: day, items: grouped[day, default: []].sorted { $0.date > $1.date })
        }
    }

    private func observeStore() async {
        do {
            for try await rows in store.observe() {
                withAnimation(MzMotion.settle) { transcriptions = rows }
            }
        } catch {
            // L'observation ne doit jamais faire tomber la fenêtre ;
            // l'état affiché reste le dernier connu.
        }
    }

    private func runSearch() {
        let query = trimmedQuery
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchResults = (try? store.search(query: query)) ?? []
    }
}

/// État vide première ouverture (§6.3) : moment éditorial, centré optique 45 %.
/// Aucune illustration.
private struct EmptyHistoryView: View {
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                Text(MzL10n.emptyTitle)
                    .font(MzFont.emptyStateTitle)
                    .lineSpacing(8)
                    .foregroundStyle(MzColor.ink)
                Text(MzL10n.emptySubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(MzColor.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(width: geo.size.width)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.45)
        }
    }
}
