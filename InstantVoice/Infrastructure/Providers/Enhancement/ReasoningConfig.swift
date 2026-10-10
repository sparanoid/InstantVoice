import Foundation
import LLMkit

struct ReasoningConfig {
    // Gemini 3.8 Flash, 3.7 Flash, and 3.1 Pro Preview do not support "minimal".
    static let geminiLowThinkingModels: Set<String> = [
        "gemini-3.8-flash",
        "gemini-3.7-flash",
        "gemini-3.1-pro-preview",
    ]

    // These models support "minimal", optimized for low-latency instruction following.
    static let geminiMinimalThinkingModels: Set<String> = [
        "gemini-3.6-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
    ]

    // Gemini 2.5 Flash-Lite is intentionally omitted because its Interactions
    // API default has thinking off.
    static func geminiThinkingLevel(for modelName: String) -> GeminiThinkingLevel? {
        if geminiMinimalThinkingModels.contains(modelName) {
            return .minimal
        }
        if geminiLowThinkingModels.contains(modelName) {
            return .low
        }
        return nil
    }

    // These OpenAI models support explicit "none" for low-latency enhancement.
    // GPT-4.1 models need no parameter.
    static let openAINoneReasoningModels: Set<String> = [
        "gpt-6-luna",
        "gpt-6-sol",
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.6-sol",
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
    ]

    // Groq GPT-OSS has no true "none"; use lowest effort.
    static let groqGPTOSSMinimumReasoningModels: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
    ]

    // Groq Qwen supports "none" for non-thinking, low-latency requests.
    static let groqNoneReasoningModels: Set<String> = [
        "qwen/qwen3.8-27b"
    ]

    static func getReasoningParameter(for provider: AIProvider, modelName: String) -> String? {
        switch provider {
        case .openAI:
            if openAINoneReasoningModels.contains(modelName) { return "none" }
        case .groq:
            if groqGPTOSSMinimumReasoningModels.contains(modelName) {
                return "low"
            } else if groqNoneReasoningModels.contains(modelName) {
                return "none"
            }
        default:
            return nil
        }
        return nil
    }

    // OpenAI's reasoning models, the o-series and GPT-5 onward, reject `temperature` unless reasoning
    // effort is "none". Older GPT models take it.
    static func acceptsTemperature(for provider: AIProvider, modelName: String) -> Bool {
        guard provider == .openAI, getReasoningParameter(for: provider, modelName: modelName) != "none" else {
            return true
        }
        let name = modelName.lowercased()
        if name.range(of: #"^o\d"#, options: .regularExpression) != nil { return false }
        guard name.hasPrefix("gpt-"), let version = Int(name.dropFirst("gpt-".count).prefix(while: \.isNumber)) else {
            return true
        }
        return version < 5
    }

    // Provider-specific body params for hiding reasoning.
    static func getExtraBodyParameters(for provider: AIProvider, modelName: String) -> [String: Any]? {
        if provider == .groq && (modelName == "openai/gpt-oss-120b" || modelName == "openai/gpt-oss-20b") {
            return ["include_reasoning": false]
        }
        return nil
    }
}
