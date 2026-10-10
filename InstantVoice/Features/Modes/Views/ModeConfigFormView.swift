import SwiftUI

struct ModeConfigFormView: View {
    let modeID: UUID
    let modeManager: ModeManager
    @Binding var draft: ModeConfigDraft
    let validationErrors: [ModeValidationError]
    let onDelete: () -> ModeRemovalResult
    let openPromptEditor: (PromptEditorView.Mode) -> Void

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var modeWarmupStore: ModeFormWarmupStore
    @FocusState private var isNameFieldFocused: Bool

    @State private var isShowingIconPicker = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDefaultModeDeleteAlert = false
    @State private var isContextAwarenessExpanded = false

    private var isDeletingDefaultMode: Bool {
        modeManager.getConfiguration(with: draft.id)?.isDefault == true
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { modeManager.getConfiguration(with: modeID)?.isEnabled ?? true },
            set: { isOn in
                if isOn {
                    modeManager.enableConfiguration(with: modeID)
                } else {
                    modeManager.disableConfiguration(with: modeID)
                }
            }
        )
    }

    private var effectiveModelName: String? {
        draft.selectedTranscriptionModelName
    }

    private var warmupSnapshot: ModeFormWarmupSnapshot {
        modeWarmupStore.snapshot
    }

    private var selectedTranscriptionModel: (any TranscriptionModel)? {
        warmupSnapshot.transcriptionModel(named: effectiveModelName)
    }

    private var selectedPrompt: CustomPrompt? {
        guard let selectedPromptId = draft.selectedPromptId else { return nil }
        return warmupSnapshot.prompts.first { $0.id == selectedPromptId }
    }

    private var aiProviderOptions: [AIProvider] {
        warmupSnapshot.connectedAIProviders
    }

    private var configuredSelectedAIProvider: AIProvider? {
        let selectedProvider: AIProvider?
        if let providerName = draft.selectedAIProvider {
            selectedProvider = AIProvider(rawValue: providerName)
        } else {
            selectedProvider = aiProviderOptions.first
        }

        guard let selectedProvider,
            selectedProvider.supportsEnhancement,
            aiProviderOptions.contains(selectedProvider)
        else { return nil }

        return selectedProvider
    }

    var body: some View {
        formContent
            .onAppear {
                applyInstantVoiceRefineRulesIfNeeded()
                applyOutputRules()
                if ModeEditorFocus.consumeNameFocusRequest(for: modeID) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNameFieldFocused = true
                    }
                }
            }
            .onChange(of: draft.isAIEnhancementEnabled) { _, _ in
                applyOutputRules()
            }
            .onChange(of: draft.selectedPromptId) { _, _ in
                applyOutputRules()
            }
            .onChange(of: draft.selectedAIProvider) { _, _ in
                applyOutputRules()
            }
            .onChange(of: draft.selectedAIModel) { _, _ in
                applyOutputRules()
            }
    }

    @ViewBuilder
    private var validationSection: some View {
        if !validationErrors.isEmpty {
            Section {
                ForEach(validationErrors) { error in
                    Label {
                        Text(error.localizedDescription)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
        }
    }

    private var identitySection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    isShowingIconPicker.toggle()
                } label: {
                    ModeIconTile(icon: draft.icon, seed: modeID, size: 40)
                }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .popover(isPresented: $isShowingIconPicker, arrowEdge: .bottom) {
                    ModeIconPickerView(
                        selectedIcon: $draft.icon,
                        isPresented: $isShowingIconPicker
                    )
                }

                TextField("Mode name", text: $draft.name, prompt: Text("Mode name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(.title3.weight(.semibold))
                    .focused($isNameFieldFocused)
            }
            .padding(.vertical, 2)

            if !isDeletingDefaultMode {
                Toggle("Enabled", isOn: isEnabled)
            }
        }
    }

    /// Sits below the last section, outside its box, like the delete buttons on System Settings pages.
    private var deleteButton: some View {
        HStack {
            Spacer()
            Button("Delete Mode…", role: .destructive) {
                if isDeletingDefaultMode {
                    isShowingDefaultModeDeleteAlert = true
                } else {
                    isShowingDeleteConfirmation = true
                }
            }
        }
        .padding(.top, 8)
    }

    private var formContent: some View {
        Form {
            validationSection
            identitySection
            ModeTriggerSection(
                appConfigs: $draft.appConfigs,
                websiteConfigs: $draft.websiteConfigs,
                triggerGroups: $draft.triggerGroups,
                triggerWords: $draft.triggerWords,
                modeId: draft.id,
                cleanURL: modeManager.cleanURL
            )
            transcriptionSection
            aiEnhancementSection
            advancedSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete Mode?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if case .blockedDefault = onDelete() {
                    isShowingDefaultModeDeleteAlert = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                    modeManager.getConfiguration(with: draft.id)?.name ?? draft.name))
        }
        .alert(
            "Default Mode Can’t Be Deleted",
            isPresented: $isShowingDefaultModeDeleteAlert,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(
                    String(
                        format: String(
                            localized: "'%@' is the default mode. Set another mode as default before deleting it."
                        ),
                        draft.name
                    )
                )
            }
        )
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
            if warmupSnapshot.usableTranscriptionModels.isEmpty {
                Text(
                    "No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab."
                )
                .foregroundColor(.secondary)
            } else {
                let availableModels = warmupSnapshot.usableTranscriptionModels
                let openRouterModels = availableModels.filter { $0.provider == .openRouter }

                LabeledContent("Model") {
                    Menu {
                        ForEach(availableModels.filter { $0.provider != .openRouter }, id: \.selectionKey) { model in
                            transcriptionModelMenuItem(model)
                        }

                        if !openRouterModels.isEmpty {
                            Menu("OpenRouter") {
                                ForEach(openRouterModels, id: \.selectionKey) { model in
                                    transcriptionModelMenuItem(model)
                                }
                            }
                        }
                    } label: {
                        Text(
                            availableModels.first { $0.selectionKey == draft.selectedTranscriptionModelName }?.displayName
                                ?? String(localized: "Unavailable")
                        )
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                }
                .onChange(of: draft.selectedTranscriptionModelName) { _, newModelName in
                    if let modelName = newModelName,
                        let model = warmupSnapshot.transcriptionModel(named: modelName)
                    {
                        draft.isRealtimeTranscriptionEnabled = TranscriptionRealtimeSupport.isAvailable(for: model)
                        draft.useCompatibleLanguage(for: model)
                    }
                }

                realtimeToggle
            }

            languagePicker

            additionalLanguagesPicker

            ExpandableSettingsRow(
                title: "Transcription Formatting",
                isExpanded: $draft.isTranscriptionFormattingExpanded
            ) {
                Toggle(isOn: $draft.isTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Paragraph breaks")
                        InfoTip("Apply intelligent text formatting to break large block of text into paragraphs.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptionModelMenuItem(_ model: any TranscriptionModel) -> some View {
        Button {
            draft.selectedTranscriptionModelName = model.selectionKey
        } label: {
            if draft.selectedTranscriptionModelName == model.selectionKey {
                Label(model.displayName, systemImage: "checkmark")
            } else {
                Text(model.displayName)
            }
        }
    }

    @ViewBuilder
    private var realtimeToggle: some View {
        if let model = selectedTranscriptionModel,
            TranscriptionRealtimeSupport.isAvailable(for: model)
        {
            Toggle("Real-time", isOn: $draft.isRealtimeTranscriptionEnabled)
                .disabled(TranscriptionRealtimeSupport.isRequired(for: model))
                .onAppear {
                    if TranscriptionRealtimeSupport.isRequired(for: model) {
                        draft.isRealtimeTranscriptionEnabled = true
                    }
                }
                .onChange(of: draft.isRealtimeTranscriptionEnabled) { _, _ in
                    draft.useCompatibleLanguage(for: model)
                }
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        if let selectedModel = effectiveModelName,
            let modelInfo = warmupSnapshot.transcriptionModel(named: selectedModel),
            modelInfo.supportedLanguages.count > 1
        {
            let languageBinding = Binding<String?>(
                get: { effectiveLanguage(for: modelInfo) },
                set: { draft.selectedLanguage = $0 }
            )

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Language")
                }

                Spacer(minLength: 12)

                if modelInfo.provider == .nativeApple {
                    NativeAppleLanguageAssetControl(
                        localeIdentifier: effectiveLanguage(for: modelInfo),
                        isVisible: true,
                        startsDownloadAutomatically: true
                    )
                    .layoutPriority(1)
                    .frame(width: 28, height: 24)
                }

                Picker("", selection: languageBinding) {
                    ForEach(
                        availableLanguages(for: modelInfo).sorted(by: {
                            if $0.key == "auto" { return true }
                            if $1.key == "auto" { return false }
                            return $0.value < $1.value
                        }), id: \.key
                    ) { key, value in
                        Text(value).tag(key as String?)
                    }
                }
                .labelsHidden()
            }
            .onAppear {
                draft.selectedLanguage = effectiveLanguage(for: modelInfo)
            }
        } else if let selectedModel = effectiveModelName,
            let modelInfo = warmupSnapshot.transcriptionModel(named: selectedModel)
        {
            EmptyView()
                .onAppear {
                    draft.selectedLanguage = effectiveLanguage(for: modelInfo)
                }
        }
    }

    /// Extra languages for providers that accept several, shown once a specific main language is chosen.
    @ViewBuilder
    private var additionalLanguagesPicker: some View {
        if let modelInfo = selectedTranscriptionModel,
            TranscriptionLanguageSupport.supportsMultipleLanguages(modelInfo)
        {
            let primaryLanguage = effectiveLanguage(for: modelInfo)

            if primaryLanguage != "auto" {
                let options = availableLanguages(for: modelInfo)
                    .filter { $0.key != "auto" && $0.key != primaryLanguage }
                    .sorted { $0.value < $1.value }
                let selectedNames = options.filter { draft.additionalLanguages.contains($0.key) }.map(\.value)

                LabeledContent {
                    Menu {
                        ForEach(options, id: \.key) { code, name in
                            Toggle(name, isOn: additionalLanguageBinding(for: code))
                        }
                    } label: {
                        Text(selectedNames.isEmpty ? String(localized: "None") : selectedNames.joined(separator: ", "))
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                } label: {
                    HStack(spacing: 4) {
                        Text("Also Recognize")
                        InfoTip(
                            "Soniox transcribes speech in the main language and these, and avoids others. Each extra language can lower accuracy, so add only ones you speak."
                        )
                    }
                }
            }
        }
    }

    private func additionalLanguageBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { draft.additionalLanguages.contains(code) },
            set: { isOn in
                var languages = draft.additionalLanguages.filter { $0 != code }
                if isOn {
                    languages.append(code)
                }
                draft.additionalLanguages = languages
            }
        )
    }

    private var aiEnhancementSection: some View {
        Section("AI Enhancement") {
            Toggle("AI Enhancement", isOn: $draft.isAIEnhancementEnabled)
                .onChange(of: draft.isAIEnhancementEnabled) { _, newValue in
                    if newValue {
                        if configuredSelectedAIProvider == nil {
                            draft.selectedAIProvider = aiProviderOptions.first?.rawValue
                            draft.selectedAIModel = nil
                        }
                        if draft.selectedAIModel == nil,
                            let provider = configuredSelectedAIProvider,
                            provider != .localCLI
                        {
                            draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                        }
                        if configuredSelectedAIProvider != .instantVoiceRefine,
                            draft.selectedPromptId == nil
                        {
                            draft.selectedPromptId = warmupSnapshot.firstPromptId
                        }
                        if configuredSelectedAIProvider == .ollama {
                            aiService.refreshOllamaAvailabilityInBackground()
                        }
                    }
                }

            let providerBinding = Binding<AIProvider>(
                get: {
                    configuredSelectedAIProvider ?? aiProviderOptions.first ?? .gemini
                },
                set: { newValue in
                    draft.selectedAIProvider = newValue.rawValue
                    draft.selectedAIModel = nil
                }
            )

            if draft.isAIEnhancementEnabled {
                let providerOptions = aiProviderOptions

                if providerOptions.isEmpty {
                    LabeledContent("AI Provider") {
                        Text("No providers connected")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    Picker("AI Provider", selection: providerBinding) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: draft.selectedAIProvider) { _, newValue in
                        if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                            switch provider {
                            case .localCLI:
                                draft.selectedAIModel = nil
                            case .instantVoiceRefine:
                                applyInstantVoiceRefineRules()
                            case .ollama:
                                if draft.selectedAIModel == nil || draft.selectedAIModel?.isEmpty == true {
                                    draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                                }
                                aiService.refreshOllamaAvailabilityInBackground()
                            default:
                                draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                            }

                            if provider != .instantVoiceRefine,
                                draft.selectedPromptId == nil
                            {
                                draft.selectedPromptId = warmupSnapshot.firstPromptId
                            }
                        }
                    }
                }

                if let provider = configuredSelectedAIProvider {
                    aiModelPicker(for: provider)
                    if provider != .instantVoiceRefine {
                        promptPicker
                        contextAwarenessRow
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func aiModelPicker(for provider: AIProvider) -> some View {
        if provider == .localCLI {
            LabeledContent("AI Model") {
                Text("Default")
                    .foregroundColor(.secondary)
            }
            .onAppear {
                draft.selectedAIModel = nil
            }
        } else if provider == .instantVoiceRefine {
            LabeledContent("AI Model") {
                Text(InstantVoiceRefineService.modelName)
                    .foregroundColor(.secondary)
            }
            .onAppear {
                applyInstantVoiceRefineRules()
            }
        } else {
            let models = aiModelOptions(for: provider)
            if models.isEmpty {
                LabeledContent("AI Model") {
                    Text(
                        provider == .openRouter
                            ? LocalizedStringKey("No models loaded") : LocalizedStringKey("No models available")
                    )
                    .foregroundColor(.secondary)
                    .italic()
                }
            } else {
                let modelBinding = Binding<String>(
                    get: {
                        if let model = draft.selectedAIModel, !model.isEmpty { return model }
                        return warmupSnapshot.selectedModel(for: provider)
                    },
                    set: { newModelValue in
                        draft.selectedAIModel = newModelValue
                    }
                )

                if provider.supportsCustomModelID {
                    EnhancementModelPicker(
                        title: "AI Model",
                        provider: provider,
                        models: models,
                        savedCustomModelID: aiService.customModelID(for: provider),
                        draftModel: modelBinding
                    )
                } else {
                    Picker("AI Model", selection: modelBinding) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if provider == .openRouter {
                    Button("Refresh Models") {
                        Task { await aiService.fetchOpenRouterModels() }
                    }
                    .help("Refresh models")
                }
            }
        }
    }

    private func aiModelOptions(for provider: AIProvider) -> [String] {
        var models = warmupSnapshot.availableModels(for: provider)

        if let selectedModel = draft.selectedAIModel,
            !selectedModel.isEmpty,
            !models.contains(selectedModel),
            !provider.supportsCustomModelID
        {
            models.insert(selectedModel, at: 0)
        }

        return models
    }

    private var promptPicker: some View {
        HStack(spacing: 8) {
            Text("Prompt")

            Spacer(minLength: 12)

            if warmupSnapshot.prompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Picker("", selection: $draft.selectedPromptId) {
                    ForEach(warmupSnapshot.prompts) { prompt in
                        Text(prompt.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(prompt.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if let selectedPrompt {
                Button {
                    openPromptEditor(.edit(selectedPrompt))
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }

            AddIconButton(helpText: "Add prompt") {
                openPromptEditor(.add)
            }
        }
    }

    private var contextAwarenessRow: some View {
        ExpandableSettingsRow(
            title: "Context Awareness",
            isExpanded: $isContextAwarenessExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                contextToggles
            }
        }
    }

    private var contextToggles: some View {
        Group {
            Toggle(isOn: $draft.useSelectedTextContext) {
                HStack(spacing: 4) {
                    Text("Selected Text")
                    InfoTip("Use selected text from the active app as context for this mode.")
                }
            }

            Toggle(isOn: $draft.useClipboardContext) {
                HStack(spacing: 4) {
                    Text("Clipboard")
                    InfoTip("Use clipboard text as context for this mode.")
                }
            }

            Toggle(isOn: $draft.useScreenCapture) {
                HStack(spacing: 4) {
                    Text("Screen")
                    InfoTip("Use captured on-screen text as context for this mode.")
                }
            }
        }
    }

    private var outputChoices: [ModeOutputMode] {
        ModeOutputMode.choices(canRespond: canRespond)
    }

    private var canRespond: Bool {
        draft.isAIEnhancementEnabled
            && selectedPrompt != nil
            && configuredSelectedAIProvider != nil
            && configuredSelectedAIProvider != .instantVoiceRefine
    }

    private func applyOutputRules() {
        draft.applyOutputRules(canRespond: canRespond)
    }

    private func applyInstantVoiceRefineRulesIfNeeded() {
        guard configuredSelectedAIProvider == .instantVoiceRefine else { return }
        applyInstantVoiceRefineRules()
    }

    private func applyInstantVoiceRefineRules() {
        draft.selectedAIModel = InstantVoiceRefineService.modelName
        applyOutputRules()
    }

    private var advancedSection: some View {
        Section {
            Picker("Output", selection: $draft.outputMode) {
                ForEach(outputChoices, id: \.self) { outputMode in
                    Label(outputMode.displayName, systemImage: outputMode.iconName)
                        .tag(outputMode)
                }
            }
            .onChange(of: draft.outputMode) { _, _ in
                applyOutputRules()
            }

            if draft.outputMode != .respond {
                Toggle(isOn: $draft.isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default mode is used when no specific app or website matches are found.")
                    }
                }
            }

            if draft.outputMode == .customCommand {
                customCommandControls
            }
        } header: {
            Text("Advanced")
        } footer: {
            deleteButton
        }
    }

    private var customCommandControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Command")
                InfoTip(
                    LocalizedStringKey(
                        "Runs locally with your user permissions. The final transcript is sent on stdin and exposed as INSTANTVOICE_TRANSCRIPT."
                    ))
                Spacer()
                Menu {
                    ForEach(CustomCommandTemplate.allCases) { template in
                        Button(template.displayName) {
                            draft.customCommand = template.command
                        }
                    }
                } label: {
                    Label("Template", systemImage: "doc.on.doc")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextEditor(text: $draft.customCommand)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.Surface.control)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.Border.control.opacity(0.4), lineWidth: 1)
                )

        }
    }

    private func availableLanguages(for model: any TranscriptionModel) -> [String: String] {
        TranscriptionLanguageSupport.languages(for: model, realtimeEnabled: draft.isRealtimeTranscriptionEnabled)
    }

    private func effectiveLanguage(for model: any TranscriptionModel) -> String {
        TranscriptionLanguageSupport.validLanguageOrFallback(
            draft.selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage"),
            for: model,
            realtimeEnabled: draft.isRealtimeTranscriptionEnabled
        )
    }

}
