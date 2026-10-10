import SwiftUI

struct DefaultModeIndicator: View {
    var body: some View {
        Text("Default")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quinary, in: Capsule())
            .help("Default mode is used when no app or website matches")
    }
}

/// A mode's icon on a rounded tile, colored like the icons in System Settings. The color is derived from
/// the mode's ID, so each mode keeps the same color across launches.
struct ModeIconTile: View {
    let icon: ModeIcon
    let seed: UUID
    var size: CGFloat = 26

    private static let palette: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .green, .teal, .cyan, .brown,
    ]

    private var tint: Color {
        Self.palette[Int(seed.uuid.0) % Self.palette.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(icon.kind == .emoji ? AnyShapeStyle(.quinary) : AnyShapeStyle(tint.gradient))

            ModeIconView(
                icon: icon,
                size: icon.kind == .emoji ? size * 0.62 : size * 0.5,
                color: .white
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A row in the Modes list: icon tile, name, and a one-line summary of how the mode transcribes.
struct ModeListRow: View {
    let config: ModeConfig
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    var body: some View {
        HStack(spacing: 12) {
            ModeIconTile(icon: config.icon, seed: config.id)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .lineLimit(1)

                    if config.isDefault {
                        DefaultModeIndicator()
                    }
                }

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(isModelMissing ? AnyShapeStyle(AppTheme.Status.error) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ModeShortcutIndicator(modeID: config.id)

            if !config.isEnabled {
                Text("Off")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .opacity(config.isEnabled ? 1 : 0.7)
    }

    private var isModelMissing: Bool {
        if case .available = modelResolution {
            return false
        }
        return true
    }

    private var modelResolution: ModeTranscriptionModelResolution {
        ModeRuntimeResolver.transcriptionModelResolution(
            mode: config,
            transcriptionModelManager: transcriptionModelManager
        )
    }

    private var summary: String {
        var parts: [String] = []

        switch modelResolution {
        case .available(_, let model):
            parts.append(model.displayName)
        case .noMode, .noSelection, .modelNotFound, .unavailable:
            parts.append(String(localized: "Unavailable"))
        }

        if let language = languageName {
            parts.append(language)
        }

        if config.isAIEnhancementEnabled {
            if config.selectedAIProvider == AIProvider.instantVoiceRefine.rawValue {
                parts.append(InstantVoiceRefineService.providerName)
            } else if let prompt = selectedPrompt {
                parts.append(prompt.title)
            }
        }

        if config.outputMode != .paste {
            parts.append(config.outputMode.displayName)
        }

        return parts.joined(separator: " · ")
    }

    private var selectedPrompt: CustomPrompt? {
        guard let promptId = config.selectedPrompt, let uuid = UUID(uuidString: promptId) else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }

    private var languageName: String? {
        guard let code = config.selectedLanguage else { return nil }
        if code == "auto" { return String(localized: "Auto") }

        if let modelName = config.selectedTranscriptionModelName,
            let model = TranscriptionModelRegistry.model(
                forSelectionKey: modelName,
                in: transcriptionModelManager.allAvailableModels
            ),
            let name = TranscriptionLanguageSupport.languages(
                for: model,
                realtimeEnabled: config.isRealtimeTranscriptionEnabled
            )[code]
        {
            return name
        }
        return code.uppercased()
    }
}

struct ModeShortcutIndicator: View {
    let modeID: UUID
    @State private var shortcut: Shortcut?

    private var action: ShortcutAction {
        .mode(modeID)
    }

    init(modeID: UUID) {
        self.modeID = modeID
        _shortcut = State(initialValue: ShortcutStore.shortcut(for: .mode(modeID)))
    }

    var body: some View {
        Group {
            if let shortcut {
                ShortcutVisualization(shortcut: shortcut, isRecording: false, isCompact: true)
                    .help("Mode shortcut: \(shortcut.displayString)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Mode shortcut: \(shortcut.displayString)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let changedAction = notification.object as? ShortcutAction,
                changedAction == action
            else { return }
            shortcut = ShortcutStore.shortcut(for: action)
        }
    }
}
