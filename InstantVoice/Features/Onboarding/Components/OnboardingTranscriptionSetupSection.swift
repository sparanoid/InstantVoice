import AppKit
import SwiftUI

/// Chooses between the local Parakeet model and a cloud provider, as a form section with a scope control above it.
struct OnboardingTranscriptionSetupSection: View {
    let localModel: FluidAudioModel?
    let setupKind: OnboardingTranscriptionSetupKind
    let providerOptions: [any CloudProvider]
    @Binding var selectedProviderKey: String
    let isLocalDownloaded: Bool
    let isLocalDownloading: Bool
    let localDownloadStatus: FluidAudioDownloadStatus?
    let onSelectSetupKind: (OnboardingTranscriptionSetupKind) -> Void
    let onDownloadLocalModel: (FluidAudioModel) -> Void
    let onCancelLocalModelDownload: (FluidAudioModel) -> Void
    let onVerificationChanged: () -> Void

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationDetailMessage: String?
    @State private var verificationSucceeded = false
    @State private var isLoadingOpenRouterModels = false

    private var selectedProvider: (any CloudProvider)? {
        providerOptions.first {
            $0.providerKey.caseInsensitiveCompare(selectedProviderKey) == .orderedSame
        } ?? providerOptions.first
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSelectedProviderConnected: Bool {
        guard let selectedProvider else { return false }
        return APIKeyManager.shared.hasAPIKey(forProvider: selectedProvider.providerKey)
    }

    private var canVerify: Bool {
        !trimmedAPIKey.isEmpty && !isVerifying
    }

    var body: some View {
        Section {
            switch setupKind {
            case .local:
                localSetup
            case .cloud:
                cloudSetup
            }
        } header: {
            setupKindPicker
        } footer: {
            if setupKind == .cloud && !isSelectedProviderConnected {
                OnboardingVerificationStatus(
                    message: verificationMessage,
                    detail: verificationDetailMessage,
                    succeeded: verificationSucceeded
                )
            }
        }
        .onAppear {
            if selectedProviderKey.isEmpty, let selectedProvider {
                selectedProviderKey = selectedProvider.providerKey
            }
            refreshVerificationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            refreshVerificationState()
        }
        .onChange(of: selectedProviderKey) { _, _ in
            handleProviderChange()
        }
        .onChange(of: apiKey) { _, _ in
            guard !apiKey.isEmpty else { return }
            verificationSucceeded = false
            verificationMessage = nil
            verificationDetailMessage = nil
        }
        .task(id: "\(setupKind.rawValue):\(selectedProviderKey)") {
            await loadOpenRouterModelsIfNeeded()
        }
    }

    private var setupKindPicker: some View {
        Picker(
            "Transcription",
            selection: Binding(get: { setupKind }, set: onSelectSetupKind)
        ) {
            ForEach(OnboardingTranscriptionSetupKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var localSetup: some View {
        if let localModel {
            TranscriptionModelDownloadRow(
                model: localModel,
                isDownloaded: isLocalDownloaded,
                isDownloading: isLocalDownloading,
                status: localDownloadStatus,
                onDownload: {
                    onDownloadLocalModel(localModel)
                },
                onCancel: {
                    onCancelLocalModelDownload(localModel)
                }
            )
        } else {
            Label("Parakeet V3 is not available.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cloudSetup: some View {
        Picker("Provider", selection: $selectedProviderKey) {
            ForEach(providerOptions.map(\.providerKey), id: \.self) { providerKey in
                Text(providerKey).tag(providerKey)
            }
        }

        if isSelectedProviderConnected {
            LabeledContent(apiKeyLabel) {
                Label("Connection verified.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if selectedProvider?.modelProvider == .openRouter, selectedProvider?.models.isEmpty == true {
                LabeledContent("Models") {
                    if isLoadingOpenRouterModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Refresh") {
                            Task { await loadOpenRouterModelsIfNeeded() }
                        }
                    }
                }
            }
        } else {
            SecureField(text: $apiKey, prompt: Text(apiKeyPlaceholder)) {
                Text(apiKeyLabel)
            }
            .onSubmit {
                if canVerify { verifyAPIKey() }
            }

            OnboardingVerificationActions(
                apiKeyURL: apiKeyURL,
                isVerifying: isVerifying,
                canVerify: canVerify,
                onVerify: verifyAPIKey
            )
        }
    }

    private var apiKeyLabel: String {
        guard let selectedProvider else { return String(localized: "API Key") }
        return String(format: String(localized: "%@ API Key"), selectedProvider.providerKey)
    }

    private var apiKeyPlaceholder: String {
        guard let selectedProvider else { return String(localized: "Paste API key") }
        return String(format: String(localized: "Paste %@ API key"), selectedProvider.providerKey)
    }

    private var apiKeyURL: URL? {
        guard let selectedProvider else { return nil }
        return descriptor(for: selectedProvider).apiConsoleURL
    }

    private func refreshVerificationState() {
        verificationSucceeded = isSelectedProviderConnected
        verificationMessage =
            verificationSucceeded
            ? selectedProvider.map {
                String(format: String(localized: "%@ connection verified."), $0.providerKey)
            }
            : nil
        verificationDetailMessage = nil

        if verificationSucceeded {
            apiKey = ""
        }
    }

    private func handleProviderChange() {
        apiKey = ""
        isVerifying = false
        refreshVerificationState()
        onVerificationChanged()
    }

    private func verifyAPIKey() {
        let key = trimmedAPIKey
        guard let selectedProvider, !key.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationDetailMessage = nil
        verificationSucceeded = false
        let providerKey = selectedProvider.providerKey

        Task {
            let result = await selectedProvider.verifyAPIKey(key)

            await MainActor.run {
                isVerifying = false

                guard self.selectedProvider?.providerKey == providerKey else {
                    refreshVerificationState()
                    onVerificationChanged()
                    return
                }

                verificationSucceeded = result.isValid

                if result.isValid {
                    guard APIKeyManager.shared.saveAPIKey(key, forProvider: providerKey) else {
                        verificationSucceeded = false
                        verificationMessage = String(
                            localized: "The key worked, but InstantVoice could not save it securely.")
                        verificationDetailMessage = nil
                        onVerificationChanged()
                        return
                    }

                    transcriptionModelManager.refreshAllAvailableModels()
                    apiKey = ""
                    verificationMessage = String(format: String(localized: "%@ connection verified."), providerKey)
                    verificationDetailMessage = nil
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                    Task { await loadOpenRouterModelsIfNeeded() }
                } else {
                    verificationMessage = String(
                        localized: "Could not verify this API key. Check the key and try again.")
                    verificationDetailMessage = result.errorMessage
                }

                onVerificationChanged()
            }
        }
    }

    private func loadOpenRouterModelsIfNeeded() async {
        guard setupKind == .cloud,
            selectedProvider?.modelProvider == .openRouter,
            selectedProvider?.models.isEmpty == true,
            isSelectedProviderConnected,
            !isLoadingOpenRouterModels
        else { return }

        isLoadingOpenRouterModels = true
        await transcriptionModelManager.refreshOpenRouterCatalog()
        isLoadingOpenRouterModels = false
        onVerificationChanged()
    }

    private func descriptor(for provider: any CloudProvider) -> ProviderDescriptor {
        ProviderDescriptor(
            displayName: provider.providerKey,
            providerKey: provider.providerKey,
            aiProvider: nil,
            cloudProvider: provider
        )
    }
}

/// The row under an API key field: a link to get a key, and the button that tests it.
struct OnboardingVerificationActions: View {
    let apiKeyURL: URL?
    let isVerifying: Bool
    let canVerify: Bool
    let onVerify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let apiKeyURL {
                Link(destination: apiKeyURL) {
                    HStack(spacing: 3) {
                        Text("Get API key")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .font(.system(size: 12))
            }

            Spacer(minLength: 12)

            if isVerifying {
                ProgressView()
                    .controlSize(.small)
            }

            Button(isVerifying ? LocalizedStringKey("Testing...") : LocalizedStringKey("Test connection"), action: onVerify)
                .disabled(!canVerify)
        }
    }
}

/// What testing an API key found, under the section; a prompt until the key has been tested.
struct OnboardingVerificationStatus: View {
    let message: String?
    let detail: String?
    let succeeded: Bool

    var body: some View {
        if let message {
            VStack(alignment: .leading, spacing: 2) {
                Label(message, systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(succeeded ? Color.green : Color.red)

                if let detail, !succeeded {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        } else {
            Text("Test the connection to continue.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
