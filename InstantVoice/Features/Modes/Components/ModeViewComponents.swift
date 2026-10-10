import SwiftUI

struct ModeConfigurationsGrid: View {
    @ObservedObject var modeManager: ModeManager
    let onEditConfig: (ModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach($modeManager.configurations) { $config in
                ConfigurationRow(
                    config: $config,
                    isEditing: false,
                    modeManager: modeManager,
                    onEditConfig: onEditConfig
                )
            }
        }
    }
}

struct DefaultModeIndicator: View {
    var body: some View {
        Label("Default", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quinary, in: Capsule())
            .contentShape(Capsule())
            .help("Default mode is used when no app or website matches")
    }
}

/// A compact metadata token on a mode card, such as its model, language, or prompt.
private struct ModeMetadataChip: View {
    let systemImage: String
    let title: String
    var isWarning = false

    var body: some View {
        Label {
            Text(Self.shortened(title))
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(isWarning ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(isWarning ? AnyShapeStyle(AppTheme.Status.error) : AnyShapeStyle(.quinary))
        }
        .fixedSize()
    }

    /// Chips size to their text, so long names are shortened up front instead of stretching the row.
    private static func shortened(_ title: String) -> String {
        title.count > 26 ? String(title.prefix(24)) + "…" : title
    }
}

private struct ModeShortcutIndicator: View {
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

struct ConfigurationRow: View {
    private struct TranscriptionModelMetadata {
        let label: String
        let isWarning: Bool
    }

    @Binding var config: ModeConfig
    let isEditing: Bool
    let modeManager: ModeManager
    let onEditConfig: (ModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @State private var isHovering = false
    @State private var isShowingDeleteConfirmation = false
    @State private var deletionCandidate: ModeConfig?

    private let maxAppIconsToShow = 5

    private var selectedPrompt: CustomPrompt? {
        guard let promptId = config.selectedPrompt,
            let uuid = UUID(uuidString: promptId)
        else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }

    private var transcriptionModelMetadata: TranscriptionModelMetadata {
        switch ModeRuntimeResolver.transcriptionModelResolution(
            mode: config,
            transcriptionModelManager: transcriptionModelManager
        ) {
        case .available(_, let model):
            return TranscriptionModelMetadata(
                label: model.displayName,
                isWarning: false
            )
        case .noMode, .noSelection, .modelNotFound, .unavailable:
            return TranscriptionModelMetadata(
                label: String(localized: "Unavailable"),
                isWarning: true
            )
        }
    }

    private var selectedLanguage: String? {
        if let langCode = config.selectedLanguage {
            if langCode == "auto" { return String(localized: "Auto") }
            if langCode == "en" { return String(localized: "English") }

            if let modelName = config.selectedTranscriptionModelName,
                let model = TranscriptionModelRegistry.model(
                    forSelectionKey: modelName,
                    in: transcriptionModelManager.allAvailableModels
                ),
                let langName = TranscriptionLanguageSupport.languages(
                    for: model, realtimeEnabled: config.isRealtimeTranscriptionEnabled)[langCode]
            {
                return langName
            }
            return langCode.uppercased()
        }
        return "Default"
    }

    private var appCount: Int { return config.allAppConfigs.count }
    private var websiteCount: Int { return config.allURLConfigs.count }

    private var websiteText: String {
        if websiteCount == 0 { return "" }
        return String(localized: "\(websiteCount) Websites")
    }

    private var appText: String {
        if appCount == 0 { return "" }
        return String(localized: "\(appCount) Apps")
    }

    private var extraAppsCount: Int {
        return max(0, appCount - maxAppIconsToShow)
    }

    private var visibleAppConfigs: [AppConfig] {
        return Array(config.allAppConfigs.prefix(maxAppIconsToShow))
    }

    @ViewBuilder private var modeActions: some View {
        Button {
            onEditConfig(config)
        } label: {
            Text("Edit")
        }

        Button {
            modeManager.duplicateConfiguration(with: config.id)
        } label: {
            Text("Duplicate")
        }

        Divider()

        Button(role: .destructive) {
            deletionCandidate = config
            isShowingDeleteConfirmation = true
        } label: {
            Text("Delete")
        }
        .disabled(config.isDefault)
    }

    private var editModeButton: some View {
        Button("Edit") {
            onEditConfig(config)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Edit mode")
        .accessibilityLabel("Edit mode")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { config.isEnabled },
            set: { newValue in
                if newValue {
                    modeManager.enableConfiguration(with: config.id)
                } else {
                    modeManager.disableConfiguration(with: config.id)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 20 : 17, color: .primary)
                        .frame(width: 40, height: 40)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(config.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if appCount > 0 || websiteCount > 0 {
                            HStack(spacing: 10) {
                                if appCount > 0 {
                                    Label(appText, systemImage: "app")
                                }

                                if websiteCount > 0 {
                                    Label(websiteText, systemImage: "globe")
                                }
                            }
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if config.isDefault {
                        DefaultModeIndicator()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onEditConfig(config)
                }

                if !config.isDefault {
                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(config.isEnabled ? "Disable mode" : "Enable mode")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

            Divider()
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                let modelMetadata = transcriptionModelMetadata
                ModeMetadataChip(
                    systemImage: "waveform",
                    title: modelMetadata.label,
                    isWarning: modelMetadata.isWarning
                )

                if let language = selectedLanguage, language != "Default" {
                    ModeMetadataChip(systemImage: "globe", title: language)
                }

                if config.isAIEnhancementEnabled,
                    config.selectedAIProvider != AIProvider.localCLI.rawValue,
                    let modelName = config.selectedAIModel,
                    !modelName.isEmpty
                {
                    ModeMetadataChip(systemImage: "cpu", title: modelName)
                }

                if config.outputMode != .paste {
                    ModeMetadataChip(systemImage: config.outputMode.iconName, title: config.outputMode.displayName)
                }

                if config.isAIEnhancementEnabled {
                    ModeMetadataChip(
                        systemImage: "sparkles",
                        title: config.selectedAIProvider == AIProvider.instantVoiceRefine.rawValue
                            ? InstantVoiceRefineService.providerName
                            : selectedPrompt?.title ?? "AI"
                    )
                }

                ModeShortcutIndicator(modeID: config.id)

                Spacer(minLength: 0)

                if isHovering {
                    editModeButton
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 22)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                onEditConfig(config)
            }
        }
        .background(AppCardBackground(isSelected: isEditing, cornerRadius: DashboardLayout.cardCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
        .opacity(config.isEnabled ? 1.0 : 0.70)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            modeActions
        }
        .confirmationDialog(
            "Delete Mode?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletionCandidate {
                    _ = modeManager.removeConfiguration(with: deletionCandidate.id)
                }
                deletionCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
            }
        } message: {
            if let deletionCandidate {
                Text(
                    String(
                        format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                        deletionCandidate.name
                    )
                )
            }
        }
    }

}

struct ModeAppIcon: View {
    let bundleId: String

    var body: some View {
        if let icon = TriggerAppIconCache.shared.icon(for: bundleId) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

struct AppGridItem: View {
    let app: (url: URL, name: String, bundleId: String, icon: NSImage)
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .shadow(color: Color(NSColor.shadowColor).opacity(0.1), radius: 2, x: 0, y: 1)
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
            }
            .frame(width: 80, height: 80)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.Accent.fillSubtle : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.Accent.primary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
