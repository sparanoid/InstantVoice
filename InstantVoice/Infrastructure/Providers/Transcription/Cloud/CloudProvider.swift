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
