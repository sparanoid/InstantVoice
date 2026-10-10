import Foundation
import SwiftData
import SwiftUI
import os

struct DashboardContent: View {
    private let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "DashboardContent")
    private static let fallbackDisplayName = String(localized: "there")
    private static let displayNameFontSize: CGFloat = 30
    private static let displayNameFontWeight: NSFont.Weight = .bold
    private static let displayNameMinWidth: CGFloat = 72
    private static let displayNameMaxWidth: CGFloat = 280
    private static let displayNameHorizontalPadding: CGFloat = 8
    private static let insightsUnlockDuration: TimeInterval = 30 * 60
    private static let peakHoursUnlockDuration: TimeInterval = 30 * 60
    private static let reviewBacklogActionThreshold = 50
    // Above this count, skip live auto-refresh (full reload is expensive); tab reopen still refreshes.
    private static let automaticStatsRefreshMetricLimit = 2_000
    private static let statsRefreshDebounceNanoseconds: UInt64 = 750_000_000
    let modelContext: ModelContext

    @State private var statsSummary: DashboardStatsSummary = .empty
    @State private var hasLoadedStatsSnapshot: Bool = false
    @State private var statsSnapshotGeneratedAt: Date?
    @State private var isDashboardStatsRefreshing = false
    @State private var dashboardStatsTask: Task<Void, Never>?
    @State private var dashboardStatsLoadGeneration = 0
    @State private var isModelPerformancePanelPresented = false
    @State private var isModelUsagePanelPresented = false
    @State private var isAutoLearnFailurePanelPresented = false
    @State private var isAutoLearnReviewPanelPresented = false
    @State private var autoLearnReviewBacklogCount = 0
    @State private var autoLearnBacklogRefreshGeneration = 0
    @State private var autoLearnFailurePresentationTask: Task<Void, Never>?
    @State private var isInsightsViewPresented = false
    @State private var selectedInsightPeriod: DashboardInsightPeriod = .allTime
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @ObservedObject private var modeManager = ModeManager.shared
    @State private var isEditingDisplayName = false
    @State private var displayNameDraft = ""
    @AppStorage("dashboardDisplayName") private var dashboardDisplayName: String = ""
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnEnabled = true
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false
    @AppStorage(AutoLearnSettings.failureAcknowledgedKey) private var isAutoLearnFailureAcknowledged = false
    @FocusState private var isNameFieldFocused: Bool
    @Query(Self.recentTranscriptionsDescriptor()) private var recentTranscriptionCandidates: [Transcription]

    private static func recentTranscriptionsDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return descriptor
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        let cachedSummary = DashboardStatsCache.shared.currentSummary()
        let cachedMetadata = DashboardStatsCache.shared.currentMetadata()
        _statsSummary = State(initialValue: cachedSummary ?? .empty)
        _hasLoadedStatsSnapshot = State(initialValue: cachedSummary != nil)
        _statsSnapshotGeneratedAt = State(initialValue: cachedMetadata?.generatedAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection

                dashboardSections
                    .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
                    .frame(maxWidth: DashboardLayout.contentMaxWidth, alignment: .topLeading)
                    .padding(.horizontal, DashboardLayout.pageHorizontalPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                // Clicking empty space ends name editing, since it doesn't move keyboard focus.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
            }
        }
        .ignoresSafeArea(edges: .top)
        // The artwork runs under the toolbar, so skip the edge band and toolbar backing that would cover it.
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .toolbar {
            if let availableUpdate = updaterViewModel.availableUpdate {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: updaterViewModel.checkForUpdates) {
                        Label("Update Available", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!updaterViewModel.canCheckForUpdates)
                    .help(
                        String(
                            format: String(localized: "Open the InstantVoice %@ update"),
                            availableUpdate.displayVersion
                        )
                    )
                    .accessibilityValue(Text(verbatim: availableUpdate.displayVersion))
                    .accessibilityHint("Opens the update window")
                }
            }
        }
        .navigationDestination(isPresented: $isInsightsViewPresented) {
            insightsPage
        }
        .task {
            scheduleDashboardStatsRefresh(allowSkipWhenFresh: hasLoadedStatsSnapshot)
        }
        .task {
            await refreshAutoLearnReviewBacklogCount()
        }
        .onAppear {
            refreshAccessibilityStatus()
            updaterViewModel.checkForUpdatesIfDue()
            if shouldAutomaticallyPresentAutoLearnFailure {
                scheduleAutoLearnFailurePresentation()
            }
        }
        .onChange(of: hasAutoLearnFailure) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnEnabled) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnFailureAcknowledged) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnFailurePanelPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented, hasAutoLearnFailure, isAutoLearnEnabled {
                AutoLearnSettings.acknowledgeCurrentFailure()
            }
        }
        .onReceive(LifecycleObserver.shared.publisher(for: .applicationDidBecomeActive)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            DashboardStatsCache.shared.markStale()

            if shouldRefreshStatsAfterMetricChange {
                scheduleDashboardStatsRefresh(debounce: true, allowSkipWhenFresh: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoLearnQueueDidChange)) { _ in
            scheduleAutoLearnReviewBacklogRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .autoLearnReviewProposalsDidChange)
        ) { _ in
            scheduleAutoLearnReviewBacklogRefresh()
        }
        .onDisappear {
            // Pushing Insights also hides the dashboard root; keep its refresh running for that page.
            guard !isInsightsViewPresented else { return }
            dashboardStatsTask?.cancel()
            dashboardStatsTask = nil
            dashboardStatsLoadGeneration += 1
            isDashboardStatsRefreshing = false
            autoLearnFailurePresentationTask?.cancel()
            autoLearnFailurePresentationTask = nil
        }
        .sidePanel(isPresented: $isAutoLearnFailurePanelPresented) {
            AutoLearnFailurePanel {
                isAutoLearnFailurePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isAutoLearnReviewPanelPresented) {
            AutoLearnReviewPanel {
                isAutoLearnReviewPanelPresented = false
            }
        }
    }

    private func scheduleAutoLearnFailurePresentation() {
        autoLearnFailurePresentationTask?.cancel()
        autoLearnFailurePresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, shouldAutomaticallyPresentAutoLearnFailure else { return }
            isAutoLearnFailurePanelPresented = true
            autoLearnFailurePresentationTask = nil
        }
    }

    private var shouldAutomaticallyPresentAutoLearnFailure: Bool {
        hasAutoLearnFailure && isAutoLearnEnabled && !isAutoLearnFailureAcknowledged
    }

    private var dashboardReviewCorrectionCount: Int? {
        guard isAutoLearnEnabled,
            autoLearnReviewBacklogCount > Self.reviewBacklogActionThreshold
        else {
            return nil
        }
        return autoLearnReviewBacklogCount
    }

    @MainActor
    private func refreshAutoLearnReviewBacklogCount() async {
        let generation = autoLearnBacklogRefreshGeneration
        let queuedCount = (try? await AutoLearnService.shared.outstandingReviewCount()) ?? 0
        let proposalCount = (try? await AutoLearnService.shared.reviewProposalCount()) ?? 0
        guard generation == autoLearnBacklogRefreshGeneration else { return }
        autoLearnReviewBacklogCount = queuedCount + proposalCount
    }

    private func scheduleAutoLearnReviewBacklogRefresh() {
        autoLearnBacklogRefreshGeneration += 1
        Task { await refreshAutoLearnReviewBacklogCount() }
    }

    private func updateAutoLearnFailurePresentation() {
        if shouldAutomaticallyPresentAutoLearnFailure {
            scheduleAutoLearnFailurePresentation()
        } else {
            autoLearnFailurePresentationTask?.cancel()
            autoLearnFailurePresentationTask = nil
            isAutoLearnFailurePanelPresented = false
        }
    }

    private var dashboardSections: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
            if !isAccessibilityEnabled {
                DashboardCallout(
                    systemImage: "hand.raised.fill",
                    tint: AppTheme.Status.warningStrong,
                    title: "Enable Accessibility Access",
                    message: "Required for InstantVoice shortcuts and app-wide controls to work properly.",
                    actionTitle: "Open Settings",
                    actionHelp: "Open Accessibility settings",
                    action: openAccessibilitySettings
                )
            }

            if !modeManager.hasEnabledConfiguration {
                DashboardCallout(
                    systemImage: "sparkles.rectangle.stack.fill",
                    tint: AppTheme.Accent.primary,
                    title: "Set Up a Mode",
                    message: "InstantVoice needs at least one mode to record. Create one to start dictating.",
                    actionTitle: "Manage Modes",
                    actionHelp: "Open Modes settings",
                    action: ModeSetupNavigator.openModesSettings
                )
            }

            if !recentDashboardTranscriptions.isEmpty {
                DashboardTranscriptCards(transcriptions: recentDashboardTranscriptions) {
                    MainWindowNavigation.shared.navigate(to: .history)
                }
            }
        }
    }

    private var recentDashboardTranscriptions: [Transcription] {
        Array(
            recentTranscriptionCandidates
                .filter { transcription in
                    isRecentDashboardTranscription(transcription)
                }
                .prefix(5)
        )
    }

    private func isRecentDashboardTranscription(_ transcription: Transcription) -> Bool {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue
            || transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue
        {
            return false
        }

        return text.range(of: "Transcription Failed:", options: [.caseInsensitive, .anchored]) == nil
    }

    private var selectedDailyActivityPoints: [DashboardProductivityPoint] {
        statsSummary.dailyActivity(for: selectedInsightPeriod)
    }

    private var selectedModelPerformance: [ModelPerformanceSummary] {
        statsSummary.modelPerformance(for: selectedInsightPeriod)
    }

    private var selectedModelUsage: ModelUsageSummary {
        statsSummary.modelUsage(for: selectedInsightPeriod)
    }

    private var selectedPeakHours: DashboardPeakHoursSummary {
        statsSummary.peakHours(for: selectedInsightPeriod)
    }

    private var selectedTotals: DashboardMetricTotals {
        statsSummary.totals(for: selectedInsightPeriod)
    }

    private var selectedTimeSavedSummary: DashboardTimeSavedSummary {
        return DashboardTimeSavedSummary(
            timeSaved: DashboardTimeSaving.timeSaved(words: selectedTotals.words, duration: selectedTotals.duration),
            wordCount: selectedTotals.words,
            sessionCount: selectedTotals.count
        )
    }

    private var canViewInsights: Bool {
        hasLoadedStatsSnapshot && statsSummary.totalDuration >= Self.insightsUnlockDuration
    }

    private var shouldShowLockedInsightsState: Bool {
        hasLoadedStatsSnapshot && !canViewInsights
    }

    private var canViewPeakHours: Bool {
        hasLoadedStatsSnapshot && selectedTotals.duration >= Self.peakHoursUnlockDuration && selectedPeakHours.hasData
    }

    private var shouldLockPeakHours: Bool {
        hasLoadedStatsSnapshot && !canViewPeakHours
    }

    private var shouldRefreshStatsAfterMetricChange: Bool {
        !hasLoadedStatsSnapshot || statsSummary.totalCount < Self.automaticStatsRefreshMetricLimit
    }

    private var insightsActionTitle: LocalizedStringKey {
        canViewInsights ? "View Insights" : "Insights Locked"
    }

    private var insightsActionIcon: String {
        canViewInsights ? "chart.line.uptrend.xyaxis" : "lock.fill"
    }

    private var insightsActionHelp: String {
        if canViewInsights {
            return String(localized: "View dashboard insights")
        }

        return String(localized: "Continue using InstantVoice to unlock these stats.")
    }

    private var insightsActionAccessibilityLabel: String {
        canViewInsights ? "View insights" : "Insights locked"
    }

    private var greetingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: greetingSymbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DashboardHeroPalette.accent)
                .font(displayNameFont)
                .accessibilityHidden(true)

            Text("\(greetingText),")
                .font(displayNameFont)
                .foregroundStyle(.primary)
                .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)

            displayNameView

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private var displayNameView: some View {
        if isEditingDisplayName {
            TextField("your name", text: displayNameBinding)
                .textFieldStyle(.plain)
                .font(displayNameFont)
                .foregroundStyle(.primary)
                .focused($isNameFieldFocused)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .padding(.horizontal, Self.displayNameHorizontalPadding)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.Accent.border, lineWidth: 1)
                )
                .onSubmit(finishEditingDisplayName)
                .onChange(of: isNameFieldFocused) { _, isFocused in
                    if !isFocused {
                        finishEditingDisplayName()
                    }
                }
        } else {
            Text(defaultedDisplayName)
                .font(displayNameFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .help("Click to edit dashboard name")
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditingDisplayName)
        }
    }

    private var displayNameFont: Font {
        .system(size: Self.displayNameFontSize, weight: .bold, design: .rounded)
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInsightsIfAvailable() {
        guard canViewInsights else {
            return
        }

        isInsightsViewPresented = true
    }

    private func openModelPerformancePanel() {
        isModelPerformancePanelPresented = true
    }

    private func openModelUsagePanel() {
        isModelUsagePanelPresented = true
    }

    private func openAutoLearnReviewPanel() {
        isAutoLearnReviewPanelPresented = true
    }

    @MainActor
    private func scheduleDashboardStatsRefresh(
        debounce: Bool = false,
        allowSkipWhenFresh: Bool = false
    ) {
        dashboardStatsTask?.cancel()
        dashboardStatsLoadGeneration += 1

        let generation = dashboardStatsLoadGeneration
        let modelContainer = modelContext.container

        dashboardStatsTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: Self.statsRefreshDebounceNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
            }

            await loadDashboardStatsEfficiently(
                from: modelContainer,
                generation: generation,
                allowSkipWhenFresh: allowSkipWhenFresh
            )
        }
    }

    private func loadDashboardStatsEfficiently(
        from modelContainer: ModelContainer,
        generation: Int,
        allowSkipWhenFresh: Bool
    ) async {
        do {
            if allowSkipWhenFresh {
                let shouldRefreshAutomatically =
                    SessionMetricMigrationService.shared.isRunning
                    || DashboardStatsCache.shared.shouldRefreshSnapshotAutomatically()

                guard shouldRefreshAutomatically else {
                    return
                }
            }

            let shouldStartRefresh = await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return false
                }

                self.isDashboardStatsRefreshing = true
                return true
            }

            guard shouldStartRefresh else {
                return
            }

            let summary = try await DashboardStatsLoader.load(from: modelContainer)

            guard !Task.isCancelled else {
                await finishDashboardStatsRefresh(generation: generation)
                return
            }

            let shouldAcceptSummary = summary.totalCount > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return
                }

                self.isDashboardStatsRefreshing = false

                guard shouldAcceptSummary else {
                    return
                }

                self.statsSummary = summary
                let metadata = DashboardStatsCache.shared.update(summary)
                self.statsSnapshotGeneratedAt = metadata.generatedAt
                self.hasLoadedStatsSnapshot = true
            }
        } catch is CancellationError {
            await finishDashboardStatsRefresh(generation: generation)
        } catch {
            await finishDashboardStatsRefresh(generation: generation)
            logger.error("Error loading dashboard stats: \(error, privacy: .public)")
        }
    }

    private func finishDashboardStatsRefresh(generation: Int) async {
        await MainActor.run {
            guard generation == dashboardStatsLoadGeneration else {
                return
            }

            self.isDashboardStatsRefreshing = false
        }
    }

    // MARK: - Sections

    private var insightsPage: some View {
        ScrollView {
            DashboardInsightsView(
                dailyActivityPoints: selectedDailyActivityPoints,
                allTimeDailyActivityPoints: statsSummary.allTimeDailyActivity,
                peakHoursSummary: selectedPeakHours,
                isPeakHoursLocked: shouldLockPeakHours,
                timeSavedSummary: selectedTimeSavedSummary,
                modelUsage: selectedModelUsage,
                modelPerformanceSummaries: selectedModelPerformance,
                onViewModelUsage: openModelUsagePanel,
                onViewModelPerformance: openModelPerformancePanel
            )
            .frame(maxWidth: DashboardLayout.contentMaxWidth, alignment: .topLeading)
            .padding(.horizontal, DashboardLayout.pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, DashboardLayout.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Insights period", selection: $selectedInsightPeriod.animation(.smooth)) {
                    ForEach(DashboardInsightPeriod.allCases) { period in
                        Text(period.pickerTitle)
                            .tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .sidePanel(isPresented: $isModelPerformancePanelPresented) {
            ModelPerformancePanel(
                summaries: selectedModelPerformance
            ) {
                isModelPerformancePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isModelUsagePanelPresented) {
            ModelUsagePanel(
                summary: selectedModelUsage
            ) {
                isModelUsagePanelPresented = false
            }
        }
    }

    private var heroSection: some View {
        DashboardHero(
            isLocked: shouldShowLockedInsightsState,
            headline: momentumHeadline,
            subtext: momentumSubtext,
            actionTitle: insightsActionTitle,
            actionIcon: insightsActionIcon,
            canViewInsights: canViewInsights,
            actionHelp: insightsActionHelp,
            actionAccessibilityLabel: insightsActionAccessibilityLabel,
            reviewCorrectionCount: dashboardReviewCorrectionCount,
            onViewInsights: openInsightsIfAvailable,
            onReviewCorrections: openAutoLearnReviewPanel,
            onBackgroundTap: dismissDisplayNameEditorIfNeeded
        ) {
            greetingRow
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: {
                isEditingDisplayName ? displayNameDraft : defaultedDisplayName
            },
            set: { newValue in
                displayNameDraft = String(newValue.prefix(32))
            }
        )
    }

    private var displayNameFieldWidth: CGFloat {
        let name = isEditingDisplayName ? displayNameDraft : defaultedDisplayName
        let measuredWidth = (name as NSString).size(
            withAttributes: [
                .font: NSFont.systemFont(ofSize: Self.displayNameFontSize, weight: Self.displayNameFontWeight)
            ]
        ).width
        return min(
            max(measuredWidth + (Self.displayNameHorizontalPadding * 2) + 6, Self.displayNameMinWidth),
            Self.displayNameMaxWidth
        )
    }

    private var defaultedDisplayName: String {
        let storedName = sanitizedDisplayName(dashboardDisplayName)
        return storedName.isEmpty ? systemDisplayName : storedName
    }

    private var systemDisplayName: String {
        Self.systemAccountFirstName() ?? Self.fallbackDisplayName
    }

    private func beginEditingDisplayName() {
        displayNameDraft = defaultedDisplayName
        isEditingDisplayName = true
        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func finishEditingDisplayName() {
        dashboardDisplayName = String(sanitizedDisplayName(displayNameDraft).prefix(32))
        isEditingDisplayName = false
        isNameFieldFocused = false

        if sanitizedDisplayName(dashboardDisplayName).isEmpty {
            dashboardDisplayName = ""
        }
    }

    private func dismissDisplayNameEditorIfNeeded() {
        if isEditingDisplayName {
            finishEditingDisplayName()
        }
    }

    private func sanitizedDisplayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func systemAccountFirstName() -> String? {
        let fullName = sanitizedSystemName(NSFullUserName())

        if let fullName,
            let givenName = PersonNameComponentsFormatter().personNameComponents(from: fullName)?.givenName,
            !givenName.isEmpty
        {
            return givenName
        }

        if let fullName,
            let firstName = fullName.split(whereSeparator: \.isWhitespace).first
        {
            return String(firstName)
        }

        if let shortName = sanitizedSystemName(NSUserName()) {
            return
                shortName
                .split(separator: ".")
                .first
                .map(String.init) ?? shortName
        }

        return nil
    }

    private static func sanitizedSystemName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return String(localized: "Good morning")
        case 12..<17:
            return String(localized: "Good afternoon")
        case 17..<24:
            return String(localized: "Good evening")
        default:
            return String(localized: "Hi")
        }
    }

    private var greetingSymbol: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "sun.horizon.fill"
        case 12..<17:
            return "sun.max.fill"
        case 17..<24:
            return "moon.stars.fill"
        default:
            return "moon.zzz.fill"
        }
    }

    private var momentumHeadline: DashboardHeroHeadline {
        guard hasLoadedStatsSnapshot else {
            return .calculatingProgress
        }

        guard statsSummary.totalCount > 0 else {
            return .startRecordingProgress
        }

        return .savedTime(formattedAllTimeSaved)
    }

    private var momentumSubtext: String {
        guard hasLoadedStatsSnapshot else {
            return String(localized: "Your word count and benchmark will appear here.")
        }

        guard statsSummary.totalCount > 0 else {
            return String(localized: "Your first milestone appears after one session.")
        }

        return formattedProgressBenchmarkText
    }

    // MARK: - Computed Metrics

    private var allTimeSaved: TimeInterval {
        DashboardTimeSaving.timeSaved(words: statsSummary.totalWords, duration: statsSummary.totalDuration)
    }

    private var formattedAllTimeSaved: String {
        Formatters.formattedSavedTime(allTimeSaved)
    }

    private var formattedAllTimeWords: String {
        let words = Formatters.formattedCompactNumber(statsSummary.totalWords)
        let wordUnit = statsSummary.totalWords == 1 ? String(localized: "word") : String(localized: "words")
        return String(localized: "\(words) \(wordUnit)")
    }

    private var formattedProgressBenchmarkText: String {
        switch DashboardProgressBenchmark.equivalence(for: statsSummary.totalWords) {
        case .matched(let title):
            return String(localized: "Dictated \(formattedAllTimeWords), equivalent to \(title).")
        case .repeated(let title, let count):
            return String(
                localized:
                    "Dictated \(formattedAllTimeWords), equivalent to \(title) \(formattedBenchmarkMultiple(count)).")
        case .remaining(let words, let title):
            guard words > 0, !title.isEmpty else {
                return String(localized: "Dictated \(formattedAllTimeWords).")
            }

            let remainingWords = Formatters.formattedNumber(words)
            return String(localized: "Dictated \(formattedAllTimeWords), \(remainingWords) words from \(title).")
        }
    }

    private func formattedBenchmarkMultiple(_ count: Int) -> String {
        if count == 2 {
            return String(localized: "twice")
        }

        return String(localized: "\(Formatters.formattedNumber(count)) times")
    }
}

private struct DashboardCallout: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let actionHelp: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .help(actionHelp)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: DashboardLayout.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}
