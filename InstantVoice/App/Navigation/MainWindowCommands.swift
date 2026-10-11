import SwiftUI

/// App and View menu commands for the main window: Settings (⌘,), one item per sidebar section (⌘1–⌘7),
/// and the standard sidebar and inspector toggles.
struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let navigation: MainWindowNavigation
    let menuBarManager: MenuBarManager
    let isEnabled: Bool

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                show(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!isEnabled)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(Self.shortcutItems.enumerated()), id: \.element) { index, item in
                Button(item.title) {
                    show(item)
                }
                .keyboardShortcut(Self.numberShortcut(for: index))
                .disabled(!isEnabled)
            }

            Divider()
        }
    }

    /// Settings already owns ⌘, so it stays out of the numbered list.
    private static let shortcutItems = ViewType.sidebarOrder.filter { $0 != .settings }

    private static func numberShortcut(for index: Int) -> KeyboardShortcut? {
        guard index < 9 else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
    }

    private func show(_ destination: ViewType) {
        navigation.navigate(to: destination)
        menuBarManager.activateForPresentedWindow()

        if WindowManager.shared.currentMainWindow() == nil {
            WindowManager.shared.prepareForUserRequestedMainWindow()
            openWindow(id: AppWindowID.main)
        } else {
            openWindow(id: AppWindowID.main)
            WindowManager.shared.showMainWindow()
        }
    }
}
