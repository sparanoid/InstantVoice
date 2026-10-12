#if DEBUG
    import AVFoundation
    import CoreAudio
    import Foundation
    import SwiftData

    /// The fixed content of screenshot runs. Dates count back from launch, which the screenshot script pins to a fixed
    /// moment, so every run renders the same labels.
    enum ScreenshotDemoData {
        // The first UUID byte picks each mode's tile color from ModeIconTile's palette.
        static let dictationModeID = UUID(uuidString: "0A3F5C10-6B2E-4D8A-9C71-1E5B7A2D4F01")!  // blue
        static let cleanUpModeID = UUID(uuidString: "0C7D2E41-3A9B-4F6C-8E15-2B4D6F8A0C02")!  // purple
        static let emailModeID = UUID(uuidString: "0B52A9E3-7C1D-4B8F-A6E2-3C5D7E9F1A03")!  // indigo
        static let rewriteModeID = UUID(uuidString: "1194B7C2-5E3F-4A1D-B8C6-4D6E8F0A2B04")!  // teal
        static let assistantModeID = UUID(uuidString: "0F28C6D4-9A5B-4E2C-9D37-5E7F9A1B3C05")!  // orange
        static let notesModeID = UUID(uuidString: "10E1D8F5-2B6C-4F3E-AE48-6F8A0B2C4D06")!  // green

        // MARK: - Defaults

        static func seedDefaults(for scene: ScreenshotScene) {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: OnboardingSettings.completedV2Key)
            defaults.set(try? JSONEncoder().encode(modes), forKey: "modeConfigurationsV2")
            defaults.set(dictationModeID.uuidString, forKey: "activeConfigurationId")
            defaults.set(try? JSONEncoder().encode(PromptTemplates.seedPrompts), forKey: "customPrompts")
            defaults.set(true, forKey: "didMigrateModesToRawModelNames")
            defaults.set("stt-rt-v5", forKey: "CurrentTranscriptionModel")
            defaults.set("Alex", forKey: "dashboardDisplayName")
            defaults.set(false, forKey: "PrewarmModelOnWake")
            defaults.set(scene == .historyInfo, forKey: "HistoryInspectorIsPresented")
            ShortcutStore.setShortcut(.rightCommand, for: .primaryRecording)
        }

        private static var modes: [ModeConfig] {
            [
                ModeConfig(
                    id: dictationModeID, name: "Dictation", icon: .symbol("mic.fill"), isAIEnhancementEnabled: false,
                    selectedTranscriptionModelName: "stt-rt-v5", selectedLanguage: "auto",
                    useSelectedTextContext: false, isTextFormattingEnabled: true, isDefault: true
                ),
                ModeConfig(
                    id: cleanUpModeID, name: "Clean Up", icon: .symbol("sparkles"), isAIEnhancementEnabled: true,
                    selectedPrompt: PromptTemplates.defaultPromptId.uuidString,
                    selectedTranscriptionModelName: "nova-3-general", selectedLanguage: "en",
                    isTextFormattingEnabled: true, selectedAIProvider: AIProvider.anthropic.rawValue,
                    selectedAIModel: "claude-sonnet-5"
                ),
                ModeConfig(
                    id: emailModeID, name: "Email", icon: .symbol("envelope.fill"),
                    triggerGroups: [
                        ModeTriggerGroup(
                            id: UUID(uuidString: "6D1E2F30-4A5B-4C6D-8E7F-9A0B1C2D3E07")!,
                            templateId: "email",
                            name: "Email",
                            appConfigs: [
                                AppConfig(
                                    id: UUID(uuidString: "7E2F3041-5B6C-4D7E-9F80-AB1C2D3E4F08")!,
                                    bundleIdentifier: "com.apple.mail", appName: "Mail")
                            ],
                            urlConfigs: [
                                URLConfig(
                                    id: UUID(uuidString: "8F304152-6C7D-4E8F-A091-BC2D3E4F5009")!,
                                    url: "mail.google.com"),
                                URLConfig(
                                    id: UUID(uuidString: "90415263-7D8E-4F90-B1A2-CD3E4F50610A")!,
                                    url: "outlook.office.com"),
                            ]
                        )
                    ],
                    isAIEnhancementEnabled: true, selectedPrompt: PromptTemplates.emailPromptId.uuidString,
                    selectedTranscriptionModelName: "scribe_v2", selectedLanguage: "en", useClipboardContext: true,
                    isTextFormattingEnabled: true, selectedAIProvider: AIProvider.openAI.rawValue,
                    selectedAIModel: "gpt-6-luna"
                ),
                ModeConfig(
                    id: rewriteModeID, name: "Rewrite", icon: .symbol("pencil.and.scribble"), triggerWords: ["rewrite"],
                    isAIEnhancementEnabled: true, selectedPrompt: PromptTemplates.rewritePromptId.uuidString,
                    selectedTranscriptionModelName: "stt-rt-v5", selectedLanguage: "auto",
                    selectedAIProvider: AIProvider.anthropic.rawValue, selectedAIModel: "claude-haiku-4-5"
                ),
                ModeConfig(
                    id: assistantModeID, name: "Assistant", icon: .symbol("bubble.left.and.text.bubble.right.fill"),
                    isAIEnhancementEnabled: true, selectedPrompt: PromptTemplates.assistantPromptId.uuidString,
                    selectedTranscriptionModelName: "stt-rt-v5", selectedLanguage: "auto",
                    selectedAIProvider: AIProvider.gemini.rawValue, selectedAIModel: "gemini-3.8-flash",
                    outputMode: .respond
                ),
                ModeConfig(
                    id: notesModeID, name: "Meeting Notes", icon: .symbol("note.text"),
                    triggerGroups: [
                        ModeTriggerGroup(
                            id: UUID(uuidString: "A1526374-8E9F-4A01-82B3-DE4F5061720B")!,
                            name: "Notes",
                            appConfigs: [
                                AppConfig(
                                    id: UUID(uuidString: "B2637485-9FA0-4B12-93C4-EF506172830C")!,
                                    bundleIdentifier: "com.apple.Notes", appName: "Notes")
                            ]
                        )
                    ],
                    isAIEnhancementEnabled: true, selectedPrompt: PromptTemplates.defaultPromptId.uuidString,
                    selectedTranscriptionModelName: "nova-3-general", selectedLanguage: "en",
                    isTextFormattingEnabled: true, selectedAIProvider: AIProvider.anthropic.rawValue,
                    selectedAIModel: "claude-sonnet-5", isEnabled: false
                ),
            ]
        }

        // MARK: - Credentials and devices

        /// Keychain accounts with obviously fake keys, so cloud providers show as connected.
        static let credentials: [String: Data] = [
            "sonioxAPIKey": "demo-soniox-key-7d41",
            "deepgramAPIKey": "demo-deepgram-key-3b9c",
            "elevenLabsAPIKey": "demo-elevenlabs-key-a52e",
            "anthropicAPIKey": "demo-anthropic-key-91f0",
            "openAIAPIKey": "demo-openai-key-c3d8",
            "geminiAPIKey": "demo-gemini-key-5e27",
        ].mapValues { Data($0.utf8) }

        /// Input devices shown instead of the machine's own. IDs sit far above real CoreAudio ones.
        static let audioDevices: [(id: AudioDeviceID, uid: String, name: String)] = [
            (90_001, "InstantVoiceScreenshots.BuiltInMicrophone", "MacBook Pro Microphone"),
            (90_002, "InstantVoiceScreenshots.StudioDisplay", "Studio Display Microphone"),
            (90_003, "InstantVoiceScreenshots.AirPods", "AirPods Pro"),
        ]

        // MARK: - Stored data

        /// Fills the in-memory container with history, usage statistics, and dictionary entries.
        @MainActor
        static func seed(into context: ModelContext) {
            let now = Date()
            let calendar = Calendar.current
            let recordingURL = writeDemoRecording(named: "screenshot-demo", duration: transcripts[0].duration)

            for (index, transcript) in transcripts.enumerated() {
                let timestamp = date(daysAgo: transcript.daysAgo, hour: transcript.hour, minute: transcript.minute)
                let mode = transcript.mode
                let transcription = Transcription(
                    text: transcript.text,
                    duration: transcript.duration,
                    enhancedText: transcript.enhancedText,
                    audioFileURL: index == 0 ? recordingURL?.absoluteString : nil,
                    transcriptionModelName: mode.transcriptionModel,
                    aiEnhancementModelName: transcript.enhancedText == nil ? nil : mode.enhancementModel,
                    promptName: transcript.enhancedText == nil ? nil : mode.promptName,
                    transcriptionDuration: mode.transcriptionSeconds(for: transcript.duration),
                    enhancementDuration: transcript.enhancedText == nil ? nil : mode.enhancementSeconds,
                    modeName: mode.name,
                    modeEmoji: mode.symbol,
                    transcriptionStatus: .completed
                )
                transcription.id = UUID(uuidString: String(format: "5C2EE0A1-0000-4000-8000-%012X", index + 1))!
                transcription.timestamp = timestamp
                context.insert(transcription)
                context.insert(
                    metric(
                        for: mode, at: timestamp, transcriptionID: transcription.id,
                        words: wordCount(transcript.text), audio: transcript.duration,
                        enhanced: transcript.enhancedText != nil))
            }

            // Months of earlier sessions without history entries, as after automatic cleanup.
            var random = DemoRandom(seed: 0x1A5E_2026_0941)
            let startOfToday = calendar.startOfDay(for: now)
            for daysAgo in 1...200 {
                guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) else { continue }
                let isWeekend = calendar.isDateInWeekend(day)
                // A quiet stretch keeps the activity calendar from looking machine-made.
                let isVacation = (52...60).contains(daysAgo)
                let sessions = isVacation ? 0 : (isWeekend ? random.int(in: 0...3) : random.int(in: 3...10))
                for _ in 0..<sessions {
                    let hour = demoHours[random.int(in: 0...(demoHours.count - 1))]
                    let minute = random.int(in: 0...59)
                    guard let timestamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
                    else { continue }
                    let mode = DemoMode.weighted(random.unit())
                    let words = random.int(in: 12...95)
                    let audio = Double(words) / 2.6 + Double(random.int(in: 10...30)) / 10
                    context.insert(
                        metric(
                            for: mode, at: timestamp, transcriptionID: UUID(), words: words, audio: audio,
                            enhanced: mode.enhancementModel != nil))
                }
            }

            for (offset, word) in vocabulary.enumerated() {
                context.insert(VocabularyWord(word: word, dateAdded: date(daysAgo: 40 - offset * 2, hour: 10, minute: 0)))
            }
            for (offset, entry) in replacements.enumerated() {
                context.insert(
                    WordReplacement(
                        originalText: entry.original,
                        replacementText: entry.replacement,
                        dateAdded: date(daysAgo: 30 - offset * 3, hour: 14, minute: 0)
                    ))
            }

            try? context.save()
        }

        private static let demoHours = [8, 9, 9, 10, 10, 10, 11, 11, 13, 14, 14, 15, 15, 16, 17, 19]

        private static func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        private static func wordCount(_ text: String) -> Int {
            text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        }

        private static func metric(
            for mode: DemoMode, at timestamp: Date, transcriptionID: UUID, words: Int, audio: TimeInterval,
            enhanced: Bool
        ) -> SessionMetric {
            let transcriptionSeconds = mode.transcriptionSeconds(for: audio)
            return SessionMetric(
                transcriptionId: transcriptionID,
                timestamp: timestamp,
                wordCount: words,
                audioDuration: audio,
                transcriptionModelName: mode.transcriptionModel,
                transcriptionDuration: transcriptionSeconds,
                speedFactor: audio / transcriptionSeconds,
                modeName: mode.name,
                aiEnhancementModelName: enhanced ? mode.enhancementModel : nil,
                enhancementDuration: enhanced ? mode.enhancementSeconds : nil,
                enhancementEstimatedTokenCount: enhanced ? 420 + words * 3 : nil
            )
        }

        // MARK: - Content

        private enum DemoMode {
            case dictation, cleanUp, email, rewrite, assistant

            static func weighted(_ value: Double) -> DemoMode {
                switch value {
                case ..<0.5: return .dictation
                case ..<0.7: return .cleanUp
                case ..<0.85: return .email
                case ..<0.95: return .rewrite
                default: return .assistant
                }
            }

            var name: String {
                switch self {
                case .dictation: return "Dictation"
                case .cleanUp: return "Clean Up"
                case .email: return "Email"
                case .rewrite: return "Rewrite"
                case .assistant: return "Assistant"
                }
            }

            var symbol: String {
                switch self {
                case .dictation: return "mic.fill"
                case .cleanUp: return "sparkles"
                case .email: return "envelope.fill"
                case .rewrite: return "pencil.and.scribble"
                case .assistant: return "bubble.left.and.text.bubble.right.fill"
                }
            }

            var transcriptionModel: String {
                switch self {
                case .dictation, .rewrite, .assistant: return "stt-rt-v5"
                case .cleanUp: return "nova-3-general"
                case .email: return "scribe_v2"
                }
            }

            var enhancementModel: String? {
                switch self {
                case .dictation: return nil
                case .cleanUp: return "claude-sonnet-5"
                case .email: return "gpt-6-luna"
                case .rewrite: return "claude-haiku-4-5"
                case .assistant: return "gemini-3.8-flash"
                }
            }

            var promptName: String? {
                switch self {
                case .dictation: return nil
                case .cleanUp: return "Default"
                case .email: return "Email"
                case .rewrite: return "Rewrite"
                case .assistant: return "Assistant"
                }
            }

            /// Streaming models finish moments after the speaker stops; file models take a pass over the audio.
            func transcriptionSeconds(for audio: TimeInterval) -> TimeInterval {
                switch self {
                case .dictation, .rewrite, .assistant: return 0.35 + audio * 0.004
                case .cleanUp: return 0.6 + audio * 0.012
                case .email: return 0.9 + audio * 0.025
                }
            }

            var enhancementSeconds: TimeInterval? {
                switch self {
                case .dictation: return nil
                case .cleanUp: return 1.8
                case .email: return 1.4
                case .rewrite: return 0.7
                case .assistant: return 0.9
                }
            }
        }

        private struct DemoTranscript {
            let daysAgo: Int
            let hour: Int
            let minute: Int
            let mode: DemoMode
            let duration: TimeInterval
            let text: String
            var enhancedText: String? = nil
        }

        /// History, newest first. The first entry is selected in History and gets the demo recording. Its detail view
        /// renders Markdown, so that entry writes a line break inside a paragraph as two spaces and `\n`; the others only
        /// appear as plain-text rows, where the spaces would show as a gap.
        private static let transcripts: [DemoTranscript] = [
            DemoTranscript(
                daysAgo: 0, hour: 9, minute: 38, mode: .email, duration: 26.4,
                text:
                    "Hi Priya, thanks for sending the Q4 roadmap draft. I went through it this morning and it looks great. Um, two small things. Can we move the onboarding refresh up to November, and, uh, add a line about the offline mode beta? Also let me know if Thursday works for a quick sync.",
                enhancedText:
                    "Hi Priya,\n\nThanks for sending the Q4 roadmap draft. I went through it this morning, and it looks great. Two small things:\n\n• Can we move the onboarding refresh up to November?  \n• Could we add a line about the offline mode beta?\n\nAlso, let me know if Thursday works for a quick sync.\n\nBest,  \nAlex"
            ),
            DemoTranscript(
                daysAgo: 0, hour: 9, minute: 24, mode: .dictation, duration: 11.8,
                text:
                    "Remind me to book the venue for the team offsite before Friday, and check whether the projector in the big conference room has been fixed."
            ),
            DemoTranscript(
                daysAgo: 0, hour: 9, minute: 7, mode: .cleanUp, duration: 31.2,
                text:
                    "So the main takeaway from the user interviews is that, um, people want faster exports. They really like the new sidebar, but a few of them got lost in the settings, so we should probably, uh, look at the labels there. And everyone asked about keyboard shortcuts.",
                enhancedText:
                    "The main takeaway from the user interviews is that people want faster exports. They really like the new sidebar, but a few got lost in Settings, so we should revisit the labels there. Everyone also asked about keyboard shortcuts."
            ),
            DemoTranscript(
                daysAgo: 0, hour: 8, minute: 46, mode: .assistant, duration: 9.6,
                text: "What's a polite way to tell the team we need one more week for the launch?",
                enhancedText:
                    "Here's a friendly, direct option:\n\n\"Quick update on the launch: we're taking one more week to get the last details right. The new date is Tuesday, October 20. Thanks for your patience — it'll be worth it.\""
            ),
            DemoTranscript(
                daysAgo: 0, hour: 8, minute: 31, mode: .dictation, duration: 7.4,
                text:
                    "Grocery list: oat milk, sourdough, blueberries, two avocados, and coffee beans from the roaster on Main Street."
            ),
            DemoTranscript(
                daysAgo: 1, hour: 18, minute: 12, mode: .rewrite, duration: 6.2,
                text: "Make this sound friendlier: we can't ship the export feature this sprint.",
                enhancedText:
                    "Heads-up: the export feature needs a little more time, so it'll land next sprint instead of this one."
            ),
            DemoTranscript(
                daysAgo: 1, hour: 16, minute: 5, mode: .dictation, duration: 14.3,
                text:
                    "Pushed the fix for the sync bug. Can someone on the iOS side double-check the conflict resolution path before we cut the release?"
            ),
            DemoTranscript(
                daysAgo: 1, hour: 11, minute: 20, mode: .email, duration: 22.7,
                text:
                    "Hi Marcus, thanks for the quick turnaround on the contract. I signed it and, uh, attached it here. Looking forward to kicking things off next Monday.",
                enhancedText:
                    "Hi Marcus,\n\nThanks for the quick turnaround on the contract. I've signed it and attached it here.\n\nLooking forward to kicking things off next Monday.\n\nBest,\nAlex"
            ),
            DemoTranscript(
                daysAgo: 2, hour: 15, minute: 50, mode: .cleanUp, duration: 41.5,
                text:
                    "Okay, notes for the design review. Uh, the empty states need illustrations, the onboarding copy is too long, and, um, we agreed to test the new color palette with five users before we commit.",
                enhancedText:
                    "Notes for the design review:\n• The empty states need illustrations.\n• The onboarding copy is too long.\n• We'll test the new color palette with five users before committing."
            ),
            DemoTranscript(
                daysAgo: 3, hour: 10, minute: 15, mode: .dictation, duration: 18.9,
                text:
                    "Ideas for the weekend: try the new ramen place downtown, finish the last chapter of my book, and fix the squeaky hinge on the back door."
            ),
            DemoTranscript(
                daysAgo: 4, hour: 14, minute: 30, mode: .assistant, duration: 8.1,
                text: "Summarize the selected article in three bullet points.",
                enhancedText:
                    "• Teams that write decisions down move faster.\n• Short daily check-ins beat long weekly meetings.\n• Clear ownership matters more than the tools you use."
            ),
            DemoTranscript(
                daysAgo: 5, hour: 9, minute: 5, mode: .dictation, duration: 12.6,
                text:
                    "To do: cache the waveform thumbnails so the history list scrolls smoothly on older Macs."
            ),
            DemoTranscript(
                daysAgo: 6, hour: 17, minute: 40, mode: .cleanUp, duration: 27.9,
                text:
                    "Um, so for the release notes, we fixed the crash when importing long recordings, improved, uh, accuracy for names and technical terms, and the menu bar icon now shows when you're recording.",
                enhancedText:
                    "This release fixes a crash when importing long recordings, improves accuracy for names and technical terms, and shows recording status in the menu bar icon."
            ),
            DemoTranscript(
                daysAgo: 9, hour: 13, minute: 25, mode: .email, duration: 19.4,
                text:
                    "Hi team, quick reminder that the office will be closed on Monday for the holiday. Uh, enjoy the long weekend!",
                enhancedText:
                    "Hi team,\n\nQuick reminder that the office will be closed on Monday for the holiday.\n\nEnjoy the long weekend!\n\nAlex"
            ),
            DemoTranscript(
                daysAgo: 13, hour: 10, minute: 40, mode: .dictation, duration: 16.2,
                text:
                    "Book a dentist appointment for next week and renew the car registration online before the end of the month."
            ),
        ]

        private static let vocabulary = [
            "InstantVoice", "Liquid Glass", "SwiftUI", "Xcode", "TestFlight", "Kubernetes", "PostgreSQL", "GraphQL",
            "OKRs", "Priya Raman", "Marcus Chen", "Café Lumière", "Parakeet", "Soniox", "WWDC", "macOS",
        ]

        private static let replacements: [(original: String, replacement: String)] = [
            ("eye phone, i phone", "iPhone"),
            ("mac book, macbook", "MacBook"),
            ("get hub", "GitHub"),
            ("jay son, j son", "JSON"),
            ("pie torch", "PyTorch"),
            ("you are el, u r l", "URL"),
            ("a sap, asap", "ASAP"),
            ("instant voice", "InstantVoice"),
        ]

        // MARK: - Demo recording

        /// Writes a speech-like recording so History shows its player and waveform. The waveform comes from a seeded
        /// generator rather than a synthesized voice, so it's identical on every Mac.
        private static func writeDemoRecording(named name: String, duration: TimeInterval) -> URL? {
            let directory = URL.applicationSupportDirectory
                .appending(path: "com.sparanoid.InstantVoice/Recordings", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(name).wav")

            let sampleRate = 16_000.0
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * sampleRate)),
                let samples = buffer.floatChannelData?[0]
            else { return nil }
            buffer.frameLength = buffer.frameCapacity

            // Phrases of syllables separated by pauses, over low-passed noise.
            var random = DemoRandom(seed: 0x00C0_FFEE_2026)
            let frameCount = Int(buffer.frameLength)
            samples.update(repeating: 0, count: frameCount)
            var frame = Int(0.35 * sampleRate)
            var filtered: Float = 0
            while frame < frameCount {
                let phraseEnd = min(frameCount, frame + Int((1.4 + random.unit() * 2.6) * sampleRate))
                while frame < phraseEnd {
                    let syllableLength = Int((0.11 + random.unit() * 0.17) * sampleRate)
                    let loudness = Float(0.25 + random.unit() * 0.65)
                    for offset in 0..<syllableLength where frame + offset < frameCount {
                        let envelope = sin(Float.pi * Float(offset) / Float(syllableLength))
                        filtered += 0.35 * (Float(random.unit() * 2 - 1) - filtered)
                        samples[frame + offset] = filtered * envelope * loudness
                    }
                    frame += syllableLength + Int(random.unit() * 0.06 * sampleRate)
                }
                frame += Int((0.25 + random.unit() * 0.5) * sampleRate)
            }

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ]
            do {
                let file = try AVAudioFile(
                    forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try file.write(from: buffer)
                return url
            } catch {
                return nil
            }
        }
    }

    /// SplitMix64, so seeded demo data comes out the same on every run.
    private struct DemoRandom {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        /// A value in 0..<1.
        mutating func unit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
    }
#endif
