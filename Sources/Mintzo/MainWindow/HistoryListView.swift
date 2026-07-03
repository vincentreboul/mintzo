import SwiftUI
import MintzoCore

/// Fenêtre principale — chrome 100 % natif macOS (amendement v1.2 du
/// design language) : `List` native `.inset` avec sections par jour,
/// toolbar unifiée (titre, filtre segmented, `.searchable`), fonds système.
/// L'identité éditoriale (« journal composé », §6) vit DANS les rangées :
/// extrait serif New York 15/22, ligne méta monospacedDigit, tag langue
/// Gorri 12 %, en-têtes de section en petites capitales sobres.
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

    /// - Parameters:
    ///   - store: store d'historique (observé en continu).
    ///   - queue: source d'affichage de la file d'attente (câblage vague 3).
    ///   - initialTranscriptions: contenu affiché avant la première émission
    ///     de l'observation (previews, harnais QA).
    ///   - onOpenDetail: remplace la navigation push (câblage externe) ;
    ///     nil = `NavigationLink` natif vers le détail.
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
                .navigationTitle("Mintzo")
                .navigationDestination(for: Transcription.self) { transcription in
                    TranscriptionDetailView(transcription: transcription)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        filterPicker
                    }
                    // Départ de dictée SANS raccourci ni Accessibilité (micro seul) —
                    // utile pour tester et comme chemin de secours permanent.
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            NotificationCenter.default.post(name: .mintzoDictateToggleRequested, object: nil)
                        } label: {
                            Label(MzL10n.dictateNow, systemImage: "mic")
                        }
                        .help(MzL10n.dictateNowHelp)
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
            emptyState
        } else {
            historyList
        }
    }

    /// La liste native : file d'attente épinglée en tête (si active),
    /// puis sections par jour.
    private var historyList: some View {
        List {
            if !queueItems.isEmpty {
                Section {
                    ForEach(queueItems) { item in
                        QueueRowView(item: item)
                    }
                } header: {
                    sectionHeader(MzL10n.queueHeader(count: queueItems.count))
                }
            }
            ForEach(sections) { section in
                Section {
                    rows(section.items)
                } header: {
                    sectionHeader(MzL10n.sectionTitle(for: section.day))
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var searchContent: some View {
        if visibleSearchResults.isEmpty {
            ContentUnavailableView {
                Label(MzL10n.searchNoResults, systemImage: "magnifyingglass")
            }
        } else {
            // Résultats classés bm25 : un seul groupe, pas de sections par jour.
            List {
                rows(visibleSearchResults, highlightTerms: searchTerms)
            }
            .listStyle(.inset)
        }
    }

    /// État vide première ouverture — habit natif (`ContentUnavailableView`),
    /// geste éditorial conservé : la phrase canonique en serif (§6.3).
    private var emptyState: some View {
        ContentUnavailableView {
            Label(MzL10n.emptyHeadline, systemImage: "waveform")
        } description: {
            VStack(spacing: 8) {
                Text(MzL10n.emptyTitle)
                    .font(MzFont.historyExcerpt)
                    .foregroundStyle(.primary)
                Text(MzL10n.emptySubtitle)
            }
            .padding(.top, 2)
        } actions: {
            Button {
                NotificationCenter.default.post(name: .mintzoDictateToggleRequested, object: nil)
            } label: {
                Label(MzL10n.dictateNow, systemImage: "mic")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// Rangées d'historique : `NavigationLink` natif (sélection, focus,
    /// accessibilité système) — ou action externe si fournie.
    @ViewBuilder
    private func rows(_ items: [Transcription], highlightTerms: [String] = []) -> some View {
        ForEach(items) { transcription in
            if let onOpenDetail {
                Button {
                    onOpenDetail(transcription)
                } label: {
                    HistoryCellView(transcription: transcription, highlightTerms: highlightTerms)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: transcription) {
                    HistoryCellView(transcription: transcription, highlightTerms: highlightTerms)
                }
            }
        }
    }

    /// En-tête de section : petites capitales espacées, discrètes sur fond
    /// système — les « folios » du journal (§6.3), en habit natif.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MzFont.sectionHeader)
            .tracking(MzFont.sectionHeaderTracking)
            .foregroundStyle(.secondary)
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
