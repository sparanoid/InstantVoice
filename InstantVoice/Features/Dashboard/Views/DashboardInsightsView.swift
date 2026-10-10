import SwiftUI

/// The Insights page body. Its title, back button, and period picker live in the toolbar.
struct DashboardInsightsView: View {
    let dailyActivityPoints: [DashboardProductivityPoint]
    let allTimeDailyActivityPoints: [DashboardProductivityPoint]
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool
    let timeSavedSummary: DashboardTimeSavedSummary
    let modelUsage: ModelUsageSummary
    let modelPerformanceSummaries: [ModelPerformanceSummary]
    let onViewModelUsage: () -> Void
    let onViewModelPerformance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashboardEditorialSummaryCard(
                summary: timeSavedSummary
            )

            DashboardActivityCalendarCard(
                points: allTimeDailyActivityPoints,
                selectedPoints: dailyActivityPoints,
                peakHoursSummary: peakHoursSummary,
                isPeakHoursLocked: isPeakHoursLocked
            )

            ModelUsageCard(
                summary: modelUsage,
                onViewMore: onViewModelUsage
            )

            ModelPerformanceCard(
                summaries: modelPerformanceSummaries,
                onViewMore: onViewModelPerformance
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The Insights page. It shows the statistics the dashboard last loaded, updates when a refresh finishes,
/// and keeps its own period choice.
struct DashboardInsightsPage: View {
    private static let peakHoursUnlockDuration: TimeInterval = 30 * 60

    @EnvironmentObject private var navigation: MainWindowNavigation
    @State private var summary = DashboardStatsCache.shared.currentSummary() ?? .empty
    @State private var period: DashboardInsightPeriod = .allTime

    var body: some View {
        ScrollView {
            DashboardInsightsView(
                dailyActivityPoints: summary.dailyActivity(for: period),
                allTimeDailyActivityPoints: summary.allTimeDailyActivity,
                peakHoursSummary: summary.peakHours(for: period),
                isPeakHoursLocked: !canViewPeakHours,
                timeSavedSummary: timeSavedSummary,
                modelUsage: summary.modelUsage(for: period),
                modelPerformanceSummaries: summary.modelPerformance(for: period),
                onViewModelUsage: { navigation.push(.modelUsage(period)) },
                onViewModelPerformance: { navigation.push(.modelPerformance(period)) }
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
                Picker("Insights period", selection: $period.animation(.smooth)) {
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
        .onAppear(perform: reloadSummary)
        .onReceive(NotificationCenter.default.publisher(for: .dashboardStatsDidUpdate)) { _ in
            reloadSummary()
        }
    }

    private func reloadSummary() {
        summary = DashboardStatsCache.shared.currentSummary() ?? summary
    }

    private var totals: DashboardMetricTotals {
        summary.totals(for: period)
    }

    private var timeSavedSummary: DashboardTimeSavedSummary {
        DashboardTimeSavedSummary(
            timeSaved: DashboardTimeSaving.timeSaved(words: totals.words, duration: totals.duration),
            wordCount: totals.words,
            sessionCount: totals.count
        )
    }

    private var canViewPeakHours: Bool {
        totals.duration >= Self.peakHoursUnlockDuration && summary.peakHours(for: period).hasData
    }
}
