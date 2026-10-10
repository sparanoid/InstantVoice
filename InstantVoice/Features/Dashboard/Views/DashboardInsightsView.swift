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
