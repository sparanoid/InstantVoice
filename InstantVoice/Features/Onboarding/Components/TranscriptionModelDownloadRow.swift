import SwiftUI

/// The local transcription model as a form row, with its download state on the trailing edge.
struct TranscriptionModelDownloadRow: View {
    let model: FluidAudioModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let status: FluidAudioDownloadStatus?
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image("nvidia-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 24)
                    .frame(width: 36, height: 36)
                    .accessibilityLabel(Text(verbatim: "NVIDIA"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium))

                    Text("Fast multilingual transcription that runs locally on Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(model.size)
                        Text(verbatim: "·")
                        Text("25+ languages")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                trailingControl
            }

            if let status, !isDownloaded {
                progress(status)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isDownloaded {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        } else if isDownloading {
            Button("Cancel", action: onCancel)
        } else {
            Button(
                status == nil ? LocalizedStringKey("Download Model") : LocalizedStringKey("Resume Download"),
                action: onDownload
            )
            .buttonStyle(.borderedProminent)
        }
    }

    private func progress(_ status: FluidAudioDownloadStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: status.fractionCompleted)
                    .progressViewStyle(.linear)
            }

            HStack {
                Text(status.message)
                    .lineLimit(1)

                Spacer()

                Text(status.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}
