import Testing

@testable import LLMkit

struct GeminiStreamingClientTests {
    @Test func transcribeModelsStreamThroughTheirLiveCounterpart() {
        #expect(GeminiStreamingClient.liveModel(for: "gemini-3.5-transcribe") == "gemini-3.5-transcribe-live")
        #expect(
            GeminiStreamingClient.liveModel(for: "gemini-3.6-transcribe-preview")
                == "gemini-3.6-transcribe-live-preview")
    }

    @Test func liveModelsStreamAsTheyAre() {
        #expect(GeminiStreamingClient.liveModel(for: "gemini-3.5-transcribe-live") == "gemini-3.5-transcribe-live")
        #expect(
            GeminiStreamingClient.liveModel(for: "gemini-3.6-transcribe-live-preview")
                == "gemini-3.6-transcribe-live-preview")
    }
}
