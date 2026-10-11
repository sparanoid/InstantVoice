import AppKit
import SwiftData
import SwiftUI

/// Quick History's actions for the transcription it shows. The main window offers them in its toolbar instead.
struct HistoryDetailActionBar: View {
    let transcription: Transcription
    let audioURL: URL?
    let onTranscriptionUpdated: (Transcription) -> Void
    /// Adds an Info button whose popover shows the transcription's details.
    var isInfoPresented: Binding<Bool>? = nil
    var onPaste: (() -> Void)? = nil

    @EnvironmentObject private var engine: InstantVoiceEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modeManager = ModeManager.shared

    @State private var didCopy = false
    @State private var isShowingModes = false
    @State private var isShowingPrompts = false
    @State private var reprocessor = TranscriptionReprocessor()

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    private var enhancementConfiguration: EnhancementRuntimeConfiguration? {
        TranscriptionReprocessor.enhancementConfiguration(mode: selectedMode, enhancementService: enhancementService)
    }

    private var selectedPromptTitle: String {
        reprocessor.pendingPrompt?.title
            ?? transcription.promptName
            ?? enhancementConfiguration?.prompt?.title
            ?? String(localized: "Select Prompt")
    }

    var body: some View {
        HStack(spacing: 8) {
            modeButton
            promptButton
            retryButton
            finderButton
            infoButton
            Spacer(minLength: 8)
            textActionButton
        }
        .padding(.horizontal, 10)
        .frame(height: HistoryLayout.actionBarHeight)
    }

    private var modeButton: some View {
        Button {
            isShowingModes.toggle()
        } label: {
            actionLabel(title: selectedMode?.name ?? String(localized: "Select Mode")) {
                if let selectedMode {
                    ModeIconView(
                        icon: selectedMode.icon,
                        size: selectedMode.icon.kind == .emoji ? 13 : 11,
                        color: AppTheme.Text.primary
                    )
                    .frame(width: 16)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(reprocessor.isWorking)
        .popover(isPresented: $isShowingModes, arrowEdge: .bottom) {
            ModePopover(selectedModeId: selectedMode?.id) { mode in
                modeManager.setActiveConfiguration(mode)
                isShowingModes = false
                retranscribe(using: mode)
            }
        }
        .help("Select a mode and retranscribe")
    }

    private var promptButton: some View {
        Button {
            isShowingPrompts.toggle()
        } label: {
            actionLabel(title: selectedPromptTitle) {
                Image(systemName: "wand.and.stars")
            }
        }
        .buttonStyle(.plain)
        .disabled(reprocessor.isWorking)
        .popover(isPresented: $isShowingPrompts, arrowEdge: .bottom) {
            promptPopover
        }
        .help("Select a prompt and enhance")
    }

    private var textActionButton: some View {
        HistoryCommandButton(
            onPaste == nil ? "Copy transcription" : "Paste Text",
            systemImage: onPaste == nil ? (didCopy ? "checkmark" : "doc.on.doc") : nil,
            shortcut: onPaste == nil ? nil : "↵",
            minimumWidth: 112,
            action: performTextAction
        )
        .help(
            onPaste == nil
                ? "Copy transcription"
                : "Paste enhanced text when available, otherwise paste the original transcription"
        )
    }

    private func performTextAction() {
        if let onPaste {
            onPaste()
        } else {
            let _ = ClipboardManager.copyToClipboard(transcription.preferredHistoryText)
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        }
    }

    private var retryButton: some View {
        HistoryIconButton(
            systemName: "arrow.clockwise",
            help: "Retranscribe with the selected mode",
            isLoading: reprocessor.isWorking
        ) {
            guard let selectedMode else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "No mode selected"),
                    type: .error,
                    duration: 3.0
                )
                return
            }
            retranscribe(using: selectedMode)
        }
        .disabled(reprocessor.isWorking || audioURL == nil)
    }

    private var finderButton: some View {
        HistoryIconButton(systemName: "folder", help: "Show recording in Finder") {
            guard let audioURL else { return }
            NSWorkspace.shared.selectFile(
                audioURL.path,
                inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path
            )
        }
        .disabled(audioURL == nil)
    }

    @ViewBuilder
    private var infoButton: some View {
        if let isInfoPresented {
            HistoryIconButton(
                systemName: "info.circle",
                help: isInfoPresented.wrappedValue ? "Hide transcription info" : "Show transcription info",
                isSelected: isInfoPresented.wrappedValue
            ) {
                isInfoPresented.wrappedValue.toggle()
            }
            .popover(isPresented: isInfoPresented, arrowEdge: .top) {
                // Fits short details, and scrolls long AI requests.
                TranscriptionInspector(transcription: transcription)
                    .frame(width: 320)
                    .frame(maxHeight: 440)
                    .popoverAppAppearance()
            }
        }
    }

    private func actionLabel<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 7) {
            icon()
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppTheme.Text.muted)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Text.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: 140)
        .frame(height: HistoryLayout.buttonHeight)
        .clipped()
        .background(QuickPanelButtonBackground())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var promptPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Prompt")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ScrollView {
                let prompts = enhancementService.allPrompts
                let promptsUnavailable = enhancementConfiguration?.provider == .instantVoiceRefine

                VStack(alignment: .leading, spacing: 4) {
                    if promptsUnavailable {
                        Text("Custom prompts aren't available with InstantVoice Refine. Select another mode first.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }

                    if prompts.isEmpty {
                        Text("No Prompts Available")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(prompts) { prompt in
                            EnhancementPromptRow(
                                prompt: prompt,
                                isSelected: enhancementConfiguration?.prompt?.id == prompt.id,
                                isDisabled: promptsUnavailable,
                                action: {
                                    isShowingPrompts = false
                                    enhance(using: prompt)
                                }
                            )
                            .disabled(promptsUnavailable)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 230)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(AppTheme.Surface.window)
        .popoverAppAppearance()
    }

    private func retranscribe(using mode: ModeConfig) {
        reprocessor.retranscribe(
            transcription,
            using: mode,
            engine: engine,
            modelContext: modelContext,
            onUpdated: onTranscriptionUpdated
        )
    }

    private func enhance(using prompt: CustomPrompt) {
        reprocessor.enhance(
            transcription,
            using: prompt,
            configuration: enhancementConfiguration,
            enhancementService: enhancementService,
            modelContext: modelContext
        )
    }
}
