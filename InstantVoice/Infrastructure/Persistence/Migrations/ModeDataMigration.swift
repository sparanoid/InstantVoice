import Foundation

extension ModeManager {
    func migratedModeConfigurationData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: configKey) {
            return data
        }

        guard let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) else {
            return nil
        }

        defaults.set(legacyData, forKey: configKey)
        return legacyData
    }

    func migrateLoadedModeConfigurationsIfNeeded() {
        var didChange = false
        let migratesRawModelNames = !UserDefaults.standard.bool(forKey: Self.rawModelNamesMigrationKey)
        let customModelNames =
            migratesRawModelNames ? Set(CustomCloudModelManager.shared.customModels.map(\.name)) : []

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            if config.selectedTranscriptionModelName == nil {
                config.selectedTranscriptionModelName = UserDefaults.standard.string(
                    forKey: "CurrentTranscriptionModel")
                changedConfig = true
            }

            if config.selectedLanguage == nil {
                config.selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
                changedConfig = true
            }

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
                let provider = config.selectedAIProvider
            {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if migratesRawModelNames,
                let modelName = config.selectedTranscriptionModelName,
                let rawName = Self.rawModelName(
                    for: modelName, realtime: config.isRealtimeTranscriptionEnabled, customModelNames: customModelNames)
            {
                config.selectedTranscriptionModelName = rawName
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if didChange {
            saveConfigurations()
        }
        if migratesRawModelNames {
            // The default model is saved the same way. It has no Real-time switch, so only renamed models
            // such as `nova-3` change.
            if let modelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
                let rawName = Self.rawModelName(for: modelName, realtime: false, customModelNames: customModelNames)
            {
                UserDefaults.standard.set(rawName, forKey: "CurrentTranscriptionModel")
            }
            UserDefaults.standard.set(true, forKey: Self.rawModelNamesMigrationKey)
        }

        migrateLegacyShortcutStorageIfNeeded()
    }

    private static let rawModelNamesMigrationKey = "didMigrateModesToRawModelNames"

    /// Applies the launch migration's model renames to modes it never saw, such as an older backup's.
    static func withRawModelNames(_ configs: [ModeConfig], customModelNames: Set<String>) -> [ModeConfig] {
        configs.map { config in
            guard let modelName = config.selectedTranscriptionModelName,
                let rawName = rawModelName(
                    for: modelName, realtime: config.isRealtimeTranscriptionEnabled, customModelNames: customModelNames)
            else { return config }
            var config = config
            config.selectedTranscriptionModelName = rawName
            return config
        }
    }

    /// Cloud models used to merge a provider's file and real-time models into one entry, with the Real-time
    /// switch picking between them. Modes now name the model they use, so real-time modes move to the
    /// streaming model, and Deepgram's general models take their canonical names. Earlier versions also saved a
    /// custom model by its name, which can look like a provider's model, such as `nova-2`; those names stay.
    private static func rawModelName(for modelName: String, realtime: Bool, customModelNames: Set<String>) -> String? {
        guard !customModelNames.contains(modelName) else { return nil }
        if modelName.range(of: #"^nova-\d+$"#, options: .regularExpression) != nil {
            return "\(modelName)-general"
        }
        guard realtime else { return nil }
        if modelName.hasPrefix("stt-async-") {
            return "stt-rt-" + modelName.dropFirst("stt-async-".count)
        }
        if modelName == "scribe_v2" {
            return "scribe_v2_realtime"
        }
        if modelName.hasPrefix("gemini-"), modelName.hasSuffix("-transcribe") {
            return "\(modelName)-live"
        }
        return nil
    }

    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.mode(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
                let oldShortcutData = defaults.data(forKey: oldShortcutKey)
            {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
                defaults.object(forKey: oldClearedKey) != nil
            {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}
