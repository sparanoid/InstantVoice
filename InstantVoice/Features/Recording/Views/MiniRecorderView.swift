import SwiftUI

/// A Liquid Glass capsule of recorder controls. Live text and assistant replies appear on a glass card above it, like
/// Siri's on iPhone, and the card morphs out of the capsule as it appears.
///
/// The recorder floats over whatever the user is working in, so both shapes use clear glass, which lets that content
/// show through, with a tint that keeps the controls legible. The card also darkens toward its top, behind the text,
/// and stays see-through toward its bottom edge.
struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    let audioMeterProvider: () -> AudioMeter
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var glassNamespace

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let controlBarWidth: CGFloat = 184
    private let transcriptWidth: CGFloat = 400
    private let assistantWidth: CGFloat = 520
    private let cardSpacing: CGFloat = 10
    private let cardCornerRadius: CGFloat = 22
    /// The strip of clear glass below the live text.
    private let transcriptLipHeight: CGFloat = 22

    /// Black in Dark Mode and white in Light Mode, for the glass tint and the card's dimming.
    private var shade: Color {
        colorScheme == .dark ? .black : .white
    }

    private var cardGlass: Glass {
        .clear.tint(shade.opacity(0.25))
    }

    private var controlBarGlass: Glass {
        .clear.tint(shade.opacity(0.4))
    }

    /// Darkens the card's glass toward the top, where the text starts, and leaves its bottom edge see-through.
    private var cardDimming: some View {
        LinearGradient(
            stops: [
                .init(color: shade.opacity(0.75), location: 0),
                .init(color: shade.opacity(0.45), location: 0.5),
                .init(color: shade.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(.rect(cornerRadius: cardCornerRadius))
    }

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTranscript
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var hasAssistantResponse: Bool {
        assistantSession.isVisible
    }

    private var shouldShowCloseButton: Bool {
        hasAssistantResponse && stateProvider.recordingState == .idle && !assistantSession.isBusy
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Group {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: stateProvider.recordingState,
                        action: onRecordButtonTapped
                    )
                }
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeterProvider: audioMeterProvider
            )

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(width: controlBarWidth, height: controlBarHeight)
    }

    var body: some View {
        GlassEffectContainer(spacing: cardSpacing) {
            VStack(spacing: cardSpacing) {
                if hasAssistantResponse {
                    AssistantPanelView(
                        session: assistantSession,
                        liveFollowUpText: liveAssistantFollowUpText,
                        onSend: onAssistantFollowUp
                    )
                    .frame(width: assistantWidth)
                    .background { cardDimming }
                    .glassEffect(cardGlass, in: .rect(cornerRadius: cardCornerRadius))
                    .glassEffectID("card", in: glassNamespace)
                } else if hasLiveTranscript {
                    LiveTranscriptCard(text: stateProvider.partialTranscript)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, transcriptLipHeight)
                        .frame(width: transcriptWidth)
                        .background { cardDimming }
                        .glassEffect(cardGlass, in: .rect(cornerRadius: cardCornerRadius))
                        .glassEffectID("card", in: glassNamespace)
                }

                controlBar
                    .glassEffect(controlBarGlass, in: .capsule)
                    .glassEffectID("controls", in: glassNamespace)
            }
        }
        .environment(\.recorderSurfaceStyle, .glass)
        .animation(.smooth(duration: 0.3), value: hasLiveTranscript)
        .animation(.smooth(duration: 0.3), value: hasAssistantResponse)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// The live transcript, grown to three lines at most. The newest words stay at the bottom; once the text outgrows the
/// card, its start slides out under a fade at the top.
private struct LiveTranscriptCard: View {
    let text: String

    /// The height of the transcript cut to `maxLines`, or nil before the first layout.
    @State private var visibleHeight: CGFloat?
    @State private var textHeight: CGFloat = 0

    private let maxLines = 3

    private var isOverflowing: Bool {
        guard let visibleHeight else { return false }
        return textHeight > visibleHeight + 0.5
    }

    private var transcript: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        transcript
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            .frame(height: visibleHeight, alignment: .bottom)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: isOverflowing ? .clear : .black, location: 0),
                        .init(color: .black, location: isOverflowing ? 0.3 : 0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .background {
                // Measures the card's height with the same text layout, cut to the last line that fits.
                transcript
                    .lineLimit(maxLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        // Animating the height grows the card's glass along with it.
                        withAnimation(.smooth(duration: 0.2)) {
                            visibleHeight = height
                        }
                    }
            }
    }
}
