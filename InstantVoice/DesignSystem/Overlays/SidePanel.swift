import SwiftUI

enum SidePanelMetrics {
    /// Matches the floating inset of the macOS sidebar so both panes read as one family.
    static let inset: CGFloat = 8
    static let cornerRadius: CGFloat = 20
}

/// Presents a trailing pane that floats over the screen on Liquid Glass, like an inspector.
struct SidePanel<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    let dismissOnExitCommand: Bool
    @ViewBuilder let panelContent: () -> PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private func dismissPanel() {
        isPresented = false
    }

    private var dismissLayer: some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissPanel)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SidePanelMetrics.cornerRadius, style: .continuous)
    }

    /// Takes the requested width, shrinking only when the window is too narrow to fit it.
    private var panelSurface: some View {
        panelContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SidePanelBackground())
            .clipShape(panelShape)
            .glassEffect(.regular, in: panelShape)
            .padding(SidePanelMetrics.inset)
            .frame(maxWidth: panelWidth + SidePanelMetrics.inset * 2)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content

            if isPresented {
                dismissLayer

                Group {
                    if dismissOnExitCommand {
                        panelSurface
                            .onExitCommand(perform: dismissPanel)
                    } else {
                        panelSurface
                    }
                }
                .transition(transition)
                .zIndex(1)
            }
        }
        .animation(animation, value: isPresented)
    }
}

/// A translucent backing that keeps dense panel content legible on top of the glass.
struct SidePanelBackground: View {
    var body: some View {
        AppTheme.Surface.sidePanelOverlay
    }
}

extension View {
    func sidePanel<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 400,
        dismissOnExitCommand: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            SidePanel(
                isPresented: isPresented,
                panelWidth: width,
                dismissOnExitCommand: dismissOnExitCommand,
                panelContent: content
            ))
    }
}
