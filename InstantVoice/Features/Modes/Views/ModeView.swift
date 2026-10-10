import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @EnvironmentObject private var navigation: MainWindowNavigation
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var pendingDeletion: ModeConfig?
    @State private var isShowingDefaultModeDeleteAlert = false
    @State private var isShowingNoTranscriptionModelAlert = false
    @State private var draggedModeID: UUID?

    var body: some View {
        Group {
            if modeManager.configurations.isEmpty {
                emptyState
            } else {
                modeList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createMode) {
                    Label("Add Mode", systemImage: "plus")
                }
                .help("Add a new mode")
            }
        }
        .confirmationDialog(
            "Delete Mode?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { config in
            Button("Delete", role: .destructive) {
                delete(config)
            }
            Button("Cancel", role: .cancel) {}
        } message: { config in
            Text(
                String(
                    format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                    config.name
                )
            )
        }
        .alert("Default Mode Can’t Be Deleted", isPresented: $isShowingDefaultModeDeleteAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("No Transcription Model", isPresented: $isShowingNoTranscriptionModelAlert) {
            Button("Open AI Models") {
                navigation.navigate(to: .models)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Download a local model or connect a cloud provider in AI Models before adding a mode.")
        }
        .onAppear(perform: configureWarmupStore)
    }

    private var modeList: some View {
        Form {
            Section {
                ForEach(modeManager.configurations) { config in
                    NavigationLink(value: MainWindowRoute.mode(config.id)) {
                        ModeListRow(config: config)
                    }
                    .onDrag {
                        draggedModeID = config.id
                        return NSItemProvider(object: config.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ModeReorderDropDelegate(
                            targetID: config.id,
                            modeManager: modeManager,
                            draggedModeID: $draggedModeID
                        )
                    )
                    .contextMenu {
                        Button("Move Up") {
                            move(config, by: -1)
                        }
                        .disabled(config.id == modeManager.configurations.first?.id)

                        Button("Move Down") {
                            move(config, by: 1)
                        }
                        .disabled(config.id == modeManager.configurations.last?.id)

                        Divider()

                        Button("Duplicate") {
                            if let duplicate = modeManager.duplicateConfiguration(with: config.id) {
                                navigation.push(.mode(duplicate.id))
                            }
                        }

                        Divider()

                        Button("Delete…", role: .destructive) {
                            if config.isDefault {
                                isShowingDefaultModeDeleteAlert = true
                            } else {
                                pendingDeletion = config
                            }
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modes help you set up InstantVoice for different writing tasks, workflows, and scenarios.")
                    Text("During recording, press Option + 1-9 to switch modes in the order listed. Drag modes to reorder them.")
                }
            }
        }
        .formStyle(.grouped)
        .onDrop(of: [UTType.text], delegate: ModeReorderEndDropDelegate(draggedModeID: $draggedModeID))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Create your first mode", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Set how InstantVoice transcribes and formats your speech, then start dictating in any app.")
        } actions: {
            Button("Add Mode", action: createMode)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func configureWarmupStore() {
        modeWarmupStore.configure(
            aiService: aiService,
            enhancementService: enhancementService,
            transcriptionModelManager: transcriptionModelManager
        )
    }

    /// Adds a mode with sensible defaults right away, then opens it, like the + button in System Settings.
    private func createMode() {
        configureWarmupStore()
        let snapshot = modeWarmupStore.snapshot

        var draft = ModeConfigDraft(mode: .add, modeManager: modeManager)
        draft.applyAddModeDefaults(snapshot: snapshot)
        draft.inheritUsableTranscriptionModelSelection(from: snapshot)
        draft.ensurePromptSelection(firstPromptId: snapshot.firstPromptId)
        guard let modelName = draft.selectedTranscriptionModelName else {
            // A mode can't record without a model, so explain where to get one instead of adding a broken mode.
            isShowingNoTranscriptionModelAlert = true
            return
        }
        if let model = snapshot.transcriptionModel(named: modelName) {
            draft.useCompatibleLanguage(for: model)
        }
        draft.name = uniqueModeName(String(localized: "New Mode"))

        let configuration = draft.makeConfig(mode: .add)
        modeManager.addConfiguration(configuration)
        ModeEditorFocus.requestNameFocus(for: configuration.id)
        navigation.push(.mode(configuration.id))
    }

    private func uniqueModeName(_ base: String) -> String {
        let names = Set(modeManager.configurations.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    private func move(_ config: ModeConfig, by offset: Int) {
        guard let index = modeManager.configurations.firstIndex(where: { $0.id == config.id }),
            modeManager.configurations.indices.contains(index + offset)
        else { return }

        withAnimation(.smooth(duration: 0.2)) {
            modeManager.moveConfigurations(
                fromOffsets: IndexSet(integer: index),
                toOffset: offset > 0 ? index + offset + 1 : index + offset
            )
        }
    }

    private func delete(_ config: ModeConfig) {
        if case .removed = modeManager.removeConfiguration(with: config.id) {
            navigation.removeFromHistory(.mode(config.id))
        }
        pendingDeletion = nil
    }
}

/// Moves the dragged mode into place as it passes over other rows.
private struct ModeReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let modeManager: ModeManager
    @Binding var draggedModeID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedModeID,
            draggedModeID != targetID,
            let fromIndex = modeManager.configurations.firstIndex(where: { $0.id == draggedModeID }),
            let toIndex = modeManager.configurations.firstIndex(where: { $0.id == targetID })
        else { return }

        withAnimation(.smooth(duration: 0.18)) {
            modeManager.moveConfigurations(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModeID = nil
        return true
    }
}

/// Ends a reorder dropped between rows or below the list.
private struct ModeReorderEndDropDelegate: DropDelegate {
    @Binding var draggedModeID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModeID = nil
        return true
    }
}

/// Lets a newly created mode open with its name field ready for typing.
enum ModeEditorFocus {
    private static var pendingModeID: UUID?

    static func requestNameFocus(for modeID: UUID) {
        pendingModeID = modeID
    }

    static func consumeNameFocusRequest(for modeID: UUID) -> Bool {
        guard pendingModeID == modeID else { return false }
        pendingModeID = nil
        return true
    }
}
