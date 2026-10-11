import SwiftUI

/// A transcription's details as a grouped form: when it was recorded, the models that processed it, and the
/// recorded AI request. History shows it in the window's inspector, and Quick History in its Info popover.
struct TranscriptionInspector: View {
    let transcription: Transcription

    @State private var isSystemPromptExpanded = false
    @State private var isUserMessageExpanded = false
    @State private var didCopyRequest = false

    var body: some View {
        Form {
            recordingSection
            transcriptionSection
            enhancementSection
            aiRequestSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    private var recordingSection: some View {
        Section {
            LabeledContent("Date") {
                Text(transcription.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .textSelection(.enabled)
            }

            LabeledContent("Duration", value: transcription.duration.formatTiming())

            if let modeName = transcription.modeName, !modeName.isEmpty {
                LabeledContent("Mode") {
                    Label {
                        Text(modeName)
                    } icon: {
                        if let icon = transcription.recordedHistoryModeIcon {
                            ModeIconView(icon: icon, size: 12, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptionSection: some View {
        if let modelName = transcription.transcriptionModelName {
            Section("Transcription") {
                LabeledContent("Model") {
                    Text(modelName)
                        .textSelection(.enabled)
                }

                if let duration = transcription.transcriptionDuration {
                    LabeledContent("Processing Time", value: duration.formatTiming())
                }
            }
        }
    }

    @ViewBuilder
    private var enhancementSection: some View {
        if transcription.aiEnhancementModelName != nil || transcription.promptName != nil {
            Section("Enhancement") {
                if let modelName = transcription.aiEnhancementModelName {
                    LabeledContent("Model") {
                        Text(modelName)
                            .textSelection(.enabled)
                    }
                }

                if let promptName = transcription.promptName {
                    LabeledContent("Prompt", value: promptName)
                }

                if let duration = transcription.enhancementDuration {
                    LabeledContent("Processing Time", value: duration.formatTiming())
                }
            }
        }
    }

    @ViewBuilder
    private var aiRequestSection: some View {
        if systemMessage != nil || userMessage != nil {
            Section {
                if let systemMessage {
                    DisclosureGroup("System Prompt", isExpanded: $isSystemPromptExpanded) {
                        requestText(systemMessage)
                    }
                }

                if let userMessage {
                    DisclosureGroup("User Message", isExpanded: $isUserMessageExpanded) {
                        requestText(userMessage)
                    }
                }

                LabeledContent("Estimated Tokens") {
                    Text(estimatedTokenCount, format: .number)
                        .monospacedDigit()
                }
                .help("Token count is estimated from the request text.")
            } header: {
                Text("AI Request")
            } footer: {
                HStack {
                    Spacer()
                    Button(action: copyRequest) {
                        if didCopyRequest {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Text("Copy Request")
                        }
                    }
                }
            }
        }
    }

    // MARK: - AI Request

    private var systemMessage: String? {
        transcription.aiRequestSystemMessage.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var userMessage: String? {
        transcription.aiRequestUserMessage.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var estimatedTokenCount: Int {
        EstimatedTokenCounter.count(in: [systemMessage, userMessage]) ?? 0
    }

    private func requestText(_ message: String) -> some View {
        Text(message)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyRequest() {
        var parts: [String] = []
        if let systemMessage {
            parts.append("System Prompt:\n\(systemMessage)")
        }
        if let userMessage {
            parts.append("User Message:\n\(userMessage)")
        }
        guard ClipboardManager.copyToClipboard(parts.joined(separator: "\n\n")) else { return }

        didCopyRequest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyRequest = false
        }
    }
}
