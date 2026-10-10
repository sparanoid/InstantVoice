import SwiftData
import SwiftUI

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

enum ConfigurationMode: Hashable {
    case add
    case edit(ModeConfig)

    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }

    static func == (lhs: ConfigurationMode, rhs: ConfigurationMode) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

enum ConfigurationType {
    case application
    case website
}

struct ModeView: View {
    @StateObject private var modeManager = ModeManager.shared
    @StateObject private var modeWarmupStore = ModeFormWarmupStore.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var activePanel: PanelType?
    @State private var panelID = UUID()

    private enum PanelType {
        case configuration(ConfigurationMode)
        case settings
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    var body: some View {
        Group {
            if modeManager.configurations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    ModeConfigurationsGrid(
                        modeManager: modeManager,
                        onEditConfig: { config in
                            openPanel(mode: .edit(config))
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ScreenInfoButton(
                    title: "Info",
                    message: "Modes help you set up InstantVoice for different writing tasks, workflows, and scenarios.",
                    learnMoreURL: "https://tryvoiceink.com/docs/modes"
                )

                Button(action: openSettingsPanel) {
                    Label("Modes Settings", systemImage: "gearshape")
                }
                .help("Modes Settings")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    openPanel(mode: .add)
                } label: {
                    Label("Add Mode", systemImage: "plus")
                }
                .help("Add a new mode")
            }
        }
        .sidePanel(
            isPresented: .init(
                get: { isPanelOpen },
                set: { if !$0 { closePanel() } }
            ), dismissOnExitCommand: false
        ) {
            switch activePanel {
            case .configuration(let mode)?:
                ModeConfigEditorView(mode: mode, modeManager: modeManager, onDismiss: closePanel)
                    .environmentObject(modeWarmupStore)
                    .id(panelID)
            case .settings?:
                ModeSettingsPanelView(modeManager: modeManager, onDismiss: closePanel)
            case nil:
                EmptyView()
            }
        }
        .onAppear {
            modeWarmupStore.configure(
                aiService: aiService,
                enhancementService: enhancementService,
                transcriptionModelManager: transcriptionModelManager
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Create your first mode", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Set how InstantVoice transcribes and formats your speech, then start dictating in any app.")
        } actions: {
            Button("Add Mode") {
                openPanel(mode: .add)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func openPanel(mode: ConfigurationMode) {
        panelID = UUID()
        activePanel = .configuration(mode)
    }

    private func closePanel() {
        activePanel = nil
    }

    private func openSettingsPanel() {
        activePanel = .settings
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}
