import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AudioTranscribeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: InstantVoiceEngine
    @ObservedObject private var modeManager = ModeManager.shared
    @StateObject private var transcriptionManager = AudioTranscriptionManager.shared
    @State private var isDropTargeted = false
    @State private var expandedItemId: UUID?

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    var body: some View {
        Group {
            if transcriptionManager.queue.isEmpty {
                emptyStateView
            } else {
                queueFormView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationSubtitle(queueSubtitle)
        .toolbar {
            if !transcriptionManager.queue.isEmpty {
                queueToolbar
            }
        }
        .onDrop(of: [.fileURL, .data, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
            return true
        }
        .overlay {
            if isDropTargeted && !transcriptionManager.queue.isEmpty {
                dropOverlay
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileForTranscription)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                transcriptionManager.addToQueue(urls: [url])
            }
        }
        .onChange(of: transcriptionManager.lastCompletedItemId) { _, newId in
            if let newId {
                withAnimation(.easeInOut(duration: 0.3)) {
                    expandedItemId = newId
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label {
                    Text("Drop audio or video files here")
                } icon: {
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "waveform.badge.plus")
                        .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
            } description: {
                Text("Supports WAV, MP3, M4A, AIFF, MP4, MOV, AAC, FLAC, CAF, AMR, OGG, OPUS, 3GP")
            } actions: {
                Button("Choose Files") {
                    selectFiles()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 520, maxHeight: 320)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isDropTargeted ? AnyShapeStyle(AppTheme.Accent.fillSubtle) : AnyShapeStyle(AppTheme.Surface.card))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                        )
                }
        }
        .animation(.smooth(duration: 0.2), value: isDropTargeted)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Queue Form View

    private var queueFormView: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(transcriptionManager.queue) { item in
                    Section {
                        AudioFileRow(
                            item: item,
                            isExpanded: expandedItemId == item.id,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedItemId = expandedItemId == item.id ? nil : item.id
                                }
                            },
                            onRemove: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    transcriptionManager.removeFromQueue(id: item.id)
                                    if expandedItemId == item.id { expandedItemId = nil }
                                }
                            },
                            onRetry: {
                                transcriptionManager.retryItem(id: item.id)
                                startProcessing()
                            }
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                Text("Drop files anywhere to add more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Toolbar

    private var queueSubtitle: Text {
        let count = transcriptionManager.queue.count
        return count == 0 ? Text(verbatim: "") : Text(String(localized: "\(count) files"))
    }

    @ToolbarContentBuilder
    private var queueToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                selectFiles()
            } label: {
                Label("Add files", systemImage: "plus")
            }
            .help("Add files")

            modePicker

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    transcriptionManager.clearAll()
                    expandedItemId = nil
                }
            } label: {
                Label("Clear", systemImage: "xmark.bin")
            }
            .help("Clear all items")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            if transcriptionManager.isProcessingQueue {
                Button(role: .cancel) {
                    transcriptionManager.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .help("Cancel transcription")
            } else {
                Button {
                    startProcessing()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .disabled(selectedMode == nil || !transcriptionManager.hasPendingItems)
                .help(selectedMode == nil ? "Select an enabled mode to start" : "Start transcription")
            }
        }
    }

    private var modePicker: some View {
        Menu {
            if modeManager.enabledConfigurations.isEmpty {
                Text("No modes available")
            } else {
                Picker("Mode", selection: modeSelection) {
                    ForEach(modeManager.enabledConfigurations) { mode in
                        Text(mode.name)
                            .tag(Optional(mode.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Label {
                Text(selectedMode?.name ?? String(localized: "None"))
            } icon: {
                if let selectedMode, selectedMode.icon.kind == .symbol {
                    Image(systemName: selectedMode.icon.value)
                } else {
                    Image(systemName: "sparkles.rectangle.stack")
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .help("Mode")
    }

    private var modeSelection: Binding<UUID?> {
        Binding(
            get: { selectedMode?.id },
            set: { id in
                guard let id, let mode = modeManager.enabledConfigurations.first(where: { $0.id == id }) else {
                    return
                }
                selectMode(mode)
            }
        )
    }

    private func selectMode(_ mode: ModeConfig) {
        modeManager.setActiveConfiguration(mode)
    }

    private func startProcessing() {
        guard let selectedMode else { return }
        transcriptionManager.startProcessing(modelContext: modelContext, engine: engine, mode: selectedMode)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(AppTheme.Accent.primary, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.Accent.fillSubtle)
            )
            .overlay {
                Text("Drop to add files")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.Accent.primary)
            }
            .padding(16)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    // MARK: - File Handling

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK {
            transcriptionManager.addToQueue(urls: panel.urls)
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        let typeIdentifiers = [
            UTType.fileURL.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.data.identifier,
            "public.file-url",
        ]

        for provider in providers {
            for typeIdentifier in typeIdentifiers {
                if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                        if let error = error {
                            print("Error loading dropped file: \(error)")
                            return
                        }

                        var fileURL: URL?

                        if let url = item as? URL {
                            fileURL = url
                        } else if let data = item as? Data {
                            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                                fileURL = url
                            } else if let urlString = String(data: data, encoding: .utf8),
                                let url = URL(string: urlString)
                            {
                                fileURL = url
                            }
                        } else if let urlString = item as? String {
                            fileURL = URL(string: urlString)
                        }

                        if let finalURL = fileURL {
                            DispatchQueue.main.async {
                                self.transcriptionManager.addToQueue(urls: [finalURL])
                            }
                        }
                    }
                    break
                }
            }
        }
    }
}
