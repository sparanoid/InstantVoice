import Foundation
import LLMkit

/// Picks the fetched models that fit each use. `ListedModelKind` reads model kinds from provider ID
/// conventions where the list endpoints don't say what a model is for.
enum ProviderModelFilters {
    /// Every chat model the provider lists, under its own ID, including dated snapshots and deprecated models.
    /// Newest first when the provider dates its models.
    static func enhancementModels(_ models: [ListedModel], for provider: AIProvider) -> [String] {
        switch provider {
        case .openAI:
            return newestFirst(models.filter { ListedModelKind.isOpenAIChatModel($0.id) }).map(\.id)
        case .groq:
            return newestFirst(models.filter { ListedModelKind.isGroqChatModel($0.id) }).map(\.id)
        case .anthropic:
            return newestFirst(models).map(\.id)
        case .gemini:
            // Gemini doesn't date its models, so higher versions go first.
            return models.filter(ListedModelKind.isGeminiChatModel).map(\.id)
                .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        default:
            return []
        }
    }

    /// Newest first when every model has a date; otherwise the provider's order.
    private static func newestFirst(_ models: [ListedModel]) -> [ListedModel] {
        guard models.allSatisfy({ $0.createdAt != nil }) else { return models }
        return models.enumerated()
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.createdAt!, rhsDate = rhs.element.createdAt!
                return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
