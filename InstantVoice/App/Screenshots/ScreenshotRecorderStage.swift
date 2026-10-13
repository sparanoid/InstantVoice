#if DEBUG
    import AppKit
    import ImageIO
    import SwiftUI

    /// The mini recorder over a wallpaper, for recorder scenes. The real recorder floats in a transparent panel, but a
    /// window capture leaves out whatever lies behind a window, Liquid Glass included. So the stage draws a wallpaper
    /// and the recorder in one window, where the glass picks up the wallpaper as it would the desktop. The stage is an
    /// `ActiveGlassPanel` like the real recorder, so its glass draws in the same style.
    enum ScreenshotRecorderStage {
        static let size = NSSize(width: 760, height: 460)

        @MainActor
        static func makeWindow(for scene: ScreenshotScene, on screen: NSScreen?) -> NSWindow {
            let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
            let window = ActiveGlassPanel(
                contentRect: NSRect(
                    x: (visibleFrame.midX - size.width / 2).rounded(),
                    y: (visibleFrame.midY - size.height / 2).rounded(),
                    width: size.width,
                    height: size.height
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            // Wherever the pointer rests, it must not leave hover highlights in the capture.
            window.ignoresMouseEvents = true
            // The wallpaper follows the app's appearance, like the desktop; the recorder takes its own setting, like the
            // real panel.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            window.appearance = MiniRecorderAppearance.stored.appKitAppearance
            window.contentView = NSHostingView(
                rootView: ScreenshotRecorderStageView(scene: scene, wallpaper: wallpaper(isDark: isDark)))
            window.orderFront(nil)
            return window
        }

        /// A wallpaper that ships with macOS, scaled down. Nil when this macOS no longer has it.
        private static func wallpaper(isDark: Bool) -> NSImage? {
            let name = isDark ? "Radial Sky Blue" : "Mac Blue"
            let url = URL(fileURLWithPath: "/System/Library/Desktop Pictures/\(name).heic")
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return NSImage(cgImage: image, size: .zero)
        }
    }

    private struct ScreenshotRecorderStageView: View {
        let wallpaper: NSImage?
        @StateObject private var state: ScreenshotRecorderState
        @StateObject private var assistantSession: AssistantSession

        init(scene: ScreenshotScene, wallpaper: NSImage?) {
            self.wallpaper = wallpaper
            let content = ScreenshotDemoData.recorderContent(for: scene)
            _state = StateObject(
                wrappedValue: ScreenshotRecorderState(
                    recordingState: content.recordingState, partialTranscript: content.partialTranscript))
            _assistantSession = StateObject(wrappedValue: ScreenshotDemoData.assistantSession(for: scene))
        }

        var body: some View {
            ZStack(alignment: .bottom) {
                background

                MiniRecorderView(
                    stateProvider: state,
                    audioMeterProvider: { ScreenshotDemoData.recorderAudioMeter },
                    assistantSession: assistantSession,
                    onRecordButtonTapped: {},
                    onCloseTapped: {},
                    onAssistantFollowUp: { _ in }
                )
                // The recorder panel, at its distance from the bottom of the screen.
                .frame(width: MiniRecorderPanel.size.width, height: MiniRecorderPanel.size.height)
                .padding(.bottom, MiniRecorderPanel.bottomPadding)
            }
            .frame(width: ScreenshotRecorderStage.size.width, height: ScreenshotRecorderStage.size.height)
        }

        @ViewBuilder
        private var background: some View {
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ScreenshotRecorderStage.size.width, height: ScreenshotRecorderStage.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.56, green: 0.36, blue: 0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    @MainActor
    private final class ScreenshotRecorderState: ObservableObject, RecorderStateProvider {
        @Published var recordingState: RecordingState
        @Published var partialTranscript: String

        init(recordingState: RecordingState, partialTranscript: String) {
            self.recordingState = recordingState
            self.partialTranscript = partialTranscript
        }
    }
#endif
