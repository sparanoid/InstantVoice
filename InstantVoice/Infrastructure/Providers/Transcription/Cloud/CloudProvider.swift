import Foundation
import SwiftData

protocol CloudProvider: Sendable {
    var modelProvider: ModelProvider { get }
    var providerKey: String { get }
    var languageCodes: [String]? { get }
    var includesAutoDetect: Bool { get }
    /// True when a request can list several languages the audio may contain.
    var supportsMultipleLanguages: Bool { get }
    var models: [CloudModel] { get }
    /// The models the app ships with, used until the provider's list has been fetched. The first ones are
    /// the recommended picks.
    var builtInModels: [CloudModel] { get }
    /// True when the provider has no batch HTTP endpoint and requires streaming for all transcription.
    var isStreamingOnly: Bool { get }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String
    /// Transcribes audio that may contain any of `languages`, primary language first. Empty means auto-detect.
    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, languages: [String],
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String
    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)?
    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?)
}

extension CloudProvider {
    var builtInModels: [CloudModel] { models }
    var isStreamingOnly: Bool { false }
    var supportsMultipleLanguages: Bool { false }

    /// Streaming-only providers inherit this and get a clear error if batch is somehow attempted.
    /// Providers that support batch transcription override this with their real implementation.
    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        throw CloudTranscriptionError.unsupportedProvider
    }

    /// Providers that accept one language transcribe with the primary one.
    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, languages: [String],
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        try await transcribe(
            audioData: audioData, fileName: fileName, apiKey: apiKey, model: model, language: languages.first,
            customVocabulary: customVocabulary, timeout: timeout)
    }
}

enum CloudProviderRegistry {
    static let allProviders: [any CloudProvider] = [
        GroqProvider(),
        ElevenLabsProvider(),
        DeepgramProvider(),
        GeminiProvider(),
        SonioxProvider(),
        XAIProvider(),
        CartesiaProvider(),
        OpenRouterProvider(),
    ]

    static func provider(for modelProvider: ModelProvider) -> (any CloudProvider)? {
        allProviders.first { $0.modelProvider == modelProvider }
    }
}

extension TranscriptionModel {
    /// The model's name, after its cloud provider's when it has one, such as "Soniox · stt-rt-v5".
    var providerQualifiedName: String {
        guard let cloudProvider = CloudProviderRegistry.provider(for: provider) else { return displayName }
        return "\(cloudProvider.providerKey) · \(displayName)"
    }
}

extension CloudModel {
    /// A raw entry from a provider's model list, shown under its ID. What the provider reports wins; otherwise
    /// the built-in entry with the same ID, then the provider-wide defaults, fill in.
    static func listed(
        _ name: String,
        provider: ModelProvider,
        builtIn: [CloudModel],
        description: String? = nil,
        defaultDescription: String,
        languages: [String: String]? = nil,
        defaultLanguages: [String: String],
        supportsBatch: Bool? = nil,
        supportsStreaming: Bool? = nil,
        batchFallbackName: String? = nil
    ) -> CloudModel {
        let known = builtIn.first { $0.name == name }
        // A reported list without any language, such as an empty one, says nothing about the model.
        let reportedLanguages = languages?.keys.contains { $0 != "auto" } == true ? languages : nil
        let supportedLanguages = reportedLanguages ?? known?.supportedLanguages ?? defaultLanguages
        // Regional variants such as `en-US` and `en-GB` count as one language.
        let baseLanguages = Set(supportedLanguages.keys.filter { $0 != "auto" }.map { $0.prefix { $0 != "-" } })
        let isMultilingual = reportedLanguages == nil ? known?.isMultilingualModel : nil
        return CloudModel(
            name: name,
            displayName: name,
            description: description ?? known?.description ?? defaultDescription,
            provider: provider,
            isMultilingual: isMultilingual ?? (baseLanguages.count > 1),
            supportsStreaming: supportsStreaming ?? known?.supportsStreaming ?? false,
            supportsBatch: supportsBatch ?? known?.supportsBatch ?? true,
            supportedLanguages: supportedLanguages,
            batchFallbackName: batchFallbackName ?? known?.batchFallbackName
        )
    }
}
