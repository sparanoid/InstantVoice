import AppKit
import SwiftUI

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(CustomPrompt)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case (.edit(let prompt1), .edit(let prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }

    let mode: Mode
    @EnvironmentObject private var enhancementService: AIEnhancementService
    let onDismiss: () -> Void
    let onSave: (CustomPrompt) -> Void
    let onDelete: ((CustomPrompt) -> Void)?
    @State private var title: String
    @State private var promptText: String
    @State private var useSystemInstructions: Bool
    @State private var showDeleteConfirmation = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isDeleted = false

    private var editingPrompt: CustomPrompt? {
        if case .edit(let prompt) = mode {
            return prompt
        }
        return nil
    }

    private var canDeletePrompt: Bool {
        editingPrompt != nil && onDelete != nil
    }

    private var isSaveDisabled: Bool {
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        mode: Mode,
        onDismiss: @escaping () -> Void,
        onSave: @escaping (CustomPrompt) -> Void,
        onDelete: ((CustomPrompt) -> Void)? = nil
    ) {
        self.mode = mode
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _promptText = State(initialValue: "")
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _useSystemInstructions = State(initialValue: prompt.useSystemInstructions)
        }
    }

    private func dismissPanel() {
        onDismiss()
    }

    var body: some View {
        Form {
            Section {
                TextField("Prompt name", text: $title, prompt: Text("Prompt name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(.title3.weight(.semibold))

                if case .add = mode {
                    templateMenu
                }
            }

            Section("Instructions") {
                instructionsEditor
            }

            Section {
                systemTemplateToggle
            } footer: {
                if canDeletePrompt {
                    HStack {
                        Spacer()
                        Button("Delete Prompt…", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(navigationTitle)
        .toolbar {
            if case .add = mode {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create Prompt") {
                        if let savedPrompt = save() {
                            onSave(savedPrompt)
                        }
                        dismissPanel()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaveDisabled)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Save this prompt and use it in this mode.")
                }
            }
        }
        .onChange(of: title) { _, _ in scheduleLiveSave() }
        .onChange(of: promptText) { _, _ in scheduleLiveSave() }
        .onChange(of: useSystemInstructions) { _, _ in scheduleLiveSave() }
        .onDisappear(perform: saveEditsNow)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveEditsNow()
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePrompt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."),
                    title))
        }
    }

    private var navigationTitle: Text {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .add = mode, trimmedTitle.isEmpty {
            return Text("New Prompt")
        }
        return Text(verbatim: trimmedTitle.isEmpty ? (editingPrompt?.title ?? "") : trimmedTitle)
    }

    /// Existing prompts save as you edit, once both the name and instructions are filled in.
    private func scheduleLiveSave() {
        guard editingPrompt != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveEditsNow()
        }
    }

    private func saveEditsNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let prompt = editingPrompt, !isDeleted, !isSaveDisabled else { return }
        guard prompt.title != title || prompt.promptText != promptText
            || prompt.useSystemInstructions != useSystemInstructions
        else { return }
        _ = save()
    }

    private var systemTemplateToggle: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $useSystemInstructions) {
                HStack(spacing: 4) {
                    Text("Use System Template")
                    InfoTip(
                        "If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users)."
                    )
                }
            }
            .toggleStyle(.switch)

            Spacer(minLength: 12)
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(PromptTemplates.all) { template in
                Button {
                    title = template.title
                    promptText = template.promptText
                    useSystemInstructions = template.useSystemInstructions
                } label: {
                    Text(template.title)
                }
            }
        } label: {
            Label("Start from a Template", systemImage: "sparkles")
        }
        .help("Start with a template")
    }

    private var instructionsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $promptText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)

            if promptText.isEmpty {
                Text("Write prompt instructions")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func deletePrompt() {
        guard let prompt = editingPrompt, canDeletePrompt else { return }
        saveTask?.cancel()
        saveTask = nil
        isDeleted = true
        onDelete?(prompt)
        dismissPanel()
    }

    private func save() -> CustomPrompt? {
        switch mode {
        case .add:
            return enhancementService.addPrompt(
                title: title,
                promptText: promptText,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: title,
                promptText: promptText,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
            return updatedPrompt
        }
    }
}

/// The prompt editor opened from a mode's AI Enhancement settings. Creating a prompt selects it for that mode.
struct PromptEditorPage: View {
    let modeID: UUID
    let promptID: UUID?

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var navigation: MainWindowNavigation
    @ObservedObject private var modeManager = ModeManager.shared

    private var route: MainWindowRoute {
        .prompt(modeID: modeID, promptID: promptID)
    }

    var body: some View {
        if let promptID {
            if let prompt = enhancementService.allPrompts.first(where: { $0.id == promptID }) {
                PromptEditorView(
                    mode: .edit(prompt),
                    onDismiss: { navigation.dismissPage(route) },
                    onSave: selectForMode,
                    onDelete: delete
                )
            } else {
                ContentUnavailableView {
                    Label("Prompt Not Found", systemImage: "text.badge.xmark")
                } description: {
                    Text("This prompt was deleted.")
                }
            }
        } else {
            PromptEditorView(
                mode: .add,
                onDismiss: { navigation.dismissPage(route) },
                onSave: selectForMode
            )
        }
    }

    private func selectForMode(_ prompt: CustomPrompt) {
        guard var config = modeManager.getConfiguration(with: modeID) else { return }
        config.selectedPrompt = prompt.id.uuidString
        modeManager.updateConfiguration(config)
    }

    private func delete(_ prompt: CustomPrompt) {
        enhancementService.deletePrompt(prompt)
        if var config = modeManager.getConfiguration(with: modeID), config.selectedPrompt == prompt.id.uuidString {
            config.selectedPrompt = enhancementService.allPrompts.first?.id.uuidString
            modeManager.updateConfiguration(config)
        }
    }
}
