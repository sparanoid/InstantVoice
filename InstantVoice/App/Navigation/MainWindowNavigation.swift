import Foundation

/// A page pushed inside a main-window section, in the style of System Settings drill-downs.
enum MainWindowRoute: Hashable {
    case mode(UUID)
    case prompt(modeID: UUID, promptID: UUID?)
    case cloudProvider(String)
    case customTranscriptionModel(UUID?)
    case customEnhancementModel(UUID?)
    case modelSettings
    case dictionarySettings
    case autoLearnReview
    case autoLearnFailure
    case historySettings
    case historyAnalysis([UUID])
    case insights
    case modelUsage(DashboardInsightPeriod)
    case modelPerformance(DashboardInsightPeriod)
}

/// Where the main window is: a sidebar section plus the pages pushed inside it.
struct MainWindowLocation: Equatable {
    var section: ViewType
    var path: [MainWindowRoute]
}

/// Drives main-window navigation with browser-style back and forward history across sections and pages,
/// like System Settings.
final class MainWindowNavigation: ObservableObject {
    static let shared = MainWindowNavigation()

    @Published private(set) var selectedView: ViewType = .dashboard
    @Published private(set) var path: [MainWindowRoute] = []
    @Published private var backStack: [MainWindowLocation] = []
    @Published private var forwardStack: [MainWindowLocation] = []

    private static let historyLimit = 50

    private init() {}

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    private var location: MainWindowLocation {
        MainWindowLocation(section: selectedView, path: path)
    }

    func navigate(to destination: String) {
        guard let viewType = ViewType(rawValue: destination) else {
            return
        }

        navigate(to: viewType)
    }

    /// Shows a section's top page. Choosing the current section again returns to its top page.
    func navigate(to destination: ViewType) {
        visit(MainWindowLocation(section: destination, path: []))
    }

    func push(_ route: MainWindowRoute) {
        visit(MainWindowLocation(section: selectedView, path: path + [route]))
    }

    /// Records path changes made by the navigation stack itself, such as a `NavigationLink` push.
    func updatePath(_ newPath: [MainWindowRoute]) {
        visit(MainWindowLocation(section: selectedView, path: newPath))
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        apply(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        apply(next)
    }

    /// Leaves a page whose content no longer exists, such as a deleted mode, and forgets it in history.
    func dismissPage(_ route: MainWindowRoute) {
        if let index = path.firstIndex(of: route) {
            apply(MainWindowLocation(section: selectedView, path: Array(path[..<index])))
        }
        removeFromHistory(route)
    }

    /// Drops history entries that lead to a page, so back and forward never land on a removed item.
    func removeFromHistory(_ route: MainWindowRoute) {
        backStack = Self.collapsed(backStack.filter { !$0.path.contains(route) })
        forwardStack = Self.collapsed(forwardStack.filter { !$0.path.contains(route) })
        // Pruning can leave the current location as the next step, which would make Back or Forward do nothing.
        while backStack.last == location {
            backStack.removeLast()
        }
        while forwardStack.last == location {
            forwardStack.removeLast()
        }
    }

    private func visit(_ target: MainWindowLocation) {
        guard target != location else { return }
        backStack.append(location)
        if backStack.count > Self.historyLimit {
            backStack.removeFirst(backStack.count - Self.historyLimit)
        }
        forwardStack.removeAll()
        apply(target)
    }

    private func apply(_ target: MainWindowLocation) {
        if selectedView != target.section {
            selectedView = target.section
        }
        if path != target.path {
            path = target.path
        }
    }

    /// Removes adjacent duplicates left behind after pruning entries.
    private static func collapsed(_ locations: [MainWindowLocation]) -> [MainWindowLocation] {
        locations.reduce(into: []) { result, location in
            if result.last != location {
                result.append(location)
            }
        }
    }
}
