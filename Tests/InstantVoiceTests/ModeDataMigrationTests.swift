import Testing

@testable import InstantVoice

struct ModeDataMigrationTests {
    @Test func builtInModelNamesChangeWhenACustomModelSharesThem() {
        // Earlier versions resolved these names to the built-in models before the custom models.
        let modes = ModeManager.withRawModelNames(
            [mode(modelName: "nova-3", realtime: false), mode(modelName: "stt-async-v5", realtime: true)],
            customModelNames: ["nova-3", "stt-async-v5"])

        #expect(modes.map(\.selectedTranscriptionModelName) == ["nova-3-general", "stt-rt-v5"])
    }

    @Test func otherNamesStayWhenACustomModelUsesThem() {
        let modes = [mode(modelName: "nova-2", realtime: false)]

        let withCustomModel = ModeManager.withRawModelNames(modes, customModelNames: ["nova-2"])
        let withoutCustomModel = ModeManager.withRawModelNames(modes, customModelNames: [])

        #expect(withCustomModel.map(\.selectedTranscriptionModelName) == ["nova-2"])
        #expect(withoutCustomModel.map(\.selectedTranscriptionModelName) == ["nova-2-general"])
    }

    private func mode(modelName: String, realtime: Bool) -> ModeConfig {
        ModeConfig(
            name: modelName, isAIEnhancementEnabled: false, selectedTranscriptionModelName: modelName,
            isRealtimeTranscriptionEnabled: realtime)
    }
}
