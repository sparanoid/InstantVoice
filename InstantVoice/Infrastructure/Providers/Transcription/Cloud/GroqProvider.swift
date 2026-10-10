import Foundation
import LLMkit
import SwiftData

struct GroqProvider: CloudProvider {
    let modelProvider: ModelProvider = .groq
    let providerKey: String = "Groq"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        listedModels ?? builtInModels
    }

    /// Whisper models from Groq's fetched list, which also holds its chat and speech models.
    private var listedModels: [CloudModel]? {
        guard let listed = ProviderModelCatalog.shared.models(for: providerKey) else { return nil }
        let models = listed
            .filter { ListedModelKind.isGroqTranscriptionModel($0.id) }
            .map { model in
                CloudModel.listed(
                    model.id,
                    provider: .groq,
                    builtIn: builtInModels,
                    defaultDescription: String(localized: "Whisper model with Groq's fast inference"),
                    defaultLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .groq)
                )
            }
        return models.isEmpty ? nil : models
    }

    var builtInModels: [CloudModel] {
        [
            CloudModel(
                name: "whisper-large-v3-turbo",
                displayName: "whisper-large-v3-turbo",
                description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
                provider: .groq,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .groq)
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await OpenAITranscriptionClient.transcribe(
            baseURL: URL(string: "https://api.groq.com/openai")!,
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await OpenAITranscriptionClient.verifyAPIKey(
            baseURL: URL(string: "https://api.groq.com/openai")!,
            apiKey: key
        )
    }
}
