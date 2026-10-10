import SwiftData
import SwiftUI

struct HistoryView: View {
    private struct PaginationCursor {
        let timestamp: Date
        let id: UUID
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigation: MainWindowNavigation
    @State private var searchText = ""
    @State private var selection: Set<UUID> = []
    @State private var updatedTranscription: Transcription?
    /// Keeps the detail pane on a selected row that a reload or search pushed out of the loaded pages.
    @State private var focusedFallback: Transcription?
    @State private var showDeleteConfirmation = false
    @State private var isShowingInfo = false
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasLoadedInitialContent = false
    @State private var hasMoreContent = true
    @State private var paginationCursor: PaginationCursor?
    @State private var isViewCurrentlyVisible = false

    private let exportService = InstantVoiceCSVExportService()
    private let pageSize = 40
    private static let listWidth: CGFloat = 300

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator:
        [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(
        after cursor: PaginationCursor? = nil,
        limit: Int? = nil
    ) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [
                SortDescriptor(\Transcription.timestamp, order: .reverse),
                SortDescriptor(\Transcription.id, order: .reverse),
            ]
        )

        if !searchText.isEmpty {
            let query = searchText
            if let cursor {
                let cursorTimestamp = cursor.timestamp
                let cursorID = cursor.id
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(query)
                        || (transcription.enhancedText?.localizedStandardContains(query) ?? false))
                        && (transcription.timestamp < cursorTimestamp
                            || (transcription.timestamp == cursorTimestamp && transcription.id < cursorID))
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(query)
                        || (transcription.enhancedText?.localizedStandardContains(query) ?? false)
                }
            }
        } else if let cursor {
            let cursorTimestamp = cursor.timestamp
            let cursorID = cursor.id
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.timestamp < cursorTimestamp
                    || (transcription.timestamp == cursorTimestamp && transcription.id < cursorID)
            }
        }

        // Fetch one extra row so the UI can determine whether another page exists.
        descriptor.fetchLimit = (limit ?? pageSize) + 1

        return descriptor
    }

    /// The transcription shown in the detail pane when exactly one row is selected.
    private var focusedTranscription: Transcription? {
        guard selection.count == 1, let id = selection.first else { return nil }
        if let updatedTranscription, updatedTranscription.id == id {
            return updatedTranscription
        }
        if let loaded = displayedTranscriptions.first(where: { $0.id == id }) {
            return loaded
        }
        return focusedFallback?.id == id ? focusedFallback : nil
    }

    private var isHistoryEmpty: Bool {
        hasLoadedInitialContent && displayedTranscriptions.isEmpty && searchText.isEmpty && !isLoading
    }

    var body: some View {
        Group {
            if isHistoryEmpty {
                ContentUnavailableView {
                    Label("No transcriptions yet", systemImage: "text.bubble")
                } description: {
                    Text("Your transcription history will appear here")
                }
            } else {
                HStack(spacing: 0) {
                    listColumn
                        .frame(width: Self.listWidth)

                    Divider()
                        .ignoresSafeArea()

                    detailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search transcriptions..."))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.push(.historySettings)
                } label: {
                    Label("History Settings", systemImage: "gearshape")
                }
                .help("History settings")
            }
        }
        .onExitCommand {
            if isShowingInfo {
                isShowingInfo = false
            } else if !selection.isEmpty {
                selection.removeAll()
            }
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    localized:
                        "This action cannot be undone. Are you sure you want to delete \(selection.count) items?"
                ))
        }
        .onAppear {
            isViewCurrentlyVisible = true
            // Returning from a pushed page reloads in place, keeping the loaded pages and scroll position.
            Task { await loadInitialContent(minimumCount: displayedTranscriptions.count) }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                resetPagination()
                await loadInitialContent()
                // A new search is a new context: keep only selected rows that are still visible.
                let visibleIDs = Set(displayedTranscriptions.map(\.id))
                selection.formIntersection(visibleIDs)
            }
        }
        .onChange(of: selection) { _, newSelection in
            isShowingInfo = false
            if newSelection.count != 1 {
                updatedTranscription = nil
            }
            refreshFocusedFallback()
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible, newId != oldId else { return }
            // Reload in place, keeping every loaded page so scroll position and selection survive.
            Task { await loadInitialContent(minimumCount: displayedTranscriptions.count + 1) }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listColumn: some View {
        if !hasLoadedInitialContent {
            // Build the list only once rows exist; rows inserted into an empty list keep a stale height.
            Color.clear
        } else if displayedTranscriptions.isEmpty && !isLoading && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(selection: $selection) {
                ForEach(displayedTranscriptions) { transcription in
                    HistoryListRow(transcription: transcription)
                        .tag(transcription.id)
                        .listRowSeparator(
                            transcription.id == displayedTranscriptions.first?.id ? .hidden : .automatic,
                            edges: .top
                        )
                        .onAppear {
                            loadMoreIfNeeded(after: transcription)
                        }
                }

                if hasMoreContent && isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, HistoryListRow.height)
            .contextMenu(forSelectionType: UUID.self) { ids in
                rowContextMenu(for: ids)
            }
            .onDeleteCommand {
                guard !selection.isEmpty else { return }
                showDeleteConfirmation = true
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button {
                copyText(of: ids)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                exportTranscriptions(ids)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button {
                analyzeTranscriptions(ids)
            } label: {
                Label("Analyze", systemImage: "chart.bar.xaxis")
            }

            Divider()

            Button(role: .destructive) {
                selection = ids
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let transcription = focusedTranscription {
            TranscriptionDetailView(
                transcription: transcription,
                isInfoPresented: $isShowingInfo,
                onBack: { selection.removeAll() },
                onTranscriptionUpdated: { updated in
                    guard selection.contains(transcription.id) else { return }
                    isShowingInfo = false
                    updatedTranscription = updated
                    selection = [updated.id]
                }
            )
            .id(transcription.id)
        } else if selection.count > 1 {
            HistoryMultiSelectionView(
                count: selection.count,
                canSelectAll: hasMoreContent,
                onSelectAll: { Task { await selectAllTranscriptions() } },
                onAnalyze: { analyzeTranscriptions(selection) },
                onExport: { exportTranscriptions(selection) },
                onDelete: { showDeleteConfirmation = true }
            )
        } else {
            ContentUnavailableView {
                Label("No Transcription Selected", systemImage: "text.bubble")
            } description: {
                Text("Select a transcription to see its details.")
            }
        }
    }

    // MARK: - Actions

    private func copyText(of ids: Set<UUID>) {
        let text = transcriptions(for: ids)
            .map(\.preferredHistoryText)
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        _ = ClipboardManager.copyToClipboard(text)
    }

    private func exportTranscriptions(_ ids: Set<UUID>) {
        exportService.exportTranscriptionsToCSV(transcriptions: transcriptions(for: ids))
    }

    private func analyzeTranscriptions(_ ids: Set<UUID>) {
        navigation.push(.historyAnalysis(transcriptions(for: ids).map(\.id)))
    }

    /// Resolves selected IDs to models, including rows beyond the loaded pages after Select All.
    private func transcriptions(for ids: Set<UUID>) -> [Transcription] {
        let loaded = displayedTranscriptions.filter { ids.contains($0.id) }
        guard loaded.count < ids.count else { return loaded }

        let idList = Array(ids)
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate<Transcription> { idList.contains($0.id) },
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? loaded
    }

    // MARK: - Data Loading

    private func loadMoreIfNeeded(after transcription: Transcription) {
        guard transcription.id == displayedTranscriptions.last?.id else { return }
        Task { await loadMoreContent() }
    }

    /// Loads the first rows, or at least `minimumCount` rows when reloading in place.
    @MainActor
    private func loadInitialContent(minimumCount: Int = 0) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedInitialContent = true
            refreshFocusedFallback()
        }

        let isFirstLoad = !hasLoadedInitialContent

        do {
            let limit = max(pageSize, minimumCount)
            let items = try modelContext.fetch(cursorQueryDescriptor(limit: limit))
            let page = Array(items.prefix(limit))
            displayedTranscriptions = page
            paginationCursor = page.last.map { PaginationCursor(timestamp: $0.timestamp, id: $0.id) }
            hasMoreContent = items.count > limit

            // Like Mail, open on the newest item rather than an empty detail pane.
            if isFirstLoad, selection.isEmpty, let newest = page.first {
                selection = [newest.id]
            }
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }

    /// Resolves a single selected row that isn't loaded, and drops it from the selection if it no longer exists.
    private func refreshFocusedFallback() {
        guard selection.count == 1, let id = selection.first,
            !displayedTranscriptions.contains(where: { $0.id == id })
        else {
            focusedFallback = nil
            return
        }
        if updatedTranscription?.id == id {
            return
        }

        var descriptor = FetchDescriptor<Transcription>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let transcription = try? modelContext.fetch(descriptor).first {
            focusedFallback = transcription
        } else {
            focusedFallback = nil
            selection.remove(id)
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let paginationCursor else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let items = try modelContext.fetch(cursorQueryDescriptor(after: paginationCursor))
            let page = Array(items.prefix(pageSize))
            displayedTranscriptions.append(contentsOf: page)
            self.paginationCursor = page.last.map { PaginationCursor(timestamp: $0.timestamp, id: $0.id) }
            hasMoreContent = items.count > pageSize
        } catch {
            print("Error loading more transcriptions: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedTranscriptions = []
        paginationCursor = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Deletion

    private func performDeletion(for transcription: Transcription) {
        if let url = transcription.availableHistoryAudioURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        for transcription in transcriptions(for: selection) {
            performDeletion(for: transcription)
        }
        selection.removeAll()
        updatedTranscription = nil
        focusedFallback = nil
        isShowingInfo = false

        let loadedCount = displayedTranscriptions.count
        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
            }
            await loadInitialContent(minimumCount: loadedCount)
        }
    }

    @MainActor
    private func selectAllTranscriptions() async {
        do {
            var allDescriptor = FetchDescriptor<Transcription>()

            if !searchText.isEmpty {
                let query = searchText
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(query)
                        || (transcription.enhancedText?.localizedStandardContains(query) ?? false)
                }
            }

            allDescriptor.propertiesToFetch = [\.id]
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            selection = Set(displayedTranscriptions.map(\.id)).union(allTranscriptions.map(\.id))
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}
