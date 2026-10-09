import Combine
import Foundation
import OSLog

enum InstantVoiceRefineAvailability: Equatable {
    case available
    case unsupportedIntel
    case insufficientMemory
}

enum InstantVoiceRefineError: LocalizedError {
    case unavailable
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "InstantVoice Refine requires an Apple silicon Mac with at least 16 GB of memory.")
        case .modelNotDownloaded:
            return String(localized: "InstantVoice Refine is not downloaded.")
        }
    }
}

final class InstantVoiceRefineService: ObservableObject {
    static let shared = InstantVoiceRefineService()

    static let providerName = "InstantVoice Refine"
    static let modelName = "VoiceInk Refine V1"
    static let systemPrompt = """
        Transform raw ASR input into polished text. Preserve the original meaning and tone. Handle punctuation, capitalization, and spoken formatting cues properly. Remove fillers, repetitions, false starts, and discarded self-corrections. Output only the final text.
        """
    static let repositoryID = "beingpax/VoiceInk-Refine-V1"
    static let pinnedRevision = "ad665418d3850e379e29236e66be3ddc0ac0bf04"
    static let minimumMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
    static var downloadSizeDescription: String {
        ByteCountFormatter.string(
            fromByteCount: InstantVoiceRefineModelDownloader.totalBytes,
            countStyle: .file
        )
    }

    @Published private(set) var isDownloaded = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress = 0.0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalDownloadBytes = InstantVoiceRefineModelDownloader.totalBytes
    private(set) var isFinalizingDownload = false
    @Published private(set) var downloadError: String?

    let availability: InstantVoiceRefineAvailability

    var isAvailableInModes: Bool {
        availability == .available && isDownloaded
    }

    var downloadedModelURL: URL? {
        isDownloaded ? snapshotURL : nil
    }

    var unavailableDescription: String? {
        switch availability {
        case .available:
            return nil
        case .unsupportedIntel:
            return String(localized: "Available on Apple silicon Macs with at least 16 GB of memory.")
        case .insufficientMemory:
            return String(localized: "Requires at least 16 GB of memory.")
        }
    }

    private let logger = Logger(
        subsystem: "com.sparanoid.instantvoice",
        category: "InstantVoiceRefineService"
    )
    private let modelRootDirectory: URL
    private let inferenceClient = InstantVoiceRefineXPCClient()
    private var downloadTask: Task<Void, Never>?

    private init(
        architectureIsAppleSilicon: Bool = SystemArchitecture.isAppleSilicon,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        if !architectureIsAppleSilicon {
            availability = .unsupportedIntel
        } else if physicalMemory < Self.minimumMemoryBytes {
            availability = .insufficientMemory
        } else {
            availability = .available
        }

        let appSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        modelRootDirectory = appSupportDirectory
            .appendingPathComponent("com.sparanoid.InstantVoice")
            .appendingPathComponent("InstantVoiceRefine")

        refreshDownloadedState()
    }

    @MainActor
    func startDownload() {
        guard availability == .available, !isDownloaded, downloadTask == nil else {
            return
        }

        downloadTask = Task { [weak self] in
            await self?.downloadModel()
        }
    }

    @MainActor
    func cancelDownload() {
        downloadTask?.cancel()
    }

    @MainActor
    func deleteModel() async {
        cancelDownload()
        await inferenceClient.shutdown()

        do {
            if FileManager.default.fileExists(atPath: modelRootDirectory.path) {
                try FileManager.default.removeItem(at: modelRootDirectory)
            }
            downloadProgress = 0
            downloadedBytes = 0
            isFinalizingDownload = false
            downloadError = nil
            refreshDownloadedState()
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        } catch {
            downloadError = error.localizedDescription
            logger.error("Failed to delete InstantVoice Refine: \(error.localizedDescription, privacy: .public)")
        }
    }

    func enhance(transcript: String) async throws -> String {
        guard availability == .available else {
            throw InstantVoiceRefineError.unavailable
        }
        guard isDownloaded, let snapshotURL else {
            throw InstantVoiceRefineError.modelNotDownloaded
        }

        return try await inferenceClient.enhance(
            transcript: transcript,
            modelDirectory: snapshotURL,
            systemPrompt: Self.systemPrompt
        )
    }

    func unloadPreparedModelIfNeeded() async {
        await inferenceClient.shutdownPreparedModelIfNeeded()
    }

    func keepPreparedModelWarmForRecording() async {
        await inferenceClient.keepPreparedModelWarmForRecording()
    }

    func prepareForRecording() async {
        guard availability == .available, isDownloaded, let snapshotURL else {
            return
        }

        do {
            try await inferenceClient.prepare(
                modelDirectory: snapshotURL,
                systemPrompt: Self.systemPrompt
            )
        } catch is CancellationError {
        } catch {
            logger.error(
                "Background model preparation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @MainActor
    private func downloadModel() async {
        downloadProgress = 0
        downloadedBytes = 0
        totalDownloadBytes = InstantVoiceRefineModelDownloader.totalBytes
        isFinalizingDownload = false
        downloadError = nil
        isDownloading = true

        defer {
            isDownloading = false
            isFinalizingDownload = false
            downloadTask = nil
        }

        #if arch(arm64)
            let downloader = InstantVoiceRefineModelDownloader(
                repositoryID: Self.repositoryID,
                revision: Self.pinnedRevision,
                modelRootDirectory: modelRootDirectory
            )
            let progressTask = Task { @MainActor [weak self, downloader] in
                while !Task.isCancelled {
                    self?.applyDownloadProgress(downloader.progress)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            defer {
                progressTask.cancel()
            }

            do {
                let downloadOperation = Task.detached(priority: .utility) {
                    try await downloader.download()
                }
                defer {
                    downloadOperation.cancel()
                }

                try await withTaskCancellationHandler {
                    try await downloadOperation.value
                } onCancel: {
                    downloadOperation.cancel()
                }
                try Task.checkCancellation()
                applyDownloadProgress(downloader.progress)
                refreshDownloadedState()
                downloadProgress = isDownloaded ? 1 : 0
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            } catch is CancellationError {
                cleanupCancelledDownload()
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    cleanupCancelledDownload()
                } else {
                    downloadError = error.localizedDescription
                    logger.error("Failed to download InstantVoice Refine: \(error.localizedDescription, privacy: .public)")
                }
            }
        #else
            downloadError = InstantVoiceRefineError.unavailable.localizedDescription
        #endif
    }

    private func cleanupCancelledDownload() {
        try? FileManager.default.removeItem(at: modelRootDirectory)
        downloadProgress = 0
        downloadedBytes = 0
        refreshDownloadedState()
        downloadError = nil
    }

    private var snapshotURL: URL? {
        #if arch(arm64)
            return InstantVoiceRefineModelDownloader.snapshotDirectory(
                in: modelRootDirectory,
                repositoryID: Self.repositoryID,
                revision: Self.pinnedRevision
            )
        #else
            return nil
        #endif
    }

    private func refreshDownloadedState() {
        guard let snapshotURL else {
            isDownloaded = false
            return
        }

        isDownloaded = InstantVoiceRefineModelDownloader.isSnapshotComplete(
            at: snapshotURL
        )
    }

    @MainActor
    private func applyDownloadProgress(
        _ progress: InstantVoiceRefineDownloadProgress
    ) {
        downloadedBytes = progress.downloadedBytes
        totalDownloadBytes = progress.totalBytes
        isFinalizingDownload = progress.isFinalizing
        downloadProgress = progress.totalBytes > 0
            ? min(1, Double(progress.downloadedBytes) / Double(progress.totalBytes))
            : 0
    }
}
