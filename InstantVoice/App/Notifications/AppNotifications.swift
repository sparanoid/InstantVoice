import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleRecorderPanel = Notification.Name("toggleRecorderPanel")
    static let dismissRecorderPanel = Notification.Name("dismissRecorderPanel")
    static let didChangeModel = Notification.Name("didChangeModel")
    static let transcribeCppModelDeleted = Notification.Name("transcribeCppModelDeleted")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    /// Posted on the main thread after a provider's fetched model list changes. The object is the provider key.
    static let providerModelCatalogDidChange = Notification.Name("providerModelCatalogDidChange")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let showMainWindowRequested = Notification.Name("showMainWindowRequested")
    static let modeConfigurationApplied = Notification.Name("modeConfigurationApplied")
    static let modeConfigurationsDidChange = Notification.Name("ModeConfigurationsDidChange")
    static let modeShortcutAvailabilityDidChange = Notification.Name("modeShortcutAvailabilityDidChange")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let sessionMetricsDidChange = Notification.Name("sessionMetricsDidChange")
    /// Posted on the main thread after `DashboardStatsCache` stores newly computed statistics.
    static let dashboardStatsDidUpdate = Notification.Name("dashboardStatsDidUpdate")
    static let wordReplacementsDidChange = Notification.Name("wordReplacementsDidChange")
    static let autoLearnQueueDidChange = Notification.Name("autoLearnQueueDidChange")
    static let autoLearnReviewProposalsDidChange = Notification.Name("autoLearnReviewProposalsDidChange")
    static let openFileForTranscription = Notification.Name("openFileForTranscription")
    static let recordingDeviceChangeRequired = Notification.Name("recordingDeviceChangeRequired")
}
