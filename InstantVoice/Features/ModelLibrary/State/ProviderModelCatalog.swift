import Foundation
import LLMkit
import os

/// The models each cloud provider lists through its API, cached between launches.
///
/// Providers' built-in model lists only fill in until their list has been fetched, and for providers that
/// have no list endpoint. OpenRouter keeps its own catalog in `OpenRouterCatalogStore`.
final class ProviderModelCatalog: @unchecked Sendable {
    static let shared = ProviderModelCatalog()

    /// Lists older than this are fetched again at launch.
    static let maximumAge: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let models: [ListedModel]
        let fetchedAt: Date
    }

    private let lock = NSLock()
    private let storageQueue = DispatchQueue(label: "com.sparanoid.instantvoice.providerModelCatalog.storage")
    private let defaults = UserDefaults.standard
    private let storageKey = "providerModelCatalogs"
    private var entries: [String: Entry] = [:]
    private var refreshingProviders: Set<String> = []
    private let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "ProviderModelCatalog")

    private init() {
        if let data = defaults.data(forKey: storageKey),
            let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        {
            entries = stored
        }
    }

    /// The models last fetched for a provider, or nil if its list hasn't been fetched.
    func models(for providerKey: String) -> [ListedModel]? {
        lock.lock()
        defer { lock.unlock() }
        return entries[providerKey]?.models
    }

    func fetchedAt(for providerKey: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[providerKey]?.fetchedAt
    }

    /// The model a listed alias forwards to, in any provider's list.
    func aliasTarget(of modelID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        for entry in entries.values {
            if let target = entry.models.first(where: { $0.id == modelID })?.aliasOf {
                return target
            }
        }
        return nil
    }

    /// Whether the provider has a list-models endpoint this catalog can fetch.
    static func supportsListing(_ providerKey: String) -> Bool {
        listingRequest(for: providerKey) != nil
    }

    /// Fetches the provider's current models with its saved API key and replaces the cached list.
    func refresh(providerKey: String) async throws {
        guard let fetch = Self.listingRequest(for: providerKey) else { return }
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: providerKey), !apiKey.isEmpty else {
            throw LLMKitError.missingAPIKey
        }
        guard beginRefreshing(providerKey) else { return }
        defer { endRefreshing(providerKey) }

        let models = try await fetch(apiKey)
        guard !models.isEmpty else { throw LLMKitError.noResultReturned }
        save(models, for: providerKey)
        logger.notice("Fetched \(models.count, privacy: .public) models for \(providerKey, privacy: .public)")

        await MainActor.run {
            NotificationCenter.default.post(name: .providerModelCatalogDidChange, object: providerKey)
        }
    }

    /// Refreshes the lists of connected providers that are missing or older than `maximumAge`.
    func refreshStaleCatalogs() async {
        let staleProviders = Self.listingProviderKeys.filter { providerKey in
            guard APIKeyManager.shared.hasAPIKey(forProvider: providerKey) else { return false }
            guard let fetchedAt = fetchedAt(for: providerKey) else { return true }
            return Date().timeIntervalSince(fetchedAt) > Self.maximumAge
        }

        await withTaskGroup(of: Void.self) { group in
            for providerKey in staleProviders {
                group.addTask {
                    do {
                        try await self.refresh(providerKey: providerKey)
                    } catch {
                        // The last fetched list, or the built-in one, stays in use.
                        self.logger.error(
                            "Couldn't refresh models for \(providerKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Fetching

    /// Providers with a list-models endpoint. xAI, Cartesia, and ElevenLabs don't list their speech-to-text
    /// models, and OpenRouter's catalog is kept separately.
    private static let listingProviderKeys = ["OpenAI", "Anthropic", "Gemini", "Groq", "Deepgram", "Soniox"]

    private static func listingRequest(for providerKey: String) -> (@Sendable (String) async throws -> [ListedModel])? {
        switch providerKey {
        case "OpenAI":
            return { try await OpenAILLMClient.listModels(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: $0) }
        case "Groq":
            return {
                try await OpenAILLMClient.listModels(baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: $0)
            }
        case "Anthropic":
            return { try await AnthropicLLMClient.listModels(apiKey: $0) }
        case "Gemini":
            return { try await GeminiLLMClient.listModels(apiKey: $0) }
        case "Deepgram":
            return { try await DeepgramClient.listModels(apiKey: $0) }
        case "Soniox":
            return { try await SonioxClient.listModels(apiKey: $0) }
        default:
            return nil
        }
    }

    // MARK: - Storage

    private func save(_ models: [ListedModel], for providerKey: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[providerKey] = Entry(models: models, fetchedAt: Date())
        let snapshot = entries

        // Queued under the lock, so parallel refreshes write their snapshots in the order they were taken. The
        // write itself runs outside the lock, which readers on the main thread wait on.
        storageQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                self.defaults.set(data, forKey: self.storageKey)
            }
        }
    }

    private func beginRefreshing(_ providerKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return refreshingProviders.insert(providerKey).inserted
    }

    private func endRefreshing(_ providerKey: String) {
        lock.lock()
        refreshingProviders.remove(providerKey)
        lock.unlock()
    }
}
