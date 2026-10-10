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

struct ContentView: View {
    private let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "ContentView")
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: sidebarSelection)
                .navigationSplitViewColumnWidth(
                    min: AppWindowLayout.sidebarMinimumWidth,
                    ideal: AppWindowLayout.sidebarIdealWidth,
                    max: AppWindowLayout.sidebarMaximumWidth
                )
        } detail: {
            // One stack per section; its path comes from the window's back and forward history.
            NavigationStack(path: pathBinding) {
                detailView(for: navigation.selectedView)
                    .navigationTitle(navigation.selectedView.title)
                    .historyNavigationToolbar()
                    .navigationDestination(for: MainWindowRoute.self) { route in
                        MainWindowRouteView(route: route)
                            .navigationBarBackButtonHidden(true)
                            .historyNavigationToolbar()
                    }
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

    private var sidebarSelection: Binding<ViewType> {
        Binding(
            get: { navigation.selectedView },
            set: { navigation.navigate(to: $0) }
        )
    }

    private var pathBinding: Binding<[MainWindowRoute]> {
        Binding(
            get: { navigation.path },
            set: { navigation.updatePath($0) }
        )
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

private extension View {
    /// Each page declares the control itself, since a pushed page replaces the toolbar items above it.
    func historyNavigationToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .navigation) {
                HistoryNavigationButtons()
            }
        }
    }
}

/// The back and forward buttons that lead the toolbar, like System Settings.
private struct HistoryNavigationButtons: View {
    @EnvironmentObject private var navigation: MainWindowNavigation

    var body: some View {
        Button(action: navigation.goBack) {
            Label("Back", systemImage: "chevron.left")
        }
        .disabled(!navigation.canGoBack)
        .keyboardShortcut("[", modifiers: .command)
        .help("Show the previous page")

        Button(action: navigation.goForward) {
            Label("Forward", systemImage: "chevron.right")
        }
        .disabled(!navigation.canGoForward)
        .keyboardShortcut("]", modifiers: .command)
        .help("Show the next page")
    }
}
