import SwiftUI

struct AppSidebar: View {
    @Binding var selection: ViewType
    @ObservedObject private var transcriptionQueue = AudioTranscriptionManager.shared

    var body: some View {
        List(selection: listSelection) {
            Section {
                ForEach(ViewType.workspaceItems) { item in
                    row(for: item)
                }
            }

            Section("Configuration") {
                ForEach(ViewType.configurationItems) { item in
                    row(for: item)
                }
            }

            Section {
                ForEach(ViewType.appItems) { item in
                    row(for: item)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            ViewType.assertSidebarItemsCoverAllCases()
        }
    }

    private var listSelection: Binding<ViewType?> {
        Binding(
            get: { selection },
            set: { newValue in
                // A section is always selected. Reassigning on nil (for example after a Command-click on
                // the selected row) republishes it so the list restores the highlight.
                selection = newValue ?? selection
            }
        )
    }

    private func row(for item: ViewType) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(badgeCount(for: item))
            .tag(item)
    }

    /// Transcribe queue files that haven't finished, shown like an unread count. The manager republishes
    /// as each file completes and when processing stops, which keeps the count current.
    private func badgeCount(for item: ViewType) -> Int {
        guard item == .transcribeAudio else { return 0 }
        return transcriptionQueue.queue.filter { $0.status != .completed }.count
    }
}

extension ViewType {
    var title: LocalizedStringKey {
        switch self {
        case .transcribeAudio:
            return "Transcribe"
        default:
            return LocalizedStringKey(rawValue)
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .transcribeAudio: return "waveform"
        case .history: return "clock.arrow.circlepath"
        case .modes: return "sparkles.rectangle.stack"
        case .dictionary: return "character.book.closed"
        case .models: return "cpu"
        case .audio: return "mic"
        case .settings: return "gearshape"
        }
    }

    static let workspaceItems: [ViewType] = [
        .dashboard,
        .transcribeAudio,
        .history,
    ]

    static let configurationItems: [ViewType] = [
        .modes,
        .dictionary,
        .models,
        .audio,
    ]

    static let appItems: [ViewType] = [
        .settings
    ]

    /// Sidebar order, which also defines the Command-number shortcuts in the View menu.
    static let sidebarOrder: [ViewType] = workspaceItems + configurationItems + appItems

    static func assertSidebarItemsCoverAllCases() {
        #if DEBUG
            assert(Set(sidebarOrder) == Set(allCases) && sidebarOrder.count == allCases.count)
        #endif
    }
}
