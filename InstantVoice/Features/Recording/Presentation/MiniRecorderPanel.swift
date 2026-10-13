import AppKit
import os

/// A panel whose Liquid Glass keeps its active look while InstantVoice is in the background.
///
/// macOS draws glass in an inactive window as a flat, frosted fallback. The recorder never becomes key, so that typing
/// and pasting keep going to the app being dictated into, and InstantVoice stays in the background, so its panel would
/// always get that fallback. AppKit has no public switch for it; answering this private query only changes how the
/// panel draws. If a later macOS stops asking, the panel falls back to the frosted look.
class ActiveGlassPanel: NSPanel {
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func hasActiveAppearanceIgnoringKeyFocus() -> Bool {
        true
    }
}

final class MiniRecorderPanel: ActiveGlassPanel {
    override var canBecomeKey: Bool { true }

    private let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "MiniRecorderPanel")

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        isFloatingPanel = true
        canHide = false
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
    }

    /// Host stays large enough for assistant output; SwiftUI controls the visible mini width.
    static let size = NSSize(width: 540, height: 430)

    /// The gap between the panel and the bottom of the screen's visible area.
    static let bottomPadding: CGFloat = 24

    /// Returns `nil` when there is no screen at all, so callers can skip showing the panel
    /// instead of placing it at the global origin.
    static func calculateWindowMetrics() -> NSRect? {
        guard let screen = RecorderScreenResolver.resolve() else { return nil }

        let visibleFrame = screen.visibleFrame
        let centerX = visibleFrame.midX
        let xPosition = centerX - (size.width / 2)
        let yPosition = visibleFrame.minY + bottomPadding

        return NSRect(
            x: xPosition,
            y: yPosition,
            width: size.width,
            height: size.height
        )
    }

    @discardableResult
    func show() -> Bool {
        guard let metrics = MiniRecorderPanel.calculateWindowMetrics() else {
            logger.error("Mini panel show skipped: no screen available")
            return false
        }

        setFrame(metrics, display: true)
        orderFrontRegardless()

        logger.notice(
            "Mini panel frame=\(NSStringFromRect(self.frame), privacy: .public) screens=\(NSScreen.screens.count, privacy: .public) onActiveSpace=\(self.isOnActiveSpace, privacy: .public)"
        )
        return true
    }

    deinit {
        logger.debug("Mini panel deallocated")
    }
}
