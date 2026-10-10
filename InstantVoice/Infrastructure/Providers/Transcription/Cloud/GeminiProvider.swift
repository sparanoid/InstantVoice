import Foundation
import LLMkit
import SwiftData

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini
    let providerKey: String = "Gemini"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    private static let transcribeLanguageCodes = [
        "af-ZA", "am-ET", "ar-EG", "as-IN", "az-AZ", "be-BY", "bg-BG", "bn-BD", "bn-IN", "bs-BA",
        "ca-ES", "ceb", "cmn-Hans-CN", "cs-CZ", "da-DK", "de-DE", "el-GR", "en-GB", "en-IN", "en-US",
        "es-419", "es-US", "et-EE", "fa-IR", "fil-PH", "fi-FI", "fr-FR", "gl-ES", "gu-IN", "ha-NG",
        "he-IL", "hi-IN", "hr-HR", "hu-HU", "hy-AM", "id-ID", "is-IS", "it-IT", "ja-JP", "jv-ID",
        "ka-GE", "kea-CV", "kk-KZ", "km-KH", "kn-IN", "ko-KR", "ky-KG", "ln-CD", "lt-LT", "lv-LV",
        "mk-MK", "ml-IN", "mn-MN", "mr-IN", "ms-MY", "mt-MT", "my-MM", "nb-NO", "ne-NP", "nl-NL",
        "or-IN", "pa-Guru-IN", "pa-IN", "pl-PL", "pt-BR", "pt-PT", "ro-RO", "ru-RU", "rup-BG",
        "sd-Arab-IN", "sk-SK", "sl-SI", "sr-RS", "sv-SE", "sw-KE", "te-IN", "tg-TJ", "th-TH", "tr-TR",
        "uk-UA", "uz-UZ", "vi-VN", "yue-Hant-HK",
    ]

    private static var transcribeSupportedLanguages: [String: String] {
        LanguageDictionary.forCodes(transcribeLanguageCodes, includesAutoDetect: true)
    }

    var models: [CloudModel] {
        listedModels ?? builtInModels
    }

    /// Transcribe models from Gemini's fetched list, which also holds its chat models. Live models such as
    /// `gemini-3.5-transcribe-live` stream; their file counterpart drops the `-live` suffix. A live model named
    /// otherwise has no known file counterpart.
    private var listedModels: [CloudModel]? {
        guard let listed = ProviderModelCatalog.shared.models(for: providerKey) else { return nil }
        let models = listed
            .filter { ListedModelKind.isGeminiTranscriptionModel($0.id) }
            .map { model in
                let fileModelName = model.id.hasSuffix("-live") ? String(model.id.dropLast("-live".count)) : nil
                let isLive = fileModelName != nil || model.capabilities.contains("bidiGenerateContent")
                return CloudModel.listed(
                    model.id,
                    provider: .gemini,
                    builtIn: builtInModels,
                    description: model.displayName,
                    defaultDescription: String(localized: "Google's dedicated transcription model"),
                    defaultLanguages: Self.transcribeSupportedLanguages,
                    supportsBatch: !isLive,
                    supportsStreaming: isLive,
                    batchFallbackName: fileModelName
                )
            }
        return models.isEmpty ? nil : models
    }

    var builtInModels: [CloudModel] {
        [
            CloudModel(
                name: "gemini-3.5-transcribe",
                displayName: "gemini-3.5-transcribe",
                description: "Google's dedicated Verbatim transcription model for recorded audio",
                provider: .gemini,
                isMultilingual: true,
                supportedLanguages: Self.transcribeSupportedLanguages
            ),
            CloudModel(
                name: "gemini-3.5-transcribe-live",
                displayName: "gemini-3.5-transcribe-live",
                description: "Google's dedicated Verbatim transcription model for real-time transcription",
                provider: .gemini,
                isMultilingual: true,
                supportsStreaming: true,
                supportsBatch: false,
                supportedLanguages: Self.transcribeSupportedLanguages,
                batchFallbackName: "gemini-3.5-transcribe"
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await GeminiTranscriptionClient.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            fileName: fileName,
            language: language,
            customVocabulary: customVocabulary,
            mode: .verbatim,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        GeminiStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await GeminiTranscriptionClient.verifyAPIKey(key)
    }
}
