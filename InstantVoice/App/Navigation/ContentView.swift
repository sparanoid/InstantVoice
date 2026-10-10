import OSLog
import SwiftUI

enum ViewType: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case modes = "Modes"
    case models = "AI Models"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case audio = "Audio"
    case dictionary = "Dictionary"
    case settings = "Settings"

    var id: String { rawValue }
}

final class MainWindowNavigation: ObservableObject {
    static let shared = MainWindowNavigation()

    @Published var selectedView: ViewType = .dashboard

    private init() {}

    func navigate(to destination: String) {
        guard let viewType = ViewType(rawValue: destination) else {
            return
        }

        navigate(to: viewType)
    }

    func navigate(to destination: ViewType) {
        selectedView = destination
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "ContentView")
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $navigation.selectedView)
                .navigationSplitViewColumnWidth(
                    min: AppWindowLayout.sidebarMinimumWidth,
                    ideal: AppWindowLayout.sidebarIdealWidth,
                    max: AppWindowLayout.sidebarMaximumWidth
                )
        } detail: {
            // A fresh stack per destination resets any drill-down when switching sections.
            NavigationStack {
                detailView(for: navigation.selectedView)
                    .navigationTitle(navigation.selectedView.title)
            }
            .id(navigation.selectedView)
        }
        .frame(minWidth: AppWindowLayout.minimumWidth, minHeight: AppWindowLayout.minimumHeight)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                navigation.navigate(to: destination)
            }
        }
    }

    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .dashboard:
            DashboardView()
        case .models:
            ModelManagementView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            HistoryView()
        case .audio:
            AudioSetupView()
        case .dictionary:
            DictionarySettingsView()
        case .modes:
            ModeView()
        case .settings:
            SettingsView()
        }
    }
}
