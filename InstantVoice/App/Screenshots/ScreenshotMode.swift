import AppKit

/// Reproducible screenshots for review and marketing. `scripts/screenshots.sh` relaunches a copy of the Debug build
/// under its own bundle identifier, home folder, and clock, names one scene per launch, and captures the main window
/// once the app reports it ready. Every other launch, and every Release build, leaves it off.
enum ScreenshotMode {
    static let isActive: Bool = {
        #if DEBUG
            return ScreenshotSession.current != nil
        #else
            return false
        #endif
    }()
}

#if DEBUG
    /// A screen the script can capture. Raw values are the names it passes with `-ScreenshotScene`.
    enum ScreenshotScene: String {
        case dashboard
        case insights
        case transcribe
        case history
        case historyInfo = "history-info"
        case modes
        case mode
        case dictionary
        case models
        case provider
        case audio
        case settings

        var section: ViewType {
            switch self {
            case .dashboard, .insights: return .dashboard
            case .transcribe: return .transcribeAudio
            case .history, .historyInfo: return .history
            case .modes, .mode: return .modes
            case .dictionary: return .dictionary
            case .models, .provider: return .models
            case .audio: return .audio
            case .settings: return .settings
            }
        }

        /// A page pushed on top of the section, as if the user had opened it.
        var route: MainWindowRoute? {
            switch self {
            case .insights: return .insights
            case .mode: return .mode(ScreenshotDemoData.emailModeID)
            case .provider: return .cloudProvider(AIProvider.soniox.rawValue)
            default: return nil
            }
        }
    }

    /// The launch arguments of one screenshot run.
    struct ScreenshotSession {
        static let bundleIdentifier = "com.sparanoid.InstantVoice.screenshots"

        /// Only the script's bundle identifier qualifies, so demo data never reaches a real defaults domain.
        static let current: ScreenshotSession? =
            Bundle.main.bundleIdentifier == bundleIdentifier ? ScreenshotSession(defaults: .standard) : nil

        let sceneName: String
        let scene: ScreenshotScene?
        let readyFileURL: URL?
        let windowSize: NSSize
        let settleDelay: Duration
        let activatesApp: Bool

        private init(defaults: UserDefaults) {
            sceneName = defaults.string(forKey: "ScreenshotScene") ?? ""
            scene = ScreenshotScene(rawValue: sceneName)
            readyFileURL = defaults.string(forKey: "ScreenshotReadyFile").map { URL(fileURLWithPath: $0) }
            windowSize = Self.size(from: defaults.string(forKey: "ScreenshotWindowSize")) ?? NSSize(width: 1280, height: 800)
            let settleSeconds = defaults.object(forKey: "ScreenshotSettleDelay") == nil
                ? 2 : defaults.double(forKey: "ScreenshotSettleDelay")
            settleDelay = .milliseconds(Int(settleSeconds * 1000))
            activatesApp = defaults.object(forKey: "ScreenshotActivate") == nil || defaults.bool(forKey: "ScreenshotActivate")
        }

        private static func size(from value: String?) -> NSSize? {
            let parts = value?.split(separator: "x").compactMap { Double($0) } ?? []
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
            return NSSize(width: parts[0], height: parts[1])
        }

        /// Seeds the demo state before any service reads defaults, and opens the scene's section.
        func prepare() {
            guard let scene else { return }
            ScreenshotDemoData.seedDefaults(for: scene)
            MainWindowNavigation.shared.reset(to: scene.section)
        }

        /// Sizes the main window, opens the scene's page, and tells the script when the window is ready to capture.
        @MainActor
        func present(_ window: NSWindow) {
            guard let scene else {
                report(["error": "Unknown screenshot scene \"\(sceneName)\""])
                NSApp.terminate(nil)
                return
            }

            // Wherever the pointer rests, it must not leave hover highlights in the capture.
            window.ignoresMouseEvents = true
            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            window.setFrame(
                NSRect(
                    x: (visibleFrame.midX - windowSize.width / 2).rounded(),
                    y: (visibleFrame.midY - windowSize.height / 2).rounded(),
                    width: windowSize.width,
                    height: windowSize.height
                ),
                display: true
            )

            Task { @MainActor in
                if let route = scene.route {
                    // The section's own page loads first, which Insights needs for its numbers.
                    try? await Task.sleep(for: .seconds(1))
                    MainWindowNavigation.shared.push(route)
                }
                try? await Task.sleep(for: settleDelay)
                if activatesApp {
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                window.displayIfNeeded()
                report([
                    "scene": scene.rawValue,
                    "windowID": window.windowNumber,
                    "pid": Int(ProcessInfo.processInfo.processIdentifier),
                    "scale": window.backingScaleFactor,
                    "width": window.frame.width,
                    "height": window.frame.height,
                ])
            }
        }

        private func report(_ info: [String: Any]) {
            guard let readyFileURL,
                let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
            else { return }
            try? data.write(to: readyFileURL, options: .atomic)
        }
    }
#endif
