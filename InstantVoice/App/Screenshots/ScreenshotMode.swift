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
        case onboardingPermissions = "onboarding-permissions"
        case onboardingMicrophone = "onboarding-microphone"
        case onboardingModel = "onboarding-model"
        case onboardingAPI = "onboarding-api"
        case onboardingShortcut = "onboarding-shortcut"
        case onboardingDictation = "onboarding-dictation"
        case onboardingEnhance = "onboarding-enhance"
        case onboardingEmail = "onboarding-email"
        case onboardingContext = "onboarding-context"
        case onboardingTrust = "onboarding-trust"
        case recorderRecording = "recorder-recording"
        case recorderLiveText = "recorder-live-text"
        case recorderTranscribing = "recorder-transcribing"
        case recorderAssistant = "recorder-assistant"

        /// The main-window section, or nil for onboarding and recorder scenes.
        var section: ViewType? {
            switch self {
            case .dashboard, .insights: return .dashboard
            case .transcribe: return .transcribeAudio
            case .history, .historyInfo: return .history
            case .modes, .mode: return .modes
            case .dictionary: return .dictionary
            case .models, .provider: return .models
            case .audio: return .audio
            case .settings: return .settings
            default: return nil
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

        var onboardingStage: OnboardingStage? {
            switch self {
            case .onboardingPermissions: return .permissions
            case .onboardingMicrophone: return .microphone
            case .onboardingModel: return .model
            case .onboardingAPI: return .api
            case .onboardingShortcut, .onboardingDictation, .onboardingEnhance, .onboardingEmail: return .experience
            case .onboardingContext: return .contextAwareness
            case .onboardingTrust: return .trust
            default: return nil
            }
        }

        /// The experience step on screen; Context Awareness follows the last one.
        var onboardingExperienceIndex: Int {
            switch self {
            case .onboardingEnhance: return 1
            case .onboardingEmail, .onboardingContext: return 2
            default: return 0
            }
        }

        /// Every step after Permissions only opens once the required access is granted.
        var grantsOnboardingPermissions: Bool {
            guard let onboardingStage else { return false }
            return onboardingStage != .permissions
        }

        /// Recorder scenes show the mini recorder over a wallpaper instead of the main window.
        var isRecorderScene: Bool {
            switch self {
            case .recorderRecording, .recorderLiveText, .recorderTranscribing, .recorderAssistant: return true
            default: return false
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
        let showsActiveAppearance: Bool

        private init(defaults: UserDefaults) {
            sceneName = defaults.string(forKey: "ScreenshotScene") ?? ""
            scene = ScreenshotScene(rawValue: sceneName)
            readyFileURL = defaults.string(forKey: "ScreenshotReadyFile").map { URL(fileURLWithPath: $0) }
            windowSize = Self.size(from: defaults.string(forKey: "ScreenshotWindowSize")) ?? NSSize(width: 1280, height: 800)
            let settleSeconds = defaults.object(forKey: "ScreenshotSettleDelay") == nil
                ? 2 : defaults.double(forKey: "ScreenshotSettleDelay")
            settleDelay = .milliseconds(Int(settleSeconds * 1000))
            showsActiveAppearance =
                defaults.object(forKey: "ScreenshotActiveAppearance") == nil
                || defaults.bool(forKey: "ScreenshotActiveAppearance")
        }

        private static func size(from value: String?) -> NSSize? {
            let parts = value?.split(separator: "x").compactMap { Double($0) } ?? []
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
            return NSSize(width: parts[0], height: parts[1])
        }

        /// Seeds the demo state before any service reads defaults, and opens the scene's section or onboarding step.
        func prepare() {
            guard let scene else { return }
            // Recorder scenes draw like the real recorder instead: InstantVoice stays in the background, and their
            // stage keeps its glass active the same way the recorder panel does.
            if showsActiveAppearance && !scene.isRecorderScene {
                ScreenshotActiveAppearance.install()
            }
            if let stage = scene.onboardingStage {
                ScreenshotDemoData.seedOnboardingDefaults(for: scene, stage: stage)
            } else if let section = scene.section {
                ScreenshotDemoData.seedDefaults(for: scene)
                MainWindowNavigation.shared.reset(to: section)
            } else if scene.isRecorderScene {
                ScreenshotDemoData.seedDefaults(for: scene)
            }
        }

        /// The first experience step always opens on its shortcut intro, so its practice scene skips ahead.
        @MainActor
        func prepare(_ coordinator: OnboardingCoordinator) {
            if scene == .onboardingDictation {
                coordinator.isExperienceInIntroPhase = false
            }
        }

        /// Sizes the main window, opens the scene's page, and tells the script when the window is ready to capture.
        @MainActor
        func present(_ window: NSWindow) {
            guard let scene else {
                report(["error": "Unknown screenshot scene \"\(sceneName)\""])
                NSApp.terminate(nil)
                return
            }
            if scene.isRecorderScene {
                presentRecorderStage(for: scene, hiding: window)
                return
            }

            // Wherever the pointer rests, it must not leave hover highlights in the capture.
            window.ignoresMouseEvents = true
            // Onboarding has a fixed size of its own.
            let size =
                scene.onboardingStage == nil
                ? windowSize : NSSize(width: AppWindowLayout.onboardingWidth, height: AppWindowLayout.onboardingHeight)
            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            window.setFrame(
                NSRect(
                    x: (visibleFrame.midX - size.width / 2).rounded(),
                    y: (visibleFrame.midY - size.height / 2).rounded(),
                    width: size.width,
                    height: size.height
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
                // Nothing keeps focus: an insertion point blinks, and whether a focus ring shows depends on the
                // viewer's keyboard navigation setting, so either would make captures differ.
                if window.firstResponder !== window {
                    window.makeFirstResponder(nil)
                    try? await Task.sleep(for: .milliseconds(400))
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

        /// Shows the mini recorder over a wallpaper in a window of its own, and tells the script to capture that window.
        @MainActor
        private func presentRecorderStage(for scene: ScreenshotScene, hiding mainWindow: NSWindow) {
            let stage = ScreenshotRecorderStage.makeWindow(for: scene, on: mainWindow.screen)
            Self.recorderStageWindow = stage
            mainWindow.orderOut(nil)

            Task { @MainActor in
                try? await Task.sleep(for: settleDelay)
                // An assistant reply focuses its follow-up field, whose insertion point would blink.
                stage.makeFirstResponder(nil)
                try? await Task.sleep(for: .milliseconds(400))
                stage.displayIfNeeded()
                report([
                    "scene": scene.rawValue,
                    "windowID": stage.windowNumber,
                    "pid": Int(ProcessInfo.processInfo.processIdentifier),
                    "scale": stage.backingScaleFactor,
                    "width": stage.frame.width,
                    "height": stage.frame.height,
                ])
            }
        }

        @MainActor private static var recorderStageWindow: NSWindow?

        private func report(_ info: [String: Any]) {
            guard let readyFileURL,
                let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
            else { return }
            try? data.write(to: readyFileURL, options: .atomic)
        }
    }

    /// Makes every window draw as the key and main window of the active app, so captures show the active style while
    /// the app stays in the background. AppKit and SwiftUI pick a window's style from these getters, several of them
    /// private; if a later macOS stops reading them, captures fall back to the inactive style.
    enum ScreenshotActiveAppearance {
        static func install() {
            let windowGetters = [
                "isKeyWindow", "isMainWindow", "hasKeyAppearance", "hasMainAppearance", "_hasKeyAppearance",
                "_hasMainAppearance", "_hasActiveAppearance", "_hasActiveAppearanceIgnoringKeyFocus",
                "_hasActiveControls", "_isKeyWindow", "_isKeyWindowIgnoringFocus",
            ]
            for name in windowGetters {
                returnTrue(NSWindow.self, name)
            }
            returnTrue(NSWindow.self, "_hasActiveAppearanceForStandardWindowButton:", takesArgument: true)
            returnTrue(NSApplication.self, "isActive")
            returnTrue(NSApplication.self, "_isActiveApp")
        }

        private static func returnTrue(_ type: AnyClass, _ name: String, takesArgument: Bool = false) {
            guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)) else { return }
            let block: Any =
                takesArgument
                ? { (_: AnyObject, _: Int) -> Bool in true } as @convention(block) (AnyObject, Int) -> Bool
                : { (_: AnyObject) -> Bool in true } as @convention(block) (AnyObject) -> Bool
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }
#endif
