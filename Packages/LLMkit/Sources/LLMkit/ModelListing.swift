import Foundation

/// A model returned by a provider's list-models endpoint.
public struct ListedModel: Codable, Sendable, Hashable {
    /// The ID to send as `model` in requests.
    public let id: String
    /// The provider's display name, when it has one.
    public let displayName: String?
    /// When the provider released the model, when it says.
    public let createdAt: Date?
    /// Language codes the model accepts, when the provider lists them.
    public let languages: [String]?
    /// Capabilities the provider reports for the model. Each list function documents its values.
    public let capabilities: [String]
    /// The model this ID forwards to, when the provider lists it as an alias.
    public let aliasOf: String?
    /// True when the provider has deprecated the model or announced its shutdown.
    public let isDeprecated: Bool

    public init(
        id: String,
        displayName: String? = nil,
        createdAt: Date? = nil,
        languages: [String]? = nil,
        capabilities: [String] = [],
        aliasOf: String? = nil,
        isDeprecated: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.languages = languages
        self.capabilities = capabilities
        self.aliasOf = aliasOf
        self.isDeprecated = isDeprecated
    }
}

// MARK: - OpenAI-compatible

extension OpenAILLMClient {
    /// Lists the models an OpenAI-compatible API offers, using `GET {baseURL}/models`.
    ///
    /// Accepts the standard `{"data": [...]}` response and the `{"models": [...]}` or bare-array shapes some
    /// compatible servers return. Models a server marks `"active": false` are left out, and models with a
    /// `shutdown_date` are marked deprecated. The response says nothing about what a model can do, so it
    /// reports no capabilities.
    ///
    /// - Parameters:
    ///   - baseURL: The API root that `/models` hangs off, e.g. `https://api.openai.com/v1` or
    ///     `https://api.groq.com/openai/v1`.
    ///   - apiKey: API key for the provider. Pass an empty string for servers without authentication.
    ///   - timeout: Request timeout in seconds (default 15).
    public static func listModels(baseURL: URL, apiKey: String, timeout: TimeInterval = 15) async throws
        -> [ListedModel]
    {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request, timeout: timeout, maxRetries: 1)
        try validateHTTPResponse(response, data: data)
        return try parseModelList(data)
    }

    /// Parses a `/models` response from an OpenAI-compatible API.
    static func parseModelList(_ data: Data) throws -> [ListedModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw LLMKitError.decodingError("The models response isn't JSON.")
        }
        let entries: [Any]
        if let object = json as? [String: Any] {
            entries = (object["data"] as? [Any]) ?? (object["models"] as? [Any]) ?? []
        } else {
            entries = (json as? [Any]) ?? []
        }

        return entries.compactMap { entry -> ListedModel? in
            guard let model = entry as? [String: Any],
                let id = (model["id"] as? String) ?? (model["name"] as? String) ?? (model["model"] as? String),
                !id.isEmpty,
                model["active"] as? Bool != false
            else { return nil }

            let created = (model["created"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let shutdownDate = model["shutdown_date"] as? String
            return ListedModel(id: id, createdAt: created, isDeprecated: shutdownDate != nil)
        }
    }
}

// MARK: - Anthropic

extension AnthropicLLMClient {
    /// Lists the Claude models available to an API key, using `GET https://api.anthropic.com/v1/models`.
    ///
    /// Follows pagination, newest models first. Anthropic lists active and deprecated models; deprecated ones
    /// are marked as such. Every listed model is a chat model, so no capabilities are reported.
    public static func listModels(apiKey: String, timeout: TimeInterval = 15) async throws -> [ListedModel] {
        try validateAPIKey(apiKey)

        var models: [ListedModel] = []
        var afterID: String?
        // A safety cap; one page holds up to 1,000 models.
        for _ in 0..<10 {
            var components = URLComponents(string: "https://api.anthropic.com/v1/models")!
            components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
            if let afterID {
                components.queryItems?.append(URLQueryItem(name: "after_id", value: afterID))
            }

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response) = try await performRequest(request, timeout: timeout, maxRetries: 1)
            try validateHTTPResponse(response, data: data)
            let page = try parseModelsPage(data)

            models += page.models
            guard let nextAfterID = page.nextAfterID else { break }
            afterID = nextAfterID
        }
        return models
    }

    /// Parses one page of `/v1/models`, returning the ID to continue after when more pages follow.
    static func parseModelsPage(_ data: Data) throws -> (models: [ListedModel], nextAfterID: String?) {
        let page = try decodeJSON(AnthropicModelsPage.self, from: data)
        let dateFormatter = ISO8601DateFormatter()
        let models = page.data.map { model in
            ListedModel(
                id: model.id,
                displayName: model.display_name,
                createdAt: model.created_at.flatMap { dateFormatter.date(from: $0) },
                isDeprecated: model.lifecycle == "deprecated"
            )
        }
        return (models, page.has_more == true ? page.last_id : nil)
    }
}

