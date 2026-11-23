import Foundation
import MFCore

/// Plain-text descriptions for the AI screens. No UI types in this file.
enum AIText {
    static func describe(_ error: AIError) -> String {
        switch error {
        case .disabled:
            return "AI integration is turned off."
        case .notConfigured(let what):
            return "Not configured: \(what)"
        case .missingAPIKey:
            return "No API key is stored."
        case .invalidURL:
            return "The base URL is not a valid http(s) address."
        case .http(let status, let message):
            return message.isEmpty ? "The server answered with HTTP \(status)." : "HTTP \(status): \(message)"
        case .timedOut:
            return "The request timed out."
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .cancelled:
            return "Cancelled."
        case .noInput:
            return "There was no text to send (nothing selected or the clipboard is empty)."
        case .declinedByUser:
            return "You chose not to send the request."
        }
    }

    /// Host (and non-default port) of an endpoint string, for the consent panel.
    static func host(ofEndpoint endpoint: String) -> String {
        guard let components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespaces)),
              let host = components.host, !host.isEmpty else { return endpoint }
        if let port = components.port { return "\(host):\(port)" }
        return host
    }

    /// Nil when the base URL looks usable, otherwise what is wrong with it.
    static func baseURLProblem(_ text: String) -> String? {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter the base URL of an OpenAI-compatible API, for example https://api.openai.com/v1" }
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else { return "This is not a valid URL." }
        if scheme == "https" { return nil }
        if scheme == "http" {
            let isLocal: Bool = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
            return isLocal ? nil : "Warning: plain http sends your text and API key unencrypted."
        }
        return "Only http and https URLs are supported."
    }

    static func inputSourceTitle(_ source: AIInputSource) -> String {
        switch source {
        case .selectedText: return "Selected text"
        case .clipboard: return "Clipboard"
        }
    }

    static func uniqueName(_ base: String, existing: [String]) -> String {
        if !existing.contains(base) { return base }
        var number: Int = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
