import AppKit
import SwiftUI

/// A mode's settings page. Edits save shortly after each change, like System Settings. A field that fails
/// validation keeps its saved value and shows an inline explanation until it's fixed; other edits still save.
struct ModeConfigEditorView: View {
    let modeID: UUID
    let modeManager: ModeManager

    @EnvironmentObject private var navigation: MainWindowNavigation
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var modeWarmupStore: ModeFormWarmupStore

    @State private var draft: ModeConfigDraft
    @State private var validationErrors: [ModeValidationError] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var hasUnsavedChanges = false
    /// Changes the form makes to itself while appearing, such as filling in a language, aren't edits.
    @State private var savesEditsAfter = Date.distantFuture
    /// The stored mode as of this page's last save, to tell its own saves apart from changes made elsewhere.
    @State private var lastSavedSettings: Data?

    private static let saveDelay: Duration = .milliseconds(350)
    private static let appearanceSettleTime: TimeInterval = 0.3

    init(config: ModeConfig, modeManager: ModeManager) {
        self.modeID = config.id
        self.modeManager = modeManager
        _draft = State(initialValue: ModeConfigDraft(mode: .edit(config), modeManager: modeManager))
    }

    private var storedConfig: ModeConfig? {
        modeManager.getConfiguration(with: modeID)
    }

    var body: some View {
        ModeConfigFormView(
            modeID: modeID,
            modeManager: modeManager,
            draft: liveDraft,
            validationErrors: validationErrors,
            onDelete: deleteConfiguration,
            openPromptEditor: openPromptEditor
        )
        .navigationTitle(Text(verbatim: displayName))
        .onAppear(perform: prepareView)
        .onDisappear(perform: saveNow)
        .onChange(of: storedConfig.flatMap(Self.settingsData)) { _, _ in
            adoptChangesMadeElsewhere()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveNow()
        }
    }

    private var displayName: String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (storedConfig?.name ?? "") : name
    }

    /// Every edit made through the form passes through here and schedules a save.
    private var liveDraft: Binding<ModeConfigDraft> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                if Date.now >= savesEditsAfter {
                    scheduleSave()
                }
            }
        )
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil

        guard let stored = storedConfig else { return }
        let validator = ModeValidator(modeManager: modeManager)
        let edited = draft.makeConfig(basedOn: stored)
        validationErrors = validator.validateForSave(config: edited, mode: .edit(stored))

        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false

        let config = edited.keepingSavedValues(for: validationErrors, from: stored)
        guard validator.validateForSave(config: config, mode: .edit(stored)).isEmpty,
            !Self.hasSameSettings(config, stored)
        else { return }

        modeManager.updateConfiguration(config)
        lastSavedSettings = storedConfig.flatMap(Self.settingsData)
    }

    /// Brings in changes saved elsewhere, such as the recorder's AI Enhancement toggle, so the next edit here
    /// doesn't revert them. Edits on this page that haven't been saved yet take precedence.
    private func adoptChangesMadeElsewhere() {
        guard !hasUnsavedChanges, let stored = storedConfig else { return }
        let storedSettings = Self.settingsData(stored)
        guard storedSettings != lastSavedSettings else { return }
        lastSavedSettings = storedSettings
        guard !Self.hasSameSettings(draft.makeConfig(basedOn: stored), stored) else { return }

        var updatedDraft = ModeConfigDraft(mode: .edit(stored), modeManager: modeManager)
        updatedDraft.isTranscriptionFormattingExpanded = draft.isTranscriptionFormattingExpanded
        draft = updatedDraft
        validationErrors = ModeValidator(modeManager: modeManager)
            .validateForSave(config: draft.makeConfig(basedOn: stored), mode: .edit(stored))
    }

    private func openPromptEditor(mode: PromptEditorView.Mode) {
        saveNow()
        switch mode {
        case .add:
            navigation.push(.prompt(modeID: modeID, promptID: nil))
        case .edit(let prompt):
            navigation.push(.prompt(modeID: modeID, promptID: prompt.id))
        }
    }

    private func prepareView() {
        savesEditsAfter = Date.now.addingTimeInterval(Self.appearanceSettleTime)
        lastSavedSettings = storedConfig.flatMap(Self.settingsData)

        modeWarmupStore.configure(
            aiService: aiService,
            enhancementService: enhancementService,
            transcriptionModelManager: transcriptionModelManager
        )

        let snapshot = modeWarmupStore.snapshot

        if let selectedModelName = draft.selectedTranscriptionModelName,
            !snapshot.hasUsableTranscriptionModel(named: selectedModelName)
        {
            draft.selectedTranscriptionModelName = nil
        }

        draft.ensurePromptSelection(firstPromptId: snapshot.firstPromptId)

        if let selectedModelName = draft.selectedTranscriptionModelName,
            let model = snapshot.transcriptionModel(named: selectedModelName)
        {
            draft.useCompatibleLanguage(for: model)
        }

        // Show existing problems, such as a missing model, without saving anything yet.
        if let stored = storedConfig {
            validationErrors = ModeValidator(modeManager: modeManager)
                .validateForSave(config: draft.makeConfig(basedOn: stored), mode: .edit(stored))
        }
    }

    private func deleteConfiguration() -> ModeRemovalResult {
        saveTask?.cancel()
        saveTask = nil
        hasUnsavedChanges = false

        let result = modeManager.removeConfiguration(with: modeID)
        switch result {
        case .removed, .notFound:
            navigation.dismissPage(.mode(modeID))
        case .blockedDefault:
            break
        }
        return result
    }

    /// The stored form of a mode. `ModeConfig` equality only compares IDs, so pages compare this instead.
    private static func settingsData(_ config: ModeConfig) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(config)
    }

    private static func hasSameSettings(_ lhs: ModeConfig, _ rhs: ModeConfig) -> Bool {
        settingsData(lhs) == settingsData(rhs)
    }
}

private extension ModeConfig {
    /// This mode with the saved value restored for every field that failed validation.
    func keepingSavedValues(for errors: [ModeValidationError], from saved: ModeConfig) -> ModeConfig {
        var config = self
        for error in errors {
            switch error {
            case .emptyName, .duplicateName:
                config.name = saved.name
            case .missingTranscriptionModel:
                config.selectedTranscriptionModelName = saved.selectedTranscriptionModelName
            case .missingEnhancementModel:
                config.selectedAIProvider = saved.selectedAIProvider
                config.selectedAIModel = saved.selectedAIModel
            case .emptyCustomCommand:
                config.outputMode = saved.outputMode
                config.customCommand = saved.customCommand
            case .duplicateAppTrigger, .duplicateWebsiteTrigger:
                config.appConfigs = saved.appConfigs
                config.urlConfigs = saved.urlConfigs
                config.triggerGroups = saved.triggerGroups
            }
        }
        return config
    }
}

/// Resolves a mode route to its page, or explains that the mode no longer exists.
struct ModeDetailPage: View {
    let modeID: UUID
    @ObservedObject private var modeManager = ModeManager.shared
    @StateObject private var modeWarmupStore = ModeFormWarmupStore.shared

    var body: some View {
        if let config = modeManager.getConfiguration(with: modeID) {
            ModeConfigEditorView(config: config, modeManager: modeManager)
                .environmentObject(modeWarmupStore)
        } else {
            ContentUnavailableView {
                Label("Mode Not Found", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("This mode was deleted.")
            }
        }
    }
}
