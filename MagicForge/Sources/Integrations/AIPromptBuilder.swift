import Foundation
import MFCore

/// Turns a prompt template plus captured text into the exact request that will be sent.
/// The UI shows `AIRequest.userPrompt` for consent, so what the user confirms is what is sent.
public enum AIPromptBuilder {
    public static let inputPlaceholder = "{{input}}"
    /// Captured text longer than this (in characters) is cut and marked as truncated.
    public static let maxInputCharacters = 12_000
    public static let truncationNotice = "\n\n[Input truncated to the first 12,000 characters by MagicForge.]"

    /// - Throws: `AIError.disabled` when AI is off, `.notConfigured` when the base URL or model is
    ///   missing, `.invalidURL` when the base URL is not acceptable, `.noInput` when there is no
    ///   captured text.
    public static func request(template: PromptTemplate, input: String, settings: AISettings) throws -> AIRequest {
        guard settings.isEnabled else { throw AIError.disabled }
        let baseURL = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else { throw AIError.notConfigured("No server address is set.") }
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.notConfigured("No model is set.") }
        _ = try OpenAICompatibleClient.endpointURL(baseURL: baseURL)

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.noInput }
        let text = prepared(trimmed)

        let timeout = settings.timeout.isFinite && settings.timeout > 0
            ? min(settings.timeout, OpenAICompatibleClient.maxTimeout) : OpenAICompatibleClient.defaultTimeout
        return AIRequest(baseURL: baseURL, model: model,
                         systemPrompt: template.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                         userPrompt: userPrompt(template: template.userPrompt, input: text), timeout: timeout)
    }

    /// The endpoint a request will be posted to, for the consent dialog. Nil when the URL is invalid.
    public static func endpointDescription(for settings: AISettings) -> String? {
        try? OpenAICompatibleClient.endpointURL(baseURL: settings.baseURL).absoluteString
    }

    /// True when `input` would be cut by `request(template:input:settings:)`.
    public static func isTruncated(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).count > maxInputCharacters
    }

    static func prepared(_ input: String) -> String {
        guard input.count > maxInputCharacters else { return input }
        return String(input.prefix(maxInputCharacters)) + truncationNotice
    }

    /// Replaces every `{{input}}` (also `{{ input }}`) in one pass, so placeholders inside the
    /// captured text itself are never expanded. A template without a placeholder gets the input
    /// appended, so captured text is never silently dropped.
    static func userPrompt(template: String, input: String) -> String {
        let normalized = template.replacingOccurrences(of: "{{ input }}", with: inputPlaceholder)
        guard normalized.contains(inputPlaceholder) else {
            let instructions = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            return instructions.isEmpty ? input : instructions + "\n\n" + input
        }
        return normalized.components(separatedBy: inputPlaceholder).joined(separator: input)
    }
}
