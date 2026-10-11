import AppKit

/// Sizes toolbar search fields like Mail's: compact until focused, then wider, and collapsed into a button when the
/// toolbar runs out of room. SwiftUI's search item otherwise stretches across the free toolbar space, so it never
/// collapses while other items overflow.
@MainActor
enum ToolbarSearchFieldSizing {
    static let compactWidth: CGFloat = 170
    static let focusedWidth: CGFloat = 280

    private static let constraintIdentifier = "InstantVoice.compactToolbarSearchField"
    private static var observer: NSObjectProtocol?

    /// Sizes search items as SwiftUI adds them to any window's toolbar.
    static func install() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSToolbar.willAddItemNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let item = notification.userInfo?["item"] as? NSSearchToolbarItem else { return }
            // Runs after the toolbar adds the item and SwiftUI finishes configuring it.
            Task { @MainActor in
                apply(to: item)
            }
        }

        for window in NSApp.windows {
            for case let item as NSSearchToolbarItem in window.toolbar?.items ?? [] {
                apply(to: item)
            }
        }
    }

    private static func apply(to item: NSSearchToolbarItem) {
        // AppKit widens the field to this while it has keyboard focus.
        item.preferredWidthForSearchField = focusedWidth

        let field = item.searchField
        guard !field.constraints.contains(where: { $0.identifier == constraintIdentifier }) else { return }

        // A cap rather than a fixed width, so the toolbar can still shrink the field into its button. Its priority
        // beats the toolbar stretching the field but yields to the focused width.
        let cap = field.widthAnchor.constraint(lessThanOrEqualToConstant: compactWidth)
        cap.priority = NSLayoutConstraint.Priority(500)
        cap.identifier = constraintIdentifier
        cap.isActive = true
    }
}
