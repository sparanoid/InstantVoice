import AppKit
import SwiftUI

/// Picks an AI provider and verifies its API key, as a form section.
struct AIProviderVerificationSection: View {
    @ObservedObject var aiService: AIService

    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider
    let onVerificationChanged: () -> Void

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationDetailMessage: String?
    @State private var verificationSucceeded = false

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSelectedProviderConnected: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: selectedProvider.rawValue)
    }

    var body: some View {
        Section {
            LabeledContent("Provider") {
                HStack(spacing: 8) {
                    if selectedProvider == .groq {
                        Text("Recommended")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if isSelectedProviderConnected {
                LabeledContent(String(format: String(localized: "%@ API Key"), selectedProvider.rawValue)) {
                    Label("Connection verified.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                SecureField(text: $apiKey, prompt: Text(apiKeyPlaceholder)) {
                    Text(String(format: String(localized: "%@ API Key"), selectedProvider.rawValue))
                }
                .onSubmit {
                    if canVerify { verifyAPIKey() }
                }

                OnboardingVerificationActions(
                    apiKeyURL: selectedProvider.apiKeyURL,
                    isVerifying: isVerifying,
                    canVerify: canVerify,
                    onVerify: verifyAPIKey
                )
            }
        } footer: {
            if !isSelectedProviderConnected {
                OnboardingVerificationStatus(
                    message: verificationMessage,
                    detail: verificationDetailMessage,
                    succeeded: verificationSucceeded
                )
            }
        }
        .onAppear { refreshVerificationState() }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            refreshVerificationState()
        }
        .onChange(of: selectedProvider) { _, _ in
            handleProviderChange()
        }
        .onChange(of: apiKey) { _, _ in
            guard !apiKey.isEmpty else { return }
            verificationSucceeded = false
            verificationMessage = nil
            verificationDetailMessage = nil
        }
    }

    private var canVerify: Bool {
        !trimmedAPIKey.isEmpty && !isVerifying
    }

    private var apiKeyPlaceholder: String {
        String(format: String(localized: "Paste %@ API key"), selectedProvider.rawValue)
    }

    private func refreshVerificationState() {
        verificationSucceeded = isSelectedProviderConnected
        verificationMessage =
            verificationSucceeded
            ? String(format: String(localized: "%@ connection verified."), selectedProvider.rawValue)
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
        guard !key.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationDetailMessage = nil
        verificationSucceeded = false

        Task {
            let provider = selectedProvider
            let modelName = provider.defaultModel
            let result = await aiService.verifyAPIKey(key, for: provider, model: modelName)

            await MainActor.run {
                isVerifying = false

                guard selectedProvider == provider else {
                    refreshVerificationState()
                    onVerificationChanged()
                    return
                }

                verificationSucceeded = result.isValid

                if result.isValid {
                    guard APIKeyManager.shared.saveAPIKey(key, forProvider: provider.rawValue) else {
                        verificationSucceeded = false
                        verificationMessage = String(
                            localized: "The key worked, but InstantVoice could not save it securely.")
                        verificationDetailMessage = nil
                        onVerificationChanged()
                        return
                    }

                    aiService.selectedProvider = provider
                    aiService.selectModel(modelName, for: provider)
                    aiService.apiKey = key
                    aiService.isAPIKeyValid = true
                    apiKey = ""
                    verificationMessage = String(
                        format: String(localized: "%@ connection verified."), provider.rawValue)
                    verificationDetailMessage = nil
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    verificationMessage = String(
                        localized: "Could not verify this API key. Check the key and try again.")
                    verificationDetailMessage = result.errorMessage
                }

                onVerificationChanged()
            }
        }
    }
}

fileprivate extension AIProvider {
    var apiKeyURL: URL? {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")
        default:
            return nil
        }
    }
}
