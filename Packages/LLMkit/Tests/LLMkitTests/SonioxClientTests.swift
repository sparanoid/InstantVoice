import Testing

@testable import LLMkit

struct SonioxClientTests {
    @Test func noLanguagesAutoDetect() {
        let body = languageFields(for: [])

        #expect(body["language_hints"] == nil)
        #expect(body["language_hints_strict"] == nil)
        #expect(body["enable_language_identification"] as? Bool == true)
    }

    @Test func autoMeansAutoDetect() {
        let body = languageFields(for: ["auto"])

        #expect(body["language_hints"] == nil)
        #expect(body["language_hints_strict"] == nil)
        #expect(body["enable_language_identification"] as? Bool == true)
    }

    @Test func singleLanguageIsStrict() {
        let body = languageFields(for: ["en"])

        #expect(body["language_hints"] as? [String] == ["en"])
        #expect(body["language_hints_strict"] as? Bool == true)
        #expect(body["enable_language_identification"] as? Bool == true)
    }

    @Test func multipleLanguagesKeepTheirOrder() {
        let body = languageFields(for: ["zh", "en", "ja"])

        #expect(body["language_hints"] as? [String] == ["zh", "en", "ja"])
        #expect(body["language_hints_strict"] as? Bool == true)
    }

    @Test func blankAutoAndRepeatedLanguagesAreDropped() {
        let body = languageFields(for: [" en ", "", "auto", "zh", "en"])

        #expect(body["language_hints"] as? [String] == ["en", "zh"])
    }

    @Test func otherFieldsAreKept() {
        var body: [String: Any] = ["model": "stt-rt-v5"]
        SonioxClient.addLanguageHints(["en"], to: &body)

        #expect(body["model"] as? String == "stt-rt-v5")
    }

    private func languageFields(for languages: [String]) -> [String: Any] {
        var body: [String: Any] = [:]
        SonioxClient.addLanguageHints(languages, to: &body)
        return body
    }
}
