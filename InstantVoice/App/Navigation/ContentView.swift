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
    /// The sidebar's copy of the selected section. Its list reports clicks while SwiftUI is still updating views,
    /// where publishing into `navigation` isn't allowed, so the two sync through `onChange` instead.
    @State private var sidebarSelection = MainWindowNavigation.shared.selectedView

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $sidebarSelection)
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
        // Not a minimum frame: that replaces a page's own larger minimum, so a narrow window clipped History with its
        // inspector open, and it could send the split view into a crashing layout loop.
        .minimumSizeFloor(width: AppWindowLayout.minimumWidth, height: AppWindowLayout.minimumHeight)
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
        .onChange(of: sidebarSelection) { _, section in
            // Skips the echo of navigation's own changes, which would reset a pushed page to its section's top.
            if section != navigation.selectedView {
                navigation.navigate(to: section)
            }
        }
        .onChange(of: navigation.selectedView) { _, section in
            sidebarSelection = section
        }
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
    /// Keeps the window at least this size while still honoring a page that needs more.
    func minimumSizeFloor(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.clear
                .frame(minWidth: width, minHeight: height)

            self
        }
    }

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
