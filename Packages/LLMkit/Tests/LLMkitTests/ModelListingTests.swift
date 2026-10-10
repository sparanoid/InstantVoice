import Foundation
import Testing

@testable import LLMkit

struct ModelListingTests {
    // MARK: - OpenAI-compatible

    @Test func openAIListReadsIDsDatesAndShutdowns() throws {
        let models = try OpenAILLMClient.parseModelList(
            json("""
                {"object": "list", "data": [
                  {"id": "gpt-6-luna", "object": "model", "created": 1686935002, "owned_by": "openai"},
                  {"id": "gpt-4.1", "object": "model", "created": 1686935002, "owned_by": "openai",
                   "shutdown_date": "2026-10-23"}
                ]}
                """))

        #expect(models.map(\.id) == ["gpt-6-luna", "gpt-4.1"])
        #expect(models[0].createdAt == Date(timeIntervalSince1970: 1_686_935_002))
        #expect(models[0].isDeprecated == false)
        #expect(models[1].isDeprecated == true)
        #expect(models[0].capabilities.isEmpty)
    }

    @Test func groqInactiveModelsAreLeftOut() throws {
        let models = try OpenAILLMClient.parseModelList(
            json("""
                {"object": "list", "data": [
                  {"id": "whisper-large-v3", "object": "model", "created": 1693721698, "owned_by": "OpenAI",
                   "active": true, "context_window": 448},
                  {"id": "retired-model", "object": "model", "active": false}
                ]}
                """))

        #expect(models.map(\.id) == ["whisper-large-v3"])
    }

    @Test func compatibleServersMayUseOtherShapes() throws {
        #expect(try OpenAILLMClient.parseModelList(json(#"[{"id": "local-model"}]"#)).map(\.id) == ["local-model"])
        #expect(
            try OpenAILLMClient.parseModelList(json(#"{"models": [{"name": "llama3"}, {"model": "qwen"}]}"#))
                .map(\.id) == ["llama3", "qwen"])
        #expect(try OpenAILLMClient.parseModelList(json(#"{"data": [{"object": "model"}]}"#)).isEmpty)
    }

    @Test func nonJSONModelListThrows() {
        #expect(throws: LLMKitError.self) {
            try OpenAILLMClient.parseModelList(Data("<html>Not found</html>".utf8))
        }
    }

    // MARK: - Anthropic

    @Test func anthropicPageReadsNamesLifecycleAndCursor() throws {
        let page = try AnthropicLLMClient.parseModelsPage(
            json("""
                {"data": [
                  {"type": "model", "id": "claude-opus-5", "display_name": "Claude Opus 5",
                   "created_at": "2026-07-24T00:00:00Z", "lifecycle": "active"},
                  {"type": "model", "id": "claude-old", "display_name": "Claude Old",
                   "created_at": "2025-01-01T00:00:00Z", "lifecycle": "deprecated"}
                ], "has_more": true, "first_id": "claude-opus-5", "last_id": "claude-old"}
                """))

        #expect(page.models.map(\.id) == ["claude-opus-5", "claude-old"])
        #expect(page.models[0].displayName == "Claude Opus 5")
        #expect(page.models[0].createdAt == ISO8601DateFormatter().date(from: "2026-07-24T00:00:00Z"))
        #expect(page.models.map(\.isDeprecated) == [false, true])
        #expect(page.nextAfterID == "claude-old")
    }

