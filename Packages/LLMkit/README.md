# LLMkit

A lightweight Swift package that provides stateless API clients for cloud transcription, LLM chat completion, and real-time streaming transcription services. Built for [VoiceInk](https://github.com/Beingpax/VoiceInk), but usable in any Swift project.

## What It Does

LLMkit is a pure networking layer — no UI, no persistence, no app state. It handles HTTP requests, multipart uploads, WebSocket connections, error mapping, and automatic retries with exponential backoff on transient failures (429, 5xx).

## Clients

**Transcription** (audio file → text):
- `DeepgramClient`, `ElevenLabsClient`, `SonioxClient`, `MistralTranscriptionClient`, `GeminiTranscriptionClient`, `OpenAITranscriptionClient`

**LLM Chat Completion** (messages → response):
- `AnthropicLLMClient`, `GeminiLLMClient`, `OpenAILLMClient`, `OllamaClient`, `OpenRouterClient`

**Streaming Transcription** (live audio → real-time text via WebSocket):
- `ElevenLabsStreamingClient`, `DeepgramStreamingClient`, `GeminiStreamingClient`, `MistralStreamingClient`, `SonioxStreamingClient`

## Usage

All batch clients use static methods — no initialization needed:

```swift
import LLMkit

let text = try await DeepgramClient.transcribe(
    apiKey: "...", audioData: data, model: "nova-3", language: "en"
)

let response = try await AnthropicLLMClient.chatCompletion(
    apiKey: "...", model: "claude-sonnet-4-5-20250929", messages: [.user("Hello")]
)

let geminiResponse = try await GeminiLLMClient.chatCompletion(
    apiKey: "...",
    model: "gemini-3.6-flash",
    messages: [.user("Hello")],
    thinkingLevel: .minimal,
    store: false
)

let geminiTranscript = try await GeminiTranscriptionClient.transcribe(
    audioData: data,
    apiKey: "...",
    model: "gemini-3.5-transcribe",
    fileName: "recording.wav",
    language: "en-US",
    customVocabulary: ["VoiceInk"],
    mode: .smart
)
```

Streaming clients are class-based with `AsyncStream` event delivery:

```swift
let client = DeepgramStreamingClient()
try await client.connect(apiKey: "...", model: "nova-3", language: "en")
for await event in client.transcriptionEvents { /* .partial, .committed, .error */ }
```

`GeminiTranscriptionClient` uploads dedicated-model audio through the Gemini Files API, creates a
non-stored Interactions request, and deletes the uploaded file after the request completes. Use
`GeminiStreamingClient` with `gemini-3.5-transcribe`; it automatically selects the corresponding
`gemini-3.5-transcribe-live` model and uses Verbatim transcription.

For Nova-3 multilingual and code-switching transcription, pass `language: "multi"`. Deepgram defaults an
omitted language to English. Both the batch and streaming clients send custom vocabulary as Nova-3 `keyterm`
parameters; up to 100 terms are accepted by the client, subject to Deepgram's 500-token total limit.

For Soniox speech that mixes known languages, pass `languages: ["en", "zh"]` to `SonioxClient.transcribe` or
`SonioxStreamingClient.connect`. They're sent as strict `language_hints`, so Soniox keeps to those languages.
An empty array, `language: nil`, or `"auto"` lets Soniox identify the language itself.

`listModels` fetches a provider's current models as `[ListedModel]`. It exists on `OpenAILLMClient` (any
OpenAI-compatible API, given its root such as `https://api.groq.com/openai/v1`), `AnthropicLLMClient`,
`GeminiLLMClient`, `DeepgramClient`, and `SonioxClient`. Most list endpoints don't say what a model is for, so
`ListedModelKind` sorts chat and speech-to-text models by each provider's documented ID conventions. ElevenLabs,
xAI, and Cartesia don't list their speech-to-text models.

## Requirements

- Swift 6.2+, macOS 14+, iOS 17+
- Zero external dependencies — uses only Foundation and `URLSession`

## Error Handling

All clients throw `LLMKitError` with cases for missing keys, HTTP errors, network failures, decoding issues, and timeouts.

### AssemblyAI realtime model selection

`AssemblyAIStreamingClient` forwards the `model` string to AssemblyAI without a
hardcoded model list. Select `universal-3-6-pro`, `universal-3-6` (preview),
`universal-3-5-pro`, or a future model compatible with the v3 streaming protocol.
AssemblyAI validates model availability and language support.

```swift
let client = AssemblyAIStreamingClient()
try await client.connect(
    apiKey: apiKey,
    model: "universal-3-6-pro",
    language: "en",
    prompt: nil,
    customVocabulary: ["VoiceInk"],
    additionalParameters: ["mode": "balanced"]
)
```

Use `additionalParameters` for optional or newly introduced connection options.
Values are URL-encoded; array or object values must be supplied as JSON strings.
The selected model and authentication cannot be overridden through this dictionary.
The `language` argument uses `language_codes`; omit it or pass `"auto"` for native
multilingual transcription. A nonempty `prompt` is forwarded when explicitly set.

Consume `transcriptionEvents` for live partials and finalized segments. After
`commit()`, consume `finalizationEvents` to receive the complete transcript once
AssemblyAI acknowledges termination. This final transcript incorporates revised
formatting and avoids repeated turns. Existing consumers still receive the empty
committed event at termination as a completion signal.
