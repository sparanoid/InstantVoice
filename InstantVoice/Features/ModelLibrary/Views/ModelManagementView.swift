import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ModelFilter: String, CaseIterable, Identifiable {
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"

    var id: String { self.rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .local:
            return "Local"
        case .cloud:
            return "Cloud"
        case .custom:
            return "Custom"
        }
    }
}

struct ModelManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @StateObject private var customAIProviderManager = CustomAIProviderManager.shared
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared
    private let instantVoiceRefineService = InstantVoiceRefineService.shared

    @EnvironmentObject private var navigation: MainWindowNavigation
    @State private var selectedFilter: ModelFilter = .local

    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if SystemArchitecture.isIntelMac {
                    intelMacWarningBanner
                }

                availableModelsSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelFilterPicker
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.push(.modelSettings)
                } label: {
                    Label("Model Settings", systemImage: "gearshape")
                }
                .help("Model Settings")
            }
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedFilter {
            case .local:
                localModelsSection
            case .cloud:
                CloudProviderManagementView(
                    selectedProviderID: nil,
                    onSelectProvider: { descriptor in
                        navigation.push(.cloudProvider(descriptor.id))
                    }
                )
                .environmentObject(aiService)
                .environmentObject(transcriptionModelManager)
            case .custom:
                CustomProviderManagementView(
                    customModelManager: customModelManager,
                    customAIProviderManager: customAIProviderManager,
                    onAddTranscriptionModel: {
                        navigation.push(.customTranscriptionModel(nil))
                    },
                    onEditTranscriptionModel: { model in
                        navigation.push(.customTranscriptionModel(model.id))
                    },
                    onDeleteTranscriptionModel: { model in
                        confirmDeleteCustomModel(model)
                    },
                    onAddEnhancementModel: {
                        navigation.push(.customEnhancementModel(nil))
                    },
                    onEditEnhancementModel: { provider in
                        navigation.push(.customEnhancementModel(provider.id))
                    },
                    onDeleteEnhancementModel: { provider in
                        confirmDeleteCustomEnhancementModel(provider)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelFilterPicker: some View {
        Picker("Model Catalog", selection: filterSelection) {
            ForEach(ModelFilter.allCases) { filter in
                Text(filter.title)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var filterSelection: Binding<ModelFilter> {
        Binding(
            get: { selectedFilter },
            set: { newValue in
                withAnimation(.smooth(duration: 0.25)) {
                    selectedFilter = newValue
                }
            }
        )
    }

    private var localModelsSection: some View {
        VStack(spacing: 12) {
            InstantVoiceRefineModelCardView(
                service: instantVoiceRefineService,
                deleteAction: deleteInstantVoiceRefineModel
            )

            ForEach(appleSpeechModels, id: \.id) { model in
                localModelCard(model)
            }

            ForEach(downloadableLocalModels, id: \.id) { model in
                localModelCard(model)
            }

            importLocalModelButton

            LocalEnhancementServiceManagementView()
                .environmentObject(aiService)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func localModelCard(_ model: any TranscriptionModel) -> some View {
        let isWarming =
            (model as? WhisperModel).map { whisperModel in
                warmupCoordinator.isWarming(modelNamed: whisperModel.name)
            } ?? false

        return ModelCardView(
            model: model,
            isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
            downloadProgress: whisperModelManager.downloadProgress,
            modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
            isWarming: isWarming,
            deleteAction: {
                deleteLocalModel(model)
            },
            downloadAction: {
                if let whisperModel = model as? WhisperModel {
                    whisperModelManager.startDownload(whisperModel)
                }
            },
            cancelDownloadAction: {
                if let whisperModel = model as? WhisperModel {
                    whisperModelManager.cancelDownload(whisperModel)
                }
            }
        )
    }

    private var importLocalModelButton: some View {
        HStack(spacing: 8) {
            Button(action: { presentImportPanel() }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Local Model…")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(AppMaterialCardBackground(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            InfoTip(
                "Add a custom fine-tuned whisper model to use with InstantVoice. Select the downloaded .bin file.",
                learnMoreURL: "https://tryvoiceink.com/docs/custom-local-whisper-models"
            )
            .help("Read more about custom local models")
        }
    }

    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Status.warningStrong)

            Text("Local models don't work reliably on Intel Macs")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text("Use Cloud")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AppTheme.Status.warningStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.Status.warningStrong.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Status.warningStrong.opacity(0.08))
        .cornerRadius(8)
    }

    private var localModels: [any TranscriptionModel] {
        transcriptionModelManager.allAvailableModels.filter {
            ($0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio
                || $0.provider == .transcribeCpp)
                && transcriptionModelManager.isAvailableOnCurrentOS($0)
        }
    }

    private var appleSpeechModels: [any TranscriptionModel] {
        localModels.filter { $0.provider == .nativeApple }
    }

    private var downloadableLocalModels: [any TranscriptionModel] {
        localModels.filter { $0.provider != .nativeApple }
    }

    private func deleteLocalModel(_ model: any TranscriptionModel) {
        guard let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) else {
            return
        }

        Task {
            await whisperModelManager.deleteModel(downloadedModel)
        }
    }

    private func confirmDeleteCustomModel(_ model: CustomCloudModel) {
        alertTitle = String(localized: "Delete Custom Model")
        alertMessage = String(
            format: String(localized: "Are you sure you want to delete the custom model '%@'?"),
            model.displayName
        )
        deleteActionClosure = {
            customModelManager.removeCustomModel(withId: model.id)
            transcriptionModelManager.refreshAllAvailableModels()
            navigation.removeFromHistory(.customTranscriptionModel(model.id))
        }
        isShowingDeleteAlert = true
    }

    private func deleteInstantVoiceRefineModel() {
        Task {
            await instantVoiceRefineService.deleteModel()
        }
    }

    private func confirmDeleteCustomEnhancementModel(_ provider: CustomAIProviderConfig) {
        alertTitle = String(localized: "Delete Custom Enhancement Model")
        alertMessage = String(
            format: String(localized: "Are you sure you want to delete the custom enhancement model '%@'?"),
            provider.name
        )
        deleteActionClosure = {
            customAIProviderManager.deleteProvider(provider)
            navigation.removeFromHistory(.customEnhancementModel(provider.id))
        }
        isShowingDeleteAlert = true
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = String(localized: "Select a Whisper ggml .bin model")
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }
}
