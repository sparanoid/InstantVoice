import SwiftUI

struct HistoryAudioPlayer: View {
    let url: URL
    @StateObject private var player = AudioPlayerManager()
    @Environment(\.historyControlStyle) private var style

    private var playbackRateLabel: String {
        player.playbackRate == 1.0 ? "1×" : player.playbackRate == 1.5 ? "1.5×" : "2×"
    }

    private var playbackPositionValue: String {
        String(
            format: String(localized: "%@ of %@"),
            formattedTime(player.currentTime),
            formattedTime(player.duration)
        )
    }

    var body: some View {
        switch style {
        case .panel:
            panelPlayer
        case .glass:
            glassPlayer
        }
    }

    /// A single glass capsule; its buttons stay borderless so glass is never stacked on glass.
    private var glassPlayer: some View {
        HStack(spacing: 10) {
            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            playbackTime(player.currentTime)

            waveform

            playbackTime(player.duration)

            Button(action: player.cyclePlaybackRate) {
                Text(playbackRateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 30)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(player.playbackRate == 1.0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .help("Playback speed")
            .accessibilityLabel("Playback speed")
            .accessibilityValue(Text(playbackRateLabel))
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .onAppear { player.loadAudio(from: url) }
        .onDisappear { player.cleanup() }
    }

    private var waveform: some View {
        WaveformView(
            samples: player.waveformSamples,
            currentTime: player.currentTime,
            duration: player.duration,
            isLoading: player.isLoadingWaveform,
            onSeek: { player.seek(to: $0) }
        )
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(playbackPositionValue))
        .accessibilityAdjustableAction { direction in
            guard !player.isLoadingWaveform, player.duration > 0 else { return }

            let offset: TimeInterval
            switch direction {
            case .increment: offset = 5
            case .decrement: offset = -5
            @unknown default: return
            }
            player.seek(to: min(max(player.currentTime + offset, 0), player.duration))
        }
    }

    private var panelPlayer: some View {
        HStack(spacing: 10) {
            HistoryIconButton(
                systemName: player.isPlaying ? "pause.fill" : "play.fill",
                help: player.isPlaying ? "Pause" : "Play"
            ) {
                player.isPlaying ? player.pause() : player.play()
            }

            playbackTime(player.currentTime)

            waveform

            playbackTime(player.duration)

            Button(action: player.cyclePlaybackRate) {
                Text(playbackRateLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .frame(width: 34, height: HistoryLayout.buttonHeight)
                    .background(QuickPanelButtonBackground(isSelected: player.playbackRate != 1.0))
            }
            .buttonStyle(.plain)
            .help("Playback speed")
            .accessibilityLabel("Playback speed")
            .accessibilityValue(Text(playbackRateLabel))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: HistoryLayout.playerHeight)
        .background(DashboardInsightRowBackground())
        .onAppear { player.loadAudio(from: url) }
        .onDisappear { player.cleanup() }
    }

    private func playbackTime(_ time: TimeInterval) -> some View {
        Text(formattedTime(time))
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(AppTheme.Text.secondary)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
