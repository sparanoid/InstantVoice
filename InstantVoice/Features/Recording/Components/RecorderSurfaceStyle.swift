import SwiftUI

/// The surface recorder controls sit on: the notch recorder's solid black, which blends into the display's notch, or
/// the mini recorder's Liquid Glass, which follows Light and Dark Mode.
enum RecorderSurfaceStyle {
    case solid
    case glass

    /// The color of text and marks. Translucent fills use it at a low opacity.
    var ink: Color {
        switch self {
        case .solid: .white
        case .glass: .primary
        }
    }
}

extension EnvironmentValues {
    @Entry var recorderSurfaceStyle: RecorderSurfaceStyle = .solid
}
