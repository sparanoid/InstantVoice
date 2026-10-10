import CoreGraphics

enum DashboardLayout {
    static let sectionSpacing: CGFloat = 22
    static let columnSpacing: CGFloat = 18
    static let pageHorizontalPadding: CGFloat = 24
    static let pageVerticalPadding: CGFloat = 28
    static let contentMaxWidth: CGFloat = 860
    static let cardCornerRadius: CGFloat = AppTheme.Radius.card

    /// The hero scrolls under the toolbar, so its copy starts below the toolbar's height.
    static let heroTopPadding: CGFloat = 96
    static let heroMinimumHeight: CGFloat = 320

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - (pageHorizontalPadding * 2))
    }
}
