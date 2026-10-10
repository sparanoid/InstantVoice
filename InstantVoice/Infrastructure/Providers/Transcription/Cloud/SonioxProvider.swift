import Foundation
import LLMkit
import SwiftData

struct SonioxProvider: CloudProvider {
    let modelProvider: ModelProvider = .soniox
    let providerKey: String = "Soniox"
    let languageCodes: [String]? = [
        "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
        "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
        "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
        "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
        "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
        "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy",
    ]
    let includesAutoDetect: Bool = true
    let supportsMultipleLanguages: Bool = true

    var models: [CloudModel] {
        listedModels ?? builtInModels
    }

    /// Every transcription model Soniox lists, under its own ID. File (`async`) and real-time models are
    /// separate entries, and aliases stay listed next to the model they forward to.
    private var listedModels: [CloudModel]? {
        guard let listed = ProviderModelCatalog.shared.models(for: providerKey) else { return nil }
        let transcriptionModels = listed.filter {
            $0.capabilities.contains("async") || $0.capabilities.contains("real_time")
        }

        let models = transcriptionModels.map { model in
            let isRealtime = model.capabilities.contains("real_time")
            return CloudModel.listed(
                model.id,
                provider: .soniox,
                builtIn: builtInModels,
                description: model.aliasOf.map { String(format: String(localized: "Alias of %@"), $0) }
                    ?? model.displayName,
                defaultDescription: String(localized: "Soniox speech-to-text model"),
                languages: model.languages.map { LanguageDictionary.forCodes($0, includesAutoDetect: true) },
                defaultLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .soniox),
                supportsBatch: model.capabilities.contains("async"),
                supportsStreaming: isRealtime,
                batchFallbackName: isRealtime ? Self.fileModel(for: model, in: transcriptionModels)?.id : nil
            )
        }
        return models.isEmpty ? nil : models
    }

    var builtInModels: [CloudModel] {
        [
            CloudModel(
                name: "stt-async-v5",
                displayName: "stt-async-v5",
                description: "Soniox v5 for recorded audio, with improved accuracy and structured data formatting",
                provider: .soniox,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .soniox)
            ),
            CloudModel(
                name: "stt-rt-v5",
                displayName: "stt-rt-v5",
                description: "Soniox v5 for real-time transcription",
                provider: .soniox,
                isMultilingual: true,
                supportsStreaming: true,
                supportsBatch: false,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .soniox),
                batchFallbackName: "stt-async-v5"
            ),
        ]
    }

    /// The file model of the same version, such as `stt-async-v5` for `stt-rt-v5`. An alias without one uses
    /// the file model of the version it forwards to.
    private static func fileModel(for model: ListedModel, in models: [ListedModel]) -> ListedModel? {
        let fileModels = models.filter { $0.capabilities.contains("async") }
        for id in [model.id, model.aliasOf].compactMap({ $0 }) {
            if let fileModel = fileModels.first(where: { version(of: $0.id) == version(of: id) }) {
                return fileModel
            }
        }
        return nil
    }

    /// `stt-async-v5` and `stt-rt-v5` share the version `stt-v5`.
    private static func version(of id: String) -> String {
        id.replacingOccurrences(of: "-async", with: "").replacingOccurrences(of: "-rt", with: "")
    }

    /// Whether Soniox accepts strict language hints for a model. Assumed until its list has been fetched.
    static func acceptsStrictLanguageHints(_ modelName: String) -> Bool {
        guard let model = ProviderModelCatalog.shared.models(for: "Soniox")?.first(where: { $0.id == modelName })
        else { return true }
        return model.capabilities.contains("language_hints_strict")
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?,
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        try await transcribe(
            audioData: audioData, fileName: fileName, apiKey: apiKey, model: model,
            languages: language.map { [$0] } ?? [], customVocabulary: customVocabulary, timeout: timeout)
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, languages: [String],
        customVocabulary: [String], timeout: TimeInterval
    ) async throws -> String {
        return try await SonioxClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            languages: languages,
            strictLanguageHints: Self.acceptsStrictLanguageHints(model),
            customVocabulary: customVocabulary,
            maxWaitSeconds: timeout,
            timeout: timeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SonioxStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await SonioxClient.verifyAPIKey(key)
    }
}
