import AppKit
import SwiftUI

struct CustomProviderManagementView: View {
    @ObservedObject var customModelManager: CustomCloudModelManager
    @ObservedObject var customAIProviderManager: CustomAIProviderManager

    let onAddTranscriptionModel: () -> Void
    let onEditTranscriptionModel: (CustomCloudModel) -> Void
    let onDeleteTranscriptionModel: (CustomCloudModel) -> Void
    let onAddEnhancementModel: () -> Void
    let onEditEnhancementModel: (CustomAIProviderConfig) -> Void
    let onDeleteEnhancementModel: (CustomAIProviderConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            customTranscriptionSection
            customEnhancementSection
        }
    }

    private var customTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Transcription Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                addHelp: "Add transcription model",
                onAdd: onAddTranscriptionModel
            )

            if customModelManager.customModels.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "waveform",
                    title: "No Custom Transcription Models"
                )
            } else {
                ForEach(customModelManager.customModels) { model in
                    CustomModelCardView(
                        model: model,
                        deleteAction: {
                            onDeleteTranscriptionModel(model)
                        },
                        editAction: onEditTranscriptionModel
                    )
                }
            }
        }
    }

    private var customEnhancementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Enhancement Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                addHelp: "Add enhancement model",
                onAdd: onAddEnhancementModel
            )

            if customAIProviderManager.providers.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "sparkles",
                    title: "No Custom Enhancement Models"
                )
            } else {
                ForEach(customAIProviderManager.providers) { provider in
                    CustomEnhancementModelRow(
                        provider: provider,
                        onEdit: {
                            onEditEnhancementModel(provider)
                        },
                        onDelete: {
                            onDeleteEnhancementModel(provider)
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        addHelp: LocalizedStringResource,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderSectionHeader(title: title, subtitle: subtitle)

            Spacer(minLength: 8)

            AddIconButton(helpText: addHelp, action: onAdd)
        }
    }

}

private struct CustomProviderEmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomEnhancementModelRow: View {
    let provider: CustomAIProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))

                if provider.modelName.isEmpty {
                    Text("No model configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(provider.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(14)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

/// Adds or edits a custom transcription model. Edits to an existing model save as soon as they're valid; a new
/// model is added with the toolbar's Add Model button.
struct CustomTranscriptionModelEditorPanel: View {
    let editingModel: CustomCloudModel?
    @ObservedObject var customModelManager: CustomCloudModelManager
    let onAdded: () -> Void
    var onUpdated: () -> Void = {}
    var onDelete: (() -> Void)? = nil

    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var serverModels: [String] = []
    @State private var isMultilingual = true
    @State private var validationErrors: [String] = []
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var isShowingDeleteConfirmation = false

    private var isEditing: Bool {
        editingModel != nil
    }

    private var canTestConnection: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetConnectionTest() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        connectionTest = .idle
    }

    private func runConnectionTest() {
        connectionTestTask?.cancel()
        connectionTest = .testing
        let endpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        connectionTestTask = Task {
            let result = await CustomModelConnectionTester.testTranscriptionEndpoint(
                endpoint: endpoint,
                apiKey: key,
                modelName: model
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connectionTest = ConnectionTestState(result: result)
            }
        }
    }

    var body: some View {
        Form {
            CustomModelErrorSection(messages: validationErrors)

            Section {
                TextField("Display Name", text: $displayName, prompt: Text("My Custom Model"))
                TextField(
                    "API Endpoint", text: $apiEndpoint,
                    prompt: Text(verbatim: "https://api.openai.com/v1/audio/transcriptions"))
                SecureField("API Key", text: $apiKey, prompt: Text("Paste API key"))
                ModelNameField(modelName: $modelName, prompt: "gpt-4o-mini-transcribe", serverModels: serverModels)
                Toggle("Multilingual Model", isOn: $isMultilingual)
                ConnectionTestRow(state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
            } header: {
                Text("Details")
            } footer: {
                CustomModelEditorFooter(
                    connectionTest: connectionTest,
                    onDelete: isEditing && onDelete != nil ? { isShowingDeleteConfirmation = true } : nil
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(
            isEditing
                ? Text(verbatim: editingModel?.displayName ?? "") : Text("Add Custom Transcription Model")
        )
        .task(id: "\(apiEndpoint)\n\(apiKey)") {
            let models = await ModelNameField.loadServerModels(endpoint: apiEndpoint, apiKey: apiKey)
            if !Task.isCancelled {
                serverModels = models
            }
        }
        .toolbar {
            if !isEditing {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Model", action: saveModel)
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave || isSaving)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .confirmationDialog(
            "Delete Custom Model",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                saveTask?.cancel()
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(localized: "Are you sure you want to delete the custom model '%@'?"),
                    editingModel?.displayName ?? displayName
                )
            )
        }
        .onAppear(perform: loadModel)
        .onDisappear {
            if saveTask != nil {
                saveModel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if saveTask != nil {
                saveModel()
            }
        }
        .onChange(of: editingModel?.id) { _, _ in
            loadModel()
        }
        .onChange(of: apiEndpoint) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: apiKey) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: modelName) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: displayName) { _, _ in scheduleLiveSave() }
        .onChange(of: isMultilingual) { _, _ in scheduleLiveSave() }
    }

    /// Existing models save shortly after each edit; new ones wait for Add Model.
    private func scheduleLiveSave() {
        guard isEditing else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveModel()
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadModel() {
        if let editingModel {
            displayName = editingModel.displayName
            apiEndpoint = editingModel.apiEndpoint
            apiKey = APIKeyManager.shared.getCustomModelAPIKey(forModelId: editingModel.id) ?? ""
            modelName = editingModel.modelName
            isMultilingual = editingModel.isMultilingualModel
        } else {
            displayName = ""
            apiEndpoint = "https://api.openai.com/v1/audio/transcriptions"
            apiKey = ""
            modelName = "gpt-4o-mini-transcribe"
            isMultilingual = true
        }

        validationErrors = []
        isSaving = false
        resetConnectionTest()
    }

    private func saveModel() {
        saveTask?.cancel()
        saveTask = nil

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedName = trimmedDisplayName.lowercased().replacingOccurrences(of: " ", with: "-")

        if let editingModel,
            editingModel.displayName == trimmedDisplayName,
            editingModel.apiEndpoint == trimmedEndpoint,
            editingModel.modelName == trimmedModelName,
            editingModel.isMultilingualModel == isMultilingual,
            (APIKeyManager.shared.getCustomModelAPIKey(forModelId: editingModel.id) ?? "") == trimmedKey
        {
            validationErrors = []
            return
        }

        validationErrors = customModelManager.validateModelDetails(
            name: generatedName,
            displayName: trimmedDisplayName,
            apiEndpoint: trimmedEndpoint,
            modelName: trimmedModelName,
            excludingId: editingModel?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else { return }
        isSaving = true

        if let editingModel {
            let updatedModel = CustomCloudModel(
                id: editingModel.id,
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                isMultilingual: isMultilingual
            )

            guard customModelManager.updateCustomModel(updatedModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }

            isSaving = false
            onUpdated()
            return
        } else {
            let customModel = CustomCloudModel(
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                isMultilingual: isMultilingual
            )

            guard customModelManager.addCustomModel(customModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }
        }

        isSaving = false
        onAdded()
    }
}

/// Adds or edits a custom enhancement model, saving edits to an existing one as soon as they're valid.
struct CustomEnhancementModelEditorPanel: View {
    let editingProvider: CustomAIProviderConfig?
    @ObservedObject var manager: CustomAIProviderManager
    let onAdded: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var serverModels: [String] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var isShowingDeleteConfirmation = false

    private var isEditing: Bool {
        editingProvider != nil
    }

    private var canTestConnection: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetConnectionTest() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        connectionTest = .idle
    }

    private func runConnectionTest() {
        connectionTestTask?.cancel()
        connectionTest = .testing
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        connectionTestTask = Task {
            let result = await CustomModelConnectionTester.testEnhancementEndpoint(
                baseURL: url,
                apiKey: key,
                modelName: model
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connectionTest = ConnectionTestState(result: result)
            }
        }
    }

    var body: some View {
        Form {
            CustomModelErrorSection(messages: errorMessage.map { [$0] } ?? [])

            Section {
                TextField("Display Name", text: $displayName, prompt: Text("My Enhancement Model"))
                TextField(
                    "Base URL", text: $baseURL,
                    prompt: Text(verbatim: "https://api.openai.com/v1/chat/completions"))
                SecureField("API Key", text: $apiKey, prompt: Text("Paste API key"))
                ModelNameField(modelName: $modelName, prompt: "gpt-5.5", serverModels: serverModels)
                ConnectionTestRow(state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
            } header: {
                Text("Details")
            } footer: {
                CustomModelEditorFooter(
                    connectionTest: connectionTest,
                    onDelete: isEditing && onDelete != nil ? { isShowingDeleteConfirmation = true } : nil
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(
            isEditing ? Text(verbatim: editingProvider?.name ?? "") : Text("Add Custom Enhancement Model")
        )
        .task(id: "\(baseURL)\n\(apiKey)") {
            let models = await ModelNameField.loadServerModels(endpoint: baseURL, apiKey: apiKey)
            if !Task.isCancelled {
                serverModels = models
            }
        }
        .toolbar {
            if !isEditing {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Model", action: saveProvider)
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave || isSaving)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .confirmationDialog(
            "Delete Custom Enhancement Model",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                saveTask?.cancel()
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(localized: "Are you sure you want to delete the custom enhancement model '%@'?"),
                    editingProvider?.name ?? displayName
                )
            )
        }
        .onAppear(perform: loadProvider)
        .onDisappear {
            if saveTask != nil {
                saveProvider()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if saveTask != nil {
                saveProvider()
            }
        }
        .onChange(of: editingProvider?.id) { _, _ in
            loadProvider()
        }
        .onChange(of: baseURL) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: apiKey) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: modelName) { _, _ in
            resetConnectionTest()
            scheduleLiveSave()
        }
        .onChange(of: displayName) { _, _ in scheduleLiveSave() }
    }

    /// Existing models save shortly after each edit; new ones wait for Add Model.
    private func scheduleLiveSave() {
        guard isEditing else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveProvider()
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadProvider() {
        if let editingProvider {
            displayName = editingProvider.name
            baseURL = editingProvider.baseURL
            apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: editingProvider.id) ?? ""
            modelName = editingProvider.modelName
        } else {
            displayName = ""
            baseURL = "https://api.openai.com/v1/chat/completions"
            apiKey = ""
            modelName = "gpt-5.5"
        }

        errorMessage = nil
        isSaving = false
        resetConnectionTest()
    }

    private func saveProvider() {
        saveTask?.cancel()
        saveTask = nil

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingProvider,
            editingProvider.name == trimmedName,
            editingProvider.baseURL == trimmedURL,
            editingProvider.modelName == trimmedModelName,
            (APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: editingProvider.id) ?? "") == trimmedKey
        {
            errorMessage = nil
            return
        }

        var validationErrors = manager.validateProvider(
            name: trimmedName,
            baseURL: trimmedURL,
            model: trimmedModelName,
            excluding: editingProvider?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: "\n")
            return
        }

        errorMessage = nil

        let provider = CustomAIProviderConfig(
            id: editingProvider?.id ?? UUID(),
            name: trimmedName,
            baseURL: trimmedURL,
            models: [trimmedModelName],
            selectedModel: trimmedModelName
        )

        if isEditing {
            isSaving = true
            let didSave = manager.updateProvider(provider, apiKey: trimmedKey)
            isSaving = false

            if !didSave {
                errorMessage = String(localized: "Failed to save custom enhancement model")
            }
            return
        }

        isSaving = true
        let didSave = manager.addProvider(provider, apiKey: trimmedKey)
        isSaving = false

        if didSave {
            onAdded()
        } else {
            errorMessage = String(localized: "Failed to save API key securely")
        }
    }
}

private enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(message: String)

    init(result: ConnectionTestResult) {
        switch result {
        case .success:
            self = .success
        case .failure(let message):
            self = .failure(message: message)
        }
    }

    var isTesting: Bool {
        self == .testing
    }
}

/// The Model Name field, with a menu of the models the server lists once it returns any.
private struct ModelNameField: View {
    @Binding var modelName: String
    let prompt: String
    let serverModels: [String]

    var body: some View {
        LabeledContent("Model Name") {
            HStack(spacing: 6) {
                TextField("Model Name", text: $modelName, prompt: Text(verbatim: prompt))
                    .labelsHidden()

                if !serverModels.isEmpty {
                    Menu {
                        ForEach(serverModels, id: \.self) { model in
                            Button(model) { modelName = model }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Choose a model this server lists")
                }
            }
        }
    }

    /// Waits for typing to pause, then asks the server for its models.
    static func loadServerModels(endpoint: String, apiKey: String) async -> [String] {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return [] }
        return await CustomModelConnectionTester.listModels(
            endpoint: endpoint,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// The Connection row: progress or success on the left of the Test button, like a System Settings row.
private struct ConnectionTestRow: View {
    let state: ConnectionTestState
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent("Connection") {
            HStack(spacing: 8) {
                inlineStatus

                Button("Test", action: action)
                    .disabled(isDisabled || state.isTesting)
            }
        }
    }

    @ViewBuilder
    private var inlineStatus: some View {
        switch state {
        case .idle, .failure:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing…")
            }
            .foregroundStyle(.secondary)
        case .success:
            Label("Test successful", systemImage: "checkmark.circle")
                .foregroundStyle(AppTheme.Status.positive)
                .lineLimit(1)
        }
    }
}

/// Below the details: a failed connection test, then the delete button outside the section's box.
private struct CustomModelEditorFooter: View {
    let connectionTest: ConnectionTestState
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .failure(let message) = connectionTest {
                Text(message)
                    .foregroundStyle(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onDelete {
                HStack {
                    Spacer()
                    Button("Delete Model…", role: .destructive, action: onDelete)
                }
                .padding(.top, 8)
            }
        }
    }
}

/// Problems that kept the model from saving, shown above the form like the mode page's validation.
private struct CustomModelErrorSection: View {
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            Section {
                ForEach(messages, id: \.self) { message in
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
        }
    }
}

#if DEBUG
    private enum CustomModelPreviewSamples {
        static let transcriptionModel = CustomCloudModel(
            name: "acme-transcribe",
            displayName: "Acme Transcribe",
            description: "OpenAI-compatible transcription endpoint for previewing custom model pages.",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "acme-transcribe-large",
            isMultilingual: true
        )

        static let enhancementProvider = CustomAIProviderConfig(
            name: "Acme Enhance",
            baseURL: "https://api.example.com/v1/chat/completions",
            models: ["acme-enhance-pro"],
            selectedModel: "acme-enhance-pro"
        )
    }

    #Preview("Custom Transcription Model Page") {
        NavigationStack {
            CustomTranscriptionModelEditorPanel(
                editingModel: CustomModelPreviewSamples.transcriptionModel,
                customModelManager: .shared,
                onAdded: {}
            )
        }
        .frame(width: 760, height: 520)
    }

    #Preview("Custom Enhancement Model Page") {
        NavigationStack {
            CustomEnhancementModelEditorPanel(
                editingProvider: CustomModelPreviewSamples.enhancementProvider,
                manager: .shared,
                onAdded: {}
            )
        }
        .frame(width: 760, height: 520)
    }
#endif

/// Page for adding (`nil` ID) or editing a custom transcription model.
struct CustomTranscriptionModelPage: View {
    let modelID: UUID?

    @ObservedObject private var customModelManager = CustomCloudModelManager.shared
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        if let modelID {
            if let model = customModelManager.customModels.first(where: { $0.id == modelID }) {
                CustomTranscriptionModelEditorPanel(
                    editingModel: model,
                    customModelManager: customModelManager,
                    onAdded: {},
                    onUpdated: transcriptionModelManager.refreshAllAvailableModels,
                    onDelete: {
                        customModelManager.removeCustomModel(withId: modelID)
                        transcriptionModelManager.refreshAllAvailableModels()
                        navigation.dismissPage(.customTranscriptionModel(modelID))
                    }
                )
            } else {
                ContentUnavailableView {
                    Label("Model Not Found", systemImage: "waveform")
                } description: {
                    Text("This model was deleted.")
                }
            }
        } else {
            CustomTranscriptionModelEditorPanel(
                editingModel: nil,
                customModelManager: customModelManager,
                onAdded: {
                    transcriptionModelManager.refreshAllAvailableModels()
                    navigation.dismissPage(.customTranscriptionModel(nil))
                }
            )
        }
    }
}

/// Page for adding (`nil` ID) or editing a custom enhancement model.
struct CustomEnhancementModelPage: View {
    let providerID: UUID?

    @ObservedObject private var manager = CustomAIProviderManager.shared
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        if let providerID {
            if let provider = manager.providers.first(where: { $0.id == providerID }) {
                CustomEnhancementModelEditorPanel(
                    editingProvider: provider,
                    manager: manager,
                    onAdded: {},
                    onDelete: {
                        manager.deleteProvider(provider)
                        navigation.dismissPage(.customEnhancementModel(providerID))
                    }
                )
            } else {
                ContentUnavailableView {
                    Label("Model Not Found", systemImage: "sparkles")
                } description: {
                    Text("This model was deleted.")
                }
            }
        } else {
            CustomEnhancementModelEditorPanel(
                editingProvider: nil,
                manager: manager,
                onAdded: { navigation.dismissPage(.customEnhancementModel(nil)) }
            )
        }
    }
}
