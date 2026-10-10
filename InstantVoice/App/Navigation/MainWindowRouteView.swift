import SwiftUI

/// The page shown for each pushed route in the main window.
struct MainWindowRouteView: View {
    let route: MainWindowRoute
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        switch route {
        case .mode(let id):
            ModeDetailPage(modeID: id)
        case .prompt(let modeID, let promptID):
            PromptEditorPage(modeID: modeID, promptID: promptID)
        case .cloudProvider(let id):
            CloudProviderPage(providerID: id)
        case .customTranscriptionModel(let id):
            CustomTranscriptionModelPage(modelID: id)
        case .customEnhancementModel(let id):
            CustomEnhancementModelPage(providerID: id)
        case .modelSettings:
            ModelSettingsPanel()
        case .dictionarySettings:
            DictionarySettingsPanel {
                navigation.push(.autoLearnReview)
            }
        case .autoLearnReview:
            AutoLearnReviewPanel()
        case .autoLearnFailure:
            AutoLearnFailurePage()
        case .historySettings:
            HistorySettingsPanel()
        case .historyAnalysis(let ids):
            HistoryAnalysisPage(transcriptionIDs: ids)
        case .insights:
            DashboardInsightsPage()
        case .modelUsage(let period):
            ModelUsagePage(period: period)
        case .modelPerformance(let period):
            ModelPerformancePage(period: period)
        }
    }
}

/// The Auto-Learn failure page. Leaving it acknowledges the failure, so the dashboard stops pointing to it.
private struct AutoLearnFailurePage: View {
    @EnvironmentObject private var navigation: MainWindowNavigation
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnEnabled = true
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false

    var body: some View {
        AutoLearnFailurePanel {
            navigation.dismissPage(.autoLearnFailure)
        }
        .onDisappear {
            if hasAutoLearnFailure, isAutoLearnEnabled {
                AutoLearnSettings.acknowledgeCurrentFailure()
            }
        }
    }
}
