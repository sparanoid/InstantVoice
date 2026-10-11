import SwiftData
import SwiftUI

/// Retranscribes or re-enhances a history item for History's toolbar and Quick History's action bar, tracking the
/// work so their controls can disable themselves and show progress meanwhile.
@MainActor
@Observable
final class TranscriptionReprocessor {
    enum Activity {
        case retranscribing
        case enhancing
    }

    private(set) var activity: Activity?
    /// The transcription being reprocessed while `activity` is set.
    private(set) var transcriptionID: UUID?
    /// The prompt being applied, so prompt pickers can show it before the result is saved.
    private(set) var pendingPrompt: CustomPrompt?

    var isWorking: Bool { activity != nil }

    /// The active mode's enhancement settings, which re-enhancing reuses with the chosen prompt.
    static func enhancementConfiguration(
        mode: ModeConfig?,
        enhancementService: AIEnhancementService
    ) -> EnhancementRuntimeConfiguration? {
        guard let aiService = enhancementService.getAIService() else { return nil }
        return ModeRuntimeResolver.currentEnhancementConfiguration(
            mode: mode,
            enhancementService: enhancementService,
            aiService: aiService
        )
    }

    func retranscribe(
        _ transcription: Transcription,
        using mode: ModeConfig,
        engine: InstantVoiceEngine,
        modelContext: ModelContext,
        onUpdated: @escaping (Transcription) -> Void
    ) {
        guard !isWorking else { return }
        guard let audioURL = transcription.availableHistoryAudioURL else {
            Self.showError(String(localized: "Audio file is unavailable"))
            return
        }
        guard let configuration = ModeRuntimeResolver.transcriptionConfiguration(
            mode: mode,
            transcriptionModelManager: engine.transcriptionModelManager
        ) else {
            Self.showError(String(localized: "No transcription model selected"))
            return
        }

        begin(.retranscribing, on: transcription)
        let service = AudioTranscriptionService(modelContext: modelContext, engine: engine)

        Task {
            defer { finish() }
            do {
                let result = try await service.retranscribeAudio(
                    from: audioURL,
                    using: configuration.model,
                    mode: mode
                )
                if let failure = result.enhancementFailure {
                    NotificationManager.shared.showNotification(
                        title: EnhancementFailureFormatter.transcriptionSavedMessage(description: failure),
                        type: .warning
                    )
                } else {
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Retranscription successful"),
                        type: .success,
                        duration: 1.0
                    )
                }
                onUpdated(result.transcription)
            } catch {
                Self.showError(
                    error.localizedDescription.isEmpty
                        ? String(localized: "Retranscription failed")
                        : error.localizedDescription
                )
            }
        }
    }

    func enhance(
        _ transcription: Transcription,
        using prompt: CustomPrompt,
        configuration baseConfiguration: EnhancementRuntimeConfiguration?,
        enhancementService: AIEnhancementService,
        modelContext: ModelContext
    ) {
        guard !isWorking else { return }
        guard let baseConfiguration else {
            Self.showError(String(localized: "AI Enhancement is not enabled or configured"))
            return
        }

        begin(.enhancing, on: transcription)
        pendingPrompt = prompt
        let configuration = baseConfiguration.replacingPrompt(prompt)

        Task {
            defer { finish() }
            do {
                transcription.aiEnhancementModelName =
                    configuration.modelName ?? configuration.provider?.defaultModel
                transcription.promptName = configuration.prompt?.title
                let result = try await enhancementService.enhance(
                    transcription.text,
                    configuration: configuration
                )
                transcription.enhancedText = result.text
                transcription.aiEnhancementModelName =
                    configuration.modelName ?? configuration.provider?.defaultModel
                transcription.promptName = result.promptName ?? configuration.prompt?.title
                transcription.enhancementDuration = result.duration
                transcription.aiRequestSystemMessage = result.systemMessage
                transcription.aiRequestUserMessage = result.userMessage
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    Self.showError(
                        error.localizedDescription.isEmpty
                            ? String(localized: "Could not save re-enhancement")
                            : error.localizedDescription
                    )
                    return
                }
                NotificationManager.shared.showNotification(
                    title: String(localized: "Re-enhancement successful"),
                    type: .success,
                    duration: 1.0
                )
            } catch {
                let description = EnhancementFailureFormatter.description(for: error)
                Self.showError(EnhancementFailureFormatter.reEnhancementMessage(description: description))
            }
        }
    }

    private func begin(_ activity: Activity, on transcription: Transcription) {
        self.activity = activity
        transcriptionID = transcription.id
    }

    private func finish() {
        activity = nil
        transcriptionID = nil
        pendingPrompt = nil
    }

    private static func showError(_ title: String) {
        NotificationManager.shared.showNotification(title: title, type: .error, duration: 3.0)
    }
}
