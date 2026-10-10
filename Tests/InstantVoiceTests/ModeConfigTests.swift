import Foundation
import Testing

@testable import InstantVoice

struct ModeConfigTests {
    @Test func additionalLanguagesSurviveSaveAndLoad() throws {
        let mode = ModeConfig(
            name: "Mixed", isAIEnhancementEnabled: false, selectedTranscriptionModelName: "stt-rt-v5",
            selectedLanguage: "en", additionalLanguages: ["zh", "ja"])

        // ModeManager saves modes as a JSON array.
        let data = try JSONEncoder().encode([mode])
        let decoded = try JSONDecoder().decode([ModeConfig].self, from: data)
        let loaded = try #require(decoded.first)

        #expect(loaded.selectedLanguage == "en")
        #expect(loaded.additionalLanguages == ["zh", "ja"])
    }

    @Test func modesSavedWithoutAdditionalLanguagesStillLoad() throws {
        // Saved by a build that predates additional languages, so the key is missing.
        let data = Data(
            """
            [{"id": "8A8D6C1E-2F4B-4C7A-9E3D-5B1F0A2C4D6E", "name": "Dictation",
              "icon": {"kind": "symbol", "value": "mic.fill"}, "isAIEnhancementEnabled": false,
              "isRealtimeTranscriptionEnabled": true, "selectedLanguage": "en",
              "selectedTranscriptionModelName": "stt-async-v5", "isTextFormattingEnabled": false,
              "useClipboardContext": false, "useSelectedTextContext": true, "useScreenCapture": false,
              "outputMode": "paste", "isEnabled": true, "isDefault": true}]
            """.utf8)

        let decoded = try JSONDecoder().decode([ModeConfig].self, from: data)
        let loaded = try #require(decoded.first)

        #expect(loaded.name == "Dictation")
        #expect(loaded.selectedLanguage == "en")
        #expect(loaded.selectedTranscriptionModelName == "stt-async-v5")
        #expect(loaded.additionalLanguages.isEmpty)
    }
}
