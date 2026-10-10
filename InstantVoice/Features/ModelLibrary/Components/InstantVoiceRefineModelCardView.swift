import AppKit
import SwiftUI

struct InstantVoiceRefineModelCardView: View {
    @ObservedObject var service: InstantVoiceRefineService
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
                progressSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(AppMaterialCardBackground())
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(InstantVoiceRefineService.modelName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.labelColor))

            Text("New")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(red: 0.96, green: 0.79, blue: 0.63)))

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label("Enhancement Model", systemImage: "sparkles")
            Label("On-Device", systemImage: "checkmark.shield")
            Label {
                Text(verbatim: InstantVoiceRefineService.downloadSizeDescription)
            } icon: {
                Image(systemName: "internaldrive")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cleans up raw transcripts. Processing stays on your Mac.")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let unavailableDescription = service.unavailableDescription {
                Text(unavailableDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Status.warningStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var progressSection: some View {
        if service.isDownloading {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(downloadDetail)
                        .lineLimit(1)

                    Spacer()

                    Text(
                        service.downloadProgress,
                        format: .percent.precision(.fractionLength(0))
                    )
                    .fontDesign(.monospaced)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

                ProgressView(value: service.downloadProgress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Model download progress")
                    .accessibilityValue(Text(verbatim: downloadAccessibilityValue))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }

        if let downloadError = service.downloadError {
            Text(downloadError)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Status.error)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            switch service.availability {
            case .unsupportedIntel, .insufficientMemory:
                modelStatusPill("Unavailable", systemImage: "exclamationmark.triangle")
            case .available:
                if service.isDownloading {
                    ModelDownloadButton(isDownloading: true) {
                        service.cancelDownload()
                    }
                } else if service.isDownloaded {
                    modelStatusPill("Downloaded", systemImage: "checkmark.circle")

                    Menu {
                        Button(role: .destructive, action: deleteAction) {
                            Label("Delete Model", systemImage: "trash")
                        }

                        Button {
                            if let modelURL = service.downloadedModelURL {
                                NSWorkspace.shared.selectFile(
                                    modelURL.path,
                                    inFileViewerRootedAtPath: ""
                                )
                            }
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20, height: 20)
                } else {
                    ModelDownloadButton(
                        isDownloading: false,
                        downloadTitle: service.downloadError == nil ? "Download" : "Retry"
                    ) {
                        service.startDownload()
                    }
                }
            }
        }
    }

    private var downloadDetail: String {
        if service.isFinalizingDownload {
            return String(localized: "Finalizing model files…")
        }

        let downloaded = ByteCountFormatter.string(
            fromByteCount: service.downloadedBytes,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: service.totalDownloadBytes,
            countStyle: .file
        )

        return String(
            format: String(localized: "%@ of %@"),
            downloaded,
            total
        )
    }

    private var downloadAccessibilityValue: String {
        let percentage = service.downloadProgress.formatted(
            .percent.precision(.fractionLength(0))
        )
        return "\(percentage). \(downloadDetail)"
    }
}
