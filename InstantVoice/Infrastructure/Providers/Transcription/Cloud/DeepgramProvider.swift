import Foundation
import LLMkit
import SwiftData

struct DeepgramProvider: CloudProvider {
    let modelProvider: ModelProvider = .deepgram
    let providerKey: String = "Deepgram"
    let languageCodes: [String]? = Self.nova3LanguageCodes
    let includesAutoDetect: Bool = true

    /// Nova-3 languages documented by Deepgram for hosted batch and streaming transcription.
    /// `auto` is presented by VoiceInk and translated to Deepgram's `language=multi` mode.
    private static let nova3LanguageCodes = [
        "af", "af-ZA",
        "ar", "ar-AE", "ar-SA", "ar-QA", "ar-KW", "ar-SY", "ar-LB", "ar-PS", "ar-JO", "ar-EG",
        "ar-SD", "ar-TD", "ar-MA", "ar-DZ", "ar-TN", "ar-IQ", "ar-IR",
        "hy", "be", "bn", "bs", "bg", "ca",
        "zh-HK", "zh", "zh-CN", "zh-Hans", "zh-TW", "zh-Hant",
        "hr", "cs", "da", "da-DK", "nl", "en", "en-US", "en-AU", "en-GB", "en-IN", "en-NZ", "et",
        "fi", "nl-BE", "fr", "fr-CA", "ka", "ka-GE", "de", "de-CH",
        "el", "gu", "gu-IN", "he", "hi", "hu", "id", "it", "ja", "kn", "ko", "ko-KR", "lv",
        "lt", "mk", "ms", "mr", "ne", "no", "fa", "pl", "pt", "pt-BR", "pt-PT", "pa", "pa-IN",
        "ro", "ru", "sr", "sk", "sl", "es", "es-419", "sv", "sv-SE", "tl", "ta", "te", "th",
        "th-TH", "tr", "uk", "ur", "vi",
    ]

    private static let nova3MedicalLanguageCodes = [
        "en", "en-US", "en-AU", "en-CA", "en-GB", "en-IE", "en-IN", "en-NZ",
    ]

    private static var nova3SupportedLanguages: [String: String] {
        var languages = LanguageDictionary.forCodes(nova3LanguageCodes)
        languages["auto"] = "Auto"
        return languages
    }

    var models: [CloudModel] {
        listedModels ?? builtInModels
    }

    /// Every speech-to-text model Deepgram lists, under the canonical name it takes as `model`.
    private var listedModels: [CloudModel]? {
        guard let listed = ProviderModelCatalog.shared.models(for: providerKey), !listed.isEmpty else { return nil }
        return listed.map { model in
            var languages = LanguageDictionary.forCodes(model.languages ?? [])
            if Self.usesMultilingualMode(model.id), model.capabilities.contains("multilingual") {
                languages["auto"] = "Auto"
            }
            return CloudModel.listed(
                model.id,
                provider: .deepgram,
                builtIn: builtInModels,
                defaultDescription: String(localized: "Deepgram speech-to-text model"),
                languages: languages.isEmpty ? nil : languages,
                defaultLanguages: Self.nova3SupportedLanguages,
                supportsBatch: model.capabilities.contains("batch"),
                supportsStreaming: model.capabilities.contains("streaming")
            )
        }
    }

    /// General Nova models, such as `nova-3-general` (or its short name `nova-3`), transcribe mixed languages
    /// when asked for `language=multi`.
    static func usesMultilingualMode(_ modelName: String) -> Bool {
        let parts = modelName.split(separator: "-")
        guard parts.count >= 2, parts[0] == "nova", Int(parts[1]) != nil else { return false }
        return parts.count == 2 || (parts.count == 3 && parts[2] == "general")
    }

    var builtInModels: [CloudModel] {
        [
            CloudModel(
                name: "nova-3-general",
                displayName: "nova-3-general",
                description: "Deepgram's latest Nova 3 model for fast, accurate transcription",
                provider: .deepgram,
                isMultilingual: true,
                supportsStreaming: true,
                supportedLanguages: Self.nova3SupportedLanguages
            ),
            CloudModel(
                name: "nova-3-medical",
                displayName: "nova-3-medical",
                description: "Specialized medical transcription model optimized for clinical environments",
                provider: .deepgram,
                isMultilingual: false,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forCodes(Self.nova3MedicalLanguageCodes)
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        let deepgramLanguage = Self.usesMultilingualMode(model) && language == nil ? "multi" : language
        return try await DeepgramClient.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            language: deepgramLanguage,
            customVocabulary: Array(customVocabulary.prefix(100)),
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        DeepgramStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await DeepgramClient.verifyAPIKey(key)
    }
}