    @Test func anthropicLastPageHasNoCursor() throws {
        let page = try AnthropicLLMClient.parseModelsPage(
            json(#"{"data": [{"id": "claude-sonnet-5"}], "has_more": false, "last_id": "claude-sonnet-5"}"#))

        #expect(page.models.map(\.id) == ["claude-sonnet-5"])
        #expect(page.nextAfterID == nil)
    }

    // MARK: - Soniox

    @Test func sonioxModelsReportModeLanguagesStrictHintsAndAliases() throws {
        let models = try SonioxClient.parseModelList(
            json("""
                {"models": [
                  {"id": "stt-rt-v5", "aliased_model_id": null, "name": "Speech-to-Text Real-time v5",
                   "context_version": 2, "transcription_mode": "real_time",
                   "languages": [{"code": "en", "name": "English"}, {"code": "zh", "name": "Chinese"}],
                   "supports_language_hints_strict": true, "translation_targets": []},
                  {"id": "stt-async-v4", "aliased_model_id": "stt-async-v5", "name": "Speech-to-Text Async v4",
                   "transcription_mode": "async", "languages": [], "supports_language_hints_strict": false}
                ]}
                """))

        #expect(models.map(\.id) == ["stt-rt-v5", "stt-async-v4"])
        #expect(models[0].displayName == "Speech-to-Text Real-time v5")
        #expect(models[0].languages == ["en", "zh"])
        #expect(models[0].capabilities == ["real_time", "language_hints_strict"])
        #expect(models[0].aliasOf == nil)
        #expect(models[1].capabilities == ["async"])
        #expect(models[1].aliasOf == "stt-async-v5")
    }

    // MARK: - Gemini

    @Test func geminiPageStripsPrefixAndKeepsMethodsAndCursor() throws {
        let page = try GeminiLLMClient.parseModelsPage(
            json("""
                {"models": [
                  {"name": "models/gemini-3.8-flash", "version": "3.8", "displayName": "Gemini 3.8 Flash",
                   "supportedGenerationMethods": ["generateContent", "countTokens"]},
                  {"name": "models/gemini-embedding-001", "displayName": "Gemini Embedding",
                   "supportedGenerationMethods": ["embedContent"]}
                ], "nextPageToken": "page-2"}
                """))

        #expect(page.models.map(\.id) == ["gemini-3.8-flash", "gemini-embedding-001"])
        #expect(page.models[0].displayName == "Gemini 3.8 Flash")
        #expect(page.models[0].capabilities == ["generateContent", "countTokens"])
        #expect(page.nextPageToken == "page-2")
    }

    @Test func geminiLastPageHasNoCursor() throws {
        #expect(try GeminiLLMClient.parseModelsPage(json(#"{"models": []}"#)).nextPageToken == nil)
        #expect(try GeminiLLMClient.parseModelsPage(json(#"{"nextPageToken": ""}"#)).nextPageToken == nil)
    }

    // MARK: - Deepgram

    @Test func deepgramVariantsAreCombinedByCanonicalName() throws {
        let models = try DeepgramClient.parseModelList(
            json("""
                {"stt": [
                  {"name": "general", "canonical_name": "nova-3-general", "architecture": "nova-3",
                   "languages": ["en", "en-US"], "version": "2026-07-01.0", "uuid": "a", "batch": true,
                   "streaming": false, "formatted_output": true, "multilingual": false},
                  {"name": "medical", "canonical_name": "nova-3-medical", "architecture": "nova-3",
                   "languages": ["en"], "version": "2026-07-01.0", "uuid": "b", "batch": true,
                   "streaming": true, "formatted_output": true, "multilingual": false},
                  {"name": "general", "canonical_name": "nova-3-general", "architecture": "nova-3",
                   "languages": ["en", "de"], "version": "2026-07-01.0", "uuid": "c", "batch": false,
                   "streaming": true, "formatted_output": true, "multilingual": true}
                ], "tts": [{"name": "aura", "canonical_name": "aura-2-thalia-en"}],
                "languages": {"en": "English", "de": "German"}}
                """))

        #expect(models.map(\.id) == ["nova-3-general", "nova-3-medical"])
        #expect(models[0].languages == ["en", "en-US", "de"])
        #expect(models[0].capabilities == ["batch", "streaming", "multilingual"])
        #expect(models[1].capabilities == ["batch", "streaming"])
    }

    // MARK: - Model kinds

    @Test func openAIChatModelsExcludeOtherKinds() {
        let chat = ["gpt-6-luna", "gpt-5.4-mini", "gpt-4.1", "o3", "o4-mini", "chatgpt-4o-latest"]
        let other = [
            "gpt-transcribe", "gpt-4o-transcribe-diarize", "whisper-1", "gpt-4o-mini-tts", "gpt-realtime",
            "gpt-live-1", "gpt-audio-1.5", "text-embedding-3-large", "omni-moderation-latest", "gpt-image-1",
            "chatgpt-image-latest", "gpt-5-codex", "o3-pro", "gpt-5.5-pro", "o4-mini-deep-research",
            "gpt-4o-search-preview", "gpt-3.5-turbo-instruct", "dall-e-3", "babbage-002", "computer-use-preview",
        ]

        #expect(chat.allSatisfy(ListedModelKind.isOpenAIChatModel))
        #expect(!other.contains(where: ListedModelKind.isOpenAIChatModel))
    }

    @Test func groqModelsSplitIntoChatAndTranscription() {
        let chat = ["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "llama-3.3-70b-versatile", "groq/compound"]
        let transcription = ["whisper-large-v3", "whisper-large-v3-turbo"]
        let other = ["canopylabs/orpheus-v1-english", "meta-llama/llama-prompt-guard-2-22m", "openai/gpt-oss-safeguard-20b"]

        #expect(chat.allSatisfy(ListedModelKind.isGroqChatModel))
        #expect(!(transcription + other).contains(where: ListedModelKind.isGroqChatModel))
        #expect(transcription.allSatisfy(ListedModelKind.isGroqTranscriptionModel))
        #expect(!(chat + other).contains(where: ListedModelKind.isGroqTranscriptionModel))
    }

    @Test func geminiModelsSplitIntoChatAndTranscription() {
        func model(_ id: String, _ methods: [String] = ["generateContent"]) -> ListedModel {
            ListedModel(id: id, capabilities: methods)
        }
        let chat = [model("gemini-3.8-flash"), model("gemini-3.1-pro-preview"), model("gemini-flash-latest")]
        let other = [
            model("gemini-3.5-transcribe"), model("gemini-3.5-transcribe-live", ["bidiGenerateContent"]),
            model("gemini-3.8-live"), model("gemini-embedding-001", ["embedContent"]), model("gemini-2.5-flash-image"),
            model("gemini-2.5-flash-preview-tts"), model("gemini-2.5-flash-native-audio-preview-12-2025"),
            model("gemini-2.5-computer-use-preview"), model("gemma-3-27b-it"), model("gemini-3.8-flash", ["countTokens"]),
        ]

        #expect(chat.allSatisfy(ListedModelKind.isGeminiChatModel))
        #expect(!other.contains(where: ListedModelKind.isGeminiChatModel))
        #expect(ListedModelKind.isGeminiTranscriptionModel("gemini-3.5-transcribe"))
        #expect(ListedModelKind.isGeminiTranscriptionModel("gemini-3.5-transcribe-live"))
        #expect(!ListedModelKind.isGeminiTranscriptionModel("gemini-3.8-flash"))
    }

    @Test func geminiLiveModelsHaveALivePart() {
        #expect(ListedModelKind.isGeminiLiveModel("gemini-3.5-transcribe-live"))
        #expect(ListedModelKind.isGeminiLiveModel("gemini-3.6-transcribe-live-preview"))
        #expect(!ListedModelKind.isGeminiLiveModel("gemini-3.5-transcribe"))
        #expect(!ListedModelKind.isGeminiLiveModel("gemini-3.6-transcribe-preview"))
    }

    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }
}
