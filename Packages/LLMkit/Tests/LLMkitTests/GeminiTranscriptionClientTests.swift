import Testing

@testable import LLMkit

struct GeminiTranscriptionClientTests {
    @Test func acceptsListedTranscriptionModels() {
        #expect(GeminiTranscriptionClient.acceptsModel("gemini-3.5-transcribe"))
        #expect(GeminiTranscriptionClient.acceptsModel("gemini-3.6-transcribe-preview"))
    }

    @Test func rejectsLiveAndChatModels() {
        #expect(!GeminiTranscriptionClient.acceptsModel("gemini-3.5-transcribe-live"))
        #expect(!GeminiTranscriptionClient.acceptsModel("gemini-3.6-transcribe-live-preview"))
        #expect(!GeminiTranscriptionClient.acceptsModel("gemini-3.8-flash"))
    }
}