private struct AnthropicModelsPage: Decodable {
    let data: [AnthropicListedModel]
    let has_more: Bool?
    let last_id: String?
}

private struct AnthropicListedModel: Decodable {
    let id: String
    let display_name: String?
    let created_at: String?
    let lifecycle: String?
}

// MARK: - Soniox

extension SonioxClient {
    /// Lists Soniox speech-to-text models, using `GET https://api.soniox.com/v1/models`.
    ///
    /// Capabilities hold the model's transcription mode, `"async"` (files) or `"real_time"` (WebSocket), plus
    /// `"language_hints_strict"` when the model accepts strict language hints. Aliases report the model they
    /// forward to in `aliasOf`.
    public static func listModels(apiKey: String, timeout: TimeInterval = 15) async throws -> [ListedModel] {
        try validateAPIKey(apiKey)

        var request = URLRequest(url: URL(string: "https://api.soniox.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request, timeout: timeout, maxRetries: 1)
        try validateHTTPResponse(response, data: data)
        return try parseModelList(data)
    }

    /// Parses a `/v1/models` response.
    static func parseModelList(_ data: Data) throws -> [ListedModel] {
        let decoded = try decodeJSON(SonioxModelsResponse.self, from: data)
        return decoded.models.map { model in
            var capabilities: [String] = []
            if let mode = model.transcription_mode {
                capabilities.append(mode)
            }
            if model.supports_language_hints_strict == true {
                capabilities.append("language_hints_strict")
            }
            return ListedModel(
                id: model.id,
                displayName: model.name,
                languages: model.languages?.map(\.code),
                capabilities: capabilities,
                aliasOf: model.aliased_model_id
            )
        }
    }
}

private struct SonioxModelsResponse: Decodable {
    let models: [SonioxListedModel]
}

private struct SonioxListedModel: Decodable {
    let id: String
    let aliased_model_id: String?
    let name: String?
    let transcription_mode: String?
    let languages: [SonioxListedLanguage]?
    let supports_language_hints_strict: Bool?
}

private struct SonioxListedLanguage: Decodable {
    let code: String
}

// MARK: - Gemini

extension GeminiLLMClient {
    /// Lists Gemini API models, using `GET https://generativelanguage.googleapis.com/v1beta/models`.
    ///
    /// Follows pagination. IDs drop the `models/` prefix. Capabilities hold the model's
    /// `supportedGenerationMethods`, such as `"generateContent"` or `"bidiGenerateContent"`.
    public static func listModels(apiKey: String, timeout: TimeInterval = 15) async throws -> [ListedModel] {
        try validateAPIKey(apiKey)

        var models: [ListedModel] = []
        var pageToken: String?
        // A safety cap; one page holds up to 1,000 models.
        for _ in 0..<10 {
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let (data, response) = try await performRequest(request, timeout: timeout, maxRetries: 1)
            try validateHTTPResponse(response, data: data)
            let page = try parseModelsPage(data)

            models += page.models
            guard let nextPageToken = page.nextPageToken else { break }
            pageToken = nextPageToken
        }
        return models
    }

    /// Parses one page of `models.list`, returning the token for the next page when there is one.
    static func parseModelsPage(_ data: Data) throws -> (models: [ListedModel], nextPageToken: String?) {
        let page = try decodeJSON(GeminiModelsPage.self, from: data)
        let models = (page.models ?? []).map { model in
            ListedModel(
                id: model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name,
                displayName: model.displayName,
                capabilities: model.supportedGenerationMethods ?? []
            )
        }
        let nextPageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        return (models, nextPageToken)
    }
}

private struct GeminiModelsPage: Decodable {
    let models: [GeminiListedModel]?
    let nextPageToken: String?
}

private struct GeminiListedModel: Decodable {
    let name: String
    let displayName: String?
    let supportedGenerationMethods: [String]?
}

// MARK: - Deepgram

extension DeepgramClient {
    /// Lists Deepgram's public speech-to-text models, using `GET https://api.deepgram.com/v1/models`.
    ///
    /// Deepgram returns one entry per variant of a model: a set of languages, served in batch or streaming.
    /// Variants are combined by `canonical_name`, the value to send as `model`, in the order first listed.
    /// Capabilities hold `"batch"`, `"streaming"`, and `"multilingual"` when any variant has them.
    public static func listModels(apiKey: String, timeout: TimeInterval = 15) async throws -> [ListedModel] {
        var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/models")!)
        request.httpMethod = "GET"
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Token \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request, timeout: timeout, maxRetries: 1)
        try validateHTTPResponse(response, data: data)
        return try parseModelList(data)
    }

    /// Parses a `/v1/models` response, combining variants of the same speech-to-text model.
    static func parseModelList(_ data: Data) throws -> [ListedModel] {
        let decoded = try decodeJSON(DeepgramModelsResponse.self, from: data)

        var order: [String] = []
        var languages: [String: [String]] = [:]
        var capabilities: [String: Set<String>] = [:]
        for variant in decoded.stt ?? [] {
            let name = variant.canonical_name
            if languages[name] == nil {
                order.append(name)
                languages[name] = []
                capabilities[name] = []
            }
            for language in variant.languages ?? [] where !languages[name]!.contains(language) {
                languages[name]!.append(language)
            }
            if variant.batch == true { capabilities[name]!.insert("batch") }
            if variant.streaming == true { capabilities[name]!.insert("streaming") }
            if variant.multilingual == true { capabilities[name]!.insert("multilingual") }
        }

        return order.map { name in
            ListedModel(
                id: name,
                languages: languages[name],
                capabilities: ["batch", "streaming", "multilingual"].filter { capabilities[name]!.contains($0) }
            )
        }
    }
}

private struct DeepgramModelsResponse: Decodable {
    let stt: [DeepgramListedVariant]?
}

private struct DeepgramListedVariant: Decodable {
    let canonical_name: String
    let languages: [String]?
    let batch: Bool?
    let streaming: Bool?
    let multilingual: Bool?
}

// MARK: - Model kinds

/// Reads what a listed model is for from its provider's ID conventions, for list endpoints that don't say.
public enum ListedModelKind {
    /// OpenAI chat models: the GPT and o-series families, minus audio, image, search, embedding, and
    /// moderation variants and the models that answer only through the Responses API.
    public static func isOpenAIChatModel(_ id: String) -> Bool {
        let id = id.lowercased()
        let isChatFamily =
            id.hasPrefix("gpt-") || id.hasPrefix("chatgpt-") || id.range(of: #"^o\d"#, options: .regularExpression) != nil
        guard isChatFamily else { return false }

        let excludedParts = [
            "audio", "codex", "computer-use", "deep-research", "diarize", "embedding", "image", "instruct", "live",
            "moderation", "realtime", "search", "transcribe", "tts", "whisper",
        ]
        if excludedParts.contains(where: id.contains) { return false }
        return !id.hasSuffix("-pro") && !id.contains("-pro-")
    }

    /// Groq lists speech-to-text, text-to-speech, and safety classifier models next to its chat models.
    public static func isGroqChatModel(_ id: String) -> Bool {
        let id = id.lowercased()
        return !["whisper", "tts", "orpheus", "guard"].contains(where: id.contains)
    }

    public static func isGroqTranscriptionModel(_ id: String) -> Bool {
        id.lowercased().contains("whisper")
    }

    /// Gemini chat models generate content and aren't embedding, speech, image, live, or agent models.
    public static func isGeminiChatModel(_ model: ListedModel) -> Bool {
        let id = model.id.lowercased()
        guard id.hasPrefix("gemini-"), model.capabilities.contains("generateContent") else { return false }
        let excludedParts = [
            "audio", "computer-use", "deep-research", "embedding", "image", "live", "robotics", "transcribe", "tts",
        ]
        return !excludedParts.contains(where: id.contains)
    }

    /// Gemini transcription models: file models such as `gemini-3.5-transcribe`, and their `-live` counterparts,
    /// which stream.
    public static func isGeminiTranscriptionModel(_ id: String) -> Bool {
        let id = id.lowercased()
        return id.hasPrefix("gemini-") && id.contains("-transcribe")
    }
}
