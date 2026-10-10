import AppKit
import LLMkit
import SwiftUI

struct ProviderDetailPanel: View {
    let descriptor: ProviderDescriptor

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var isRefreshingModels = false
    @State private var modelRefreshError: String?
    @State private var verificationMessage: String?
    @State private var verificationDetailMessage: String?
    @State private var verificationSucceeded = false
    @State private var isShowingRemoveAPIKeyConfirmation = false
    @State private var activeDescriptorID = ""

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var iconName: String {
        if descriptor.hasTranscription && descriptor.hasEnhancement { return "rectangle.2.swap" }
        if descriptor.hasTranscription { return "captions.bubble.fill" }
        return "sparkles"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                apiKeySection

                if descriptor.hasTranscription {
                    transcriptionModelsSection
                }

                if descriptor.hasEnhancement {
                    enhancementModelsSection
                }

                if !otherModels.isEmpty {
                    otherModelsSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(verbatim: descriptor.displayName))
        .onAppear(perform: loadSavedAPIKey)
        .onChange(of: descriptor.id) { _, _ in
            resetProviderState()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProviderBrandIcon(
                descriptor: descriptor,
                fallbackSystemImage: iconName,
                isSelected: false,
                size: 48,
                iconSize: 22
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.displayName)
                    .font(.title2.weight(.semibold))

                ProviderStatusBadge(
                    title: isConfigured ? "Connected" : "Not connected",
                    color: isConfigured ? AppTheme.Status.positive : Color.secondary
                )
            }

            Spacer()
        }
    }

    private var apiKeySection: some View {
        ProviderConfigurationGroup(title: "Connection") {
            VStack(alignment: .leading, spacing: 8) {
                if isConfigured {
                    verifiedAPIKeyRow
                } else {
                    apiKeyInputRow
                }

                verificationStatusMessage
            }
        }
    }

    @ViewBuilder
    private var verificationStatusMessage: some View {
        if let verificationMessage {
            VStack(alignment: .leading, spacing: 3) {
                Text(verificationMessage)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(verificationSucceeded ? AppTheme.Status.positive : AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)

                if let verificationDetailMessage, !verificationSucceeded {
                    Text(verificationDetailMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Status.error.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var verifiedAPIKeyRow: some View {
        HStack(spacing: 12) {
            providerDetailIcon("checkmark.seal.fill")

            VStack(alignment: .leading, spacing: 3) {
                Text("Key verified")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let obfuscatedKey {
                    Text(obfuscatedKey)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button {
                isShowingRemoveAPIKeyConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .help("Remove API key")
        }
        .padding(12)
        .background(ProviderSurface(cornerRadius: 8))
        .alert("Remove API Key?", isPresented: $isShowingRemoveAPIKeyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removeAPIKey()
            }
        } message: {
            Text(
                String(
                    format: String(localized: "This will remove your %@ API key. You can add it again later."),
                    descriptor.displayName))
        }
    }

    private var apiKeyInputRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerDetailIcon("key.fill")

                VStack(alignment: .leading, spacing: 3) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 8) {
                SecureField("Paste API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(isVerifying)
                    .onChange(of: apiKey) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        verificationMessage = nil
                        verificationDetailMessage = nil
                    }

                Button {
                    verifyAndSaveAPIKey()
                } label: {
                    HStack(spacing: 5) {
                        if isVerifying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal")
                        }
                        Text(isVerifying ? LocalizedStringKey("Verifying") : LocalizedStringKey("Verify"))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                .opacity(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying ? 0.55 : 1)
            }

            if let consoleURL = descriptor.apiConsoleURL {
                Link(destination: consoleURL) {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))

                        Text(String(format: String(localized: "Get %@ API Key"), descriptor.displayName))
                            .font(.system(size: 12, weight: .medium))

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(neutralLinkButtonBackground)
                }
                .buttonStyle(.plain)
                .help(String(format: String(localized: "Open %@ API key page"), descriptor.displayName))
            }
        }
        .padding(12)
        .background(ProviderSurface(cornerRadius: 8))
    }

    private func providerDetailIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.Surface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var neutralLinkButtonBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(AppTheme.Surface.control)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
            )
    }

    private var transcriptionModelsSection: some View {
        let models = descriptor.transcriptionModels

        return ProviderModelListSection(title: "Available Transcription Models") {
            if supportsModelRefresh {
                modelListStatus(modelCount: models.count)
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    modelRow(
                        title: model.displayName,
                        subtitle: transcriptionModelDetails(model),
                        trailing: nil,
                        systemImage: "captions.bubble.fill"
                    )

                    if index < models.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    /// What a transcription model handles, then what the provider says about it.
    private func transcriptionModelDetails(_ model: CloudModel) -> String {
        let capability: String
        switch (model.supportsBatch, model.supportsStreaming) {
        case (true, true): capability = String(localized: "Recorded audio and real-time")
        case (false, true): capability = String(localized: "Real-time only")
        default: capability = String(localized: "Recorded audio")
        }
        return model.description.isEmpty ? capability : "\(capability) · \(model.description)"
    }

    @ViewBuilder
    private var enhancementModelsSection: some View {
        if let provider = descriptor.aiProvider {
            let models = aiService.availableModels(for: provider)

            ProviderModelListSection(title: "Available Enhancement Models") {
                if supportsModelRefresh && !descriptor.hasTranscription {
                    modelListStatus(modelCount: models.count)
                }

                if provider != .openRouter && models.isEmpty {
                    Text("No models listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                            modelRow(
                                title: model,
                                subtitle: nil,
                                trailing: nil,
                                systemImage: "sparkles"
                            )

                            if index < models.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

            }
        }
    }

    /// The rest of what the provider lists, such as speech or embedding models, which the app doesn't use.
    private var otherModels: [ListedModel] {
        guard let listed = ProviderModelCatalog.shared.models(for: descriptor.providerKey) else { return [] }
        var usedModels = Set(descriptor.transcriptionModels.map(\.name))
        if let provider = descriptor.aiProvider {
            usedModels.formUnion(aiService.availableModels(for: provider))
        }
        return listed.filter { !usedModels.contains($0.id) }
    }

    private var otherModelsSection: some View {
        let models = otherModels

        return ProviderModelListSection(title: "Other Models") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                    modelRow(
                        title: model.id,
                        subtitle: model.displayName.flatMap { $0 == model.id ? nil : $0 },
                        trailing: nil,
                        systemImage: "square.stack.3d.up"
                    )

                    if index < models.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func openRouterModelAvailabilityText(for count: Int) -> String {
        if count == 0 {
            return String(localized: "No models loaded.")
        }

        return String(localized: "\(count) models available")
    }

    /// OpenRouter's public catalog, and providers whose list-models API the catalog can fetch.
    private var supportsModelRefresh: Bool {
        isOpenRouter || ProviderModelCatalog.supportsListing(descriptor.providerKey)
    }

    private var isOpenRouter: Bool {
        descriptor.providerKey == AIProvider.openRouter.rawValue
    }

    /// Fetching needs a saved key, except for OpenRouter's public catalog.
    private var canRefreshModels: Bool {
        isOpenRouter || isConfigured
    }

    private func modelListStatusText(modelCount: Int) -> String {
        if isOpenRouter {
            return openRouterModelAvailabilityText(for: modelCount)
        }
        if let fetchedAt = ProviderModelCatalog.shared.fetchedAt(for: descriptor.providerKey) {
            return String(
                format: String(localized: "Updated %@"), fetchedAt.formatted(.relative(presentation: .named)))
        }
        return String(localized: "Built-in model list")
    }

    private func modelListStatus(modelCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Redrawn each minute so "Updated 5 minutes ago" stays current.
                TimelineView(.everyMinute) { _ in
                    Text(modelListStatusText(modelCount: modelCount))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(modelCount == 0 ? .secondary : .primary)
                }

                Spacer()

                Button {
                    refreshModels()
                } label: {
                    HStack(spacing: 5) {
                        if isRefreshingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRefreshingModels ? LocalizedStringKey("Refreshing") : LocalizedStringKey("Refresh"))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshingModels || !canRefreshModels)
                .help(
                    canRefreshModels
                        ? String(format: String(localized: "Fetch the latest models from %@"), descriptor.displayName)
                        : String(localized: "Add an API key to fetch the latest models")
                )
            }

            if let modelRefreshError {
                Text(modelRefreshError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    private func modelRow(title: String, subtitle: String?, trailing: String?, systemImage: String) -> some View {
        HStack(spacing: 10) {
            modelTypeIcon(systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func modelTypeIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.Surface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var obfuscatedKey: String? {
        guard let savedKey = APIKeyManager.shared.getAPIKey(forProvider: descriptor.providerKey) else {
            return nil
        }

        let trimmedKey = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        if trimmedKey.count <= 8 {
            return String(repeating: "\u{2022}", count: trimmedKey.count)
        }

        return
            "\(trimmedKey.prefix(4))\(String(repeating: "\u{2022}", count: max(4, trimmedKey.count - 8)))\(trimmedKey.suffix(4))"
    }

    private func loadSavedAPIKey() {
        resetProviderState()
    }

    private func resetProviderState() {
        activeDescriptorID = descriptor.id
        verificationSucceeded = isConfigured
        apiKey = ""
        isVerifying = false
        isRefreshingModels = false
        modelRefreshError = nil
        verificationMessage = nil
        verificationDetailMessage = nil
        isShowingRemoveAPIKeyConfirmation = false
    }

    private func verificationModel(for provider: AIProvider) -> String {
        let selectedModel = aiService.selectedModel(for: provider)
        let models = aiService.availableModels(for: provider)

        if provider.supportsCustomModelID || models.contains(selectedModel) {
            return selectedModel
        }

        return models.first ?? selectedModel
    }

    private func verifyAndSaveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationDetailMessage = nil
        let providerID = descriptor.id

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            if let cloudProvider = descriptor.cloudProvider {
                result = await cloudProvider.verifyAPIKey(trimmedKey)
            } else if let provider = descriptor.aiProvider {
                result = await aiService.verifyAPIKey(
                    trimmedKey,
                    for: provider,
                    model: verificationModel(for: provider)
                )
            } else {
                result = (false, String(localized: "Provider is not supported"))
            }

            await MainActor.run {
                guard activeDescriptorID == providerID else { return }

                isVerifying = false
                verificationSucceeded = result.isValid

                if result.isValid {
                    APIKeyManager.shared.saveAPIKey(trimmedKey, forProvider: descriptor.providerKey)
                    if let provider = descriptor.aiProvider, aiService.selectedProvider == provider {
                        aiService.apiKey = trimmedKey
                        aiService.isAPIKeyValid = true
                    }
                    apiKey = ""
                    verificationMessage = nil
                    verificationDetailMessage = nil
                    transcriptionModelManager.refreshAllAvailableModels()
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                    if supportsModelRefresh && !isOpenRouter {
                        refreshModels()
                    }
                } else {
                    verificationMessage = String(
                        localized: "Could not verify this API key. Check the key and try again.")
                    verificationDetailMessage = result.errorMessage
                }
            }
        }
    }

    private func removeAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: descriptor.providerKey)
        apiKey = ""
        verificationSucceeded = false
        verificationMessage = nil
        verificationDetailMessage = nil
        transcriptionModelManager.refreshAllAvailableModels()
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }

    private func refreshModels() {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        modelRefreshError = nil
        let providerID = descriptor.id

        Task {
            var failure: String?
            if isOpenRouter {
                await aiService.fetchOpenRouterModels()
                await transcriptionModelManager.refreshOpenRouterCatalog()
            } else {
                do {
                    try await ProviderModelCatalog.shared.refresh(providerKey: descriptor.providerKey)
                } catch {
                    failure = error.localizedDescription
                }
            }
            await MainActor.run {
                guard activeDescriptorID == providerID else { return }
                isRefreshingModels = false
                modelRefreshError = failure.map {
                    String(format: String(localized: "Couldn't fetch models: %@"), $0)
                }
            }
        }
    }

}

/// A cloud provider's page: its API key and the models it offers.
struct CloudProviderPage: View {
    let providerID: String

    var body: some View {
        if let descriptor = ProviderDescriptor.cloudProvider(withID: providerID) {
            ProviderDetailPanel(descriptor: descriptor)
                .id(descriptor.id)
        } else {
            ContentUnavailableView {
                Label("Provider Not Found", systemImage: "cloud")
            } description: {
                Text("This provider is no longer available.")
            }
        }
    }
}
