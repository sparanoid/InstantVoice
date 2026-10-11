import AppKit
import SwiftData
import SwiftUI

/// History's actions for the selected transcriptions, grouped in the window toolbar like Mail's message actions.
struct HistoryTranscriptionToolbar: ToolbarContent {
    /// The item that single-item actions apply to; nil when none or several rows are selected.
    let transcription: Transcription?
    let selectionCount: Int
    let reprocessor: TranscriptionReprocessor
    let onTranscriptionUpdated: (Transcription) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HistoryRetranscribeMenu(
                transcription: transcription,
                reprocessor: reprocessor,
                onTranscriptionUpdated: onTranscriptionUpdated
            )
            HistoryEnhanceMenu(transcription: transcription, reprocessor: reprocessor)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            HistoryCopyButton(isEnabled: selectionCount > 0, action: onCopy)

            Button(action: revealRecording) {
                Label("Show in Finder", systemImage: "folder")
            }
            .help("Show recording in Finder")
            .disabled(transcription?.availableHistoryAudioURL == nil)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected transcriptions")
            .disabled(selectionCount == 0)
        }
    }

    private func revealRecording() {
        guard let audioURL = transcription?.availableHistoryAudioURL else { return }
        NSWorkspace.shared.selectFile(
            audioURL.path,
            inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path
        )
    }
}

/// Retranscribes with the current mode on click; its menu picks another mode, makes it current, and retranscribes.
private struct HistoryRetranscribeMenu: View {
    let transcription: Transcription?
    let reprocessor: TranscriptionReprocessor
    let onTranscriptionUpdated: (Transcription) -> Void

    @EnvironmentObject private var engine: InstantVoiceEngine
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modeManager = ModeManager.shared

    var body: some View {
        let currentMode = modeManager.currentEffectiveConfiguration

        Menu {
            ForEach(modeManager.enabledConfigurations) { mode in
                Toggle(
                    isOn: Binding(
                        get: { mode.id == currentMode?.id },
                        set: { _ in
                            modeManager.setActiveConfiguration(mode)
                            retranscribe(using: mode)
                        }
                    )
                ) {
                    HistoryModeMenuLabel(mode: mode)
                }
            }
        } label: {
            Label("Retranscribe", systemImage: "arrow.clockwise")
        } primaryAction: {
            guard let currentMode else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "No mode selected"),
                    type: .error,
                    duration: 3.0
                )
                return
            }
            retranscribe(using: currentMode)
        }
        .help("Retranscribe with the selected mode")
        .disabled(reprocessor.isWorking || transcription?.availableHistoryAudioURL == nil)
    }

    private func retranscribe(using mode: ModeConfig) {
        guard let transcription else { return }
        reprocessor.retranscribe(
            transcription,
            using: mode,
            engine: engine,
            modelContext: modelContext,
            onUpdated: onTranscriptionUpdated
        )
    }
}

/// Lists prompts with the current one checked; choosing one re-enhances the transcription with it.
private struct HistoryEnhanceMenu: View {
    let transcription: Transcription?
    let reprocessor: TranscriptionReprocessor

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modeManager = ModeManager.shared

    var body: some View {
        let configuration = TranscriptionReprocessor.enhancementConfiguration(
            mode: modeManager.currentEffectiveConfiguration,
            enhancementService: enhancementService
        )
        let promptsUnavailable = configuration?.provider == .instantVoiceRefine
        let prompts = enhancementService.allPrompts

        Menu {
            if promptsUnavailable {
                Text("Custom prompts aren't available with InstantVoice Refine. Select another mode first.")
            }

            if prompts.isEmpty {
                Text("No Prompts Available")
            } else {
                ForEach(prompts) { prompt in
                    Toggle(
                        prompt.title,
                        isOn: Binding(
                            get: { configuration?.prompt?.id == prompt.id },
                            set: { _ in enhance(using: prompt, configuration: configuration) }
                        )
                    )
                    .disabled(promptsUnavailable)
                }
            }
        } label: {
            Label("Enhance", systemImage: "wand.and.stars")
        }
        .help("Select a prompt and enhance")
        .disabled(reprocessor.isWorking || transcription == nil)
    }

    private func enhance(using prompt: CustomPrompt, configuration: EnhancementRuntimeConfiguration?) {
        guard let transcription else { return }
        reprocessor.enhance(
            transcription,
            using: prompt,
            configuration: configuration,
            enhancementService: enhancementService,
            modelContext: modelContext
        )
    }
}

/// A mode's name with its symbol, or its emoji, which menu items can't draw as an image.
private struct HistoryModeMenuLabel: View {
    let mode: ModeConfig

    var body: some View {
        switch mode.icon.kind {
        case .symbol:
            Label(mode.name, systemImage: mode.icon.value)
        case .emoji:
            Text(verbatim: "\(mode.icon.value) \(mode.name)")
        }
    }
}

private struct HistoryCopyButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var didCopy = false

    var body: some View {
        Button {
            action()
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        } label: {
            Label("Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .help("Copy transcription")
        .disabled(!isEnabled)
    }
}
