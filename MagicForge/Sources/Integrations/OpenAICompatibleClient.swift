import Foundation
import MFCore

/// Chat-completions client for OpenAI-compatible servers (OpenAI, Azure-style gateways, Ollama,
/// LM Studio, …). Sends exactly one POST per `complete` call, never retries, and never logs
/// prompts, responses or API keys.
public final class OpenAICompatibleClient: AICompleting {
    /// Used when the request's timeout is not a positive finite number.
    public static let defaultTimeout: TimeInterval = 30
    public static let maxTimeout: TimeInterval = 600
    /// Longest server error text kept in `AIError.http`.
    public static let maxErrorMessageLength = 300

    private let transport: HTTPTransport

    public init() { transport = URLSessionTransport() }
    public init(transport: HTTPTransport) { self.transport = transport }

    // MARK: Endpoint

    /// `{baseURL}/chat/completions`. The base URL is used as given (with or without `/v1`);
    /// trailing slashes are ignored and a query string is preserved. Only `https` is accepted,
    /// plus plain `http` for this machine (`localhost`, `127.0.0.1`, `::1`).
    /// URLs with embedded credentials or fragments are rejected.
    public static func endpointURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 }),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              var host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil
        else { throw AIError.invalidURL }

        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        switch scheme {
        case "https":
            break
        case "http":
            guard ["localhost", "127.0.0.1", "::1"].contains(host) else { throw AIError.invalidURL }
        default:
            throw AIError.invalidURL
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.scheme = scheme
        components.path = path + "/chat/completions"
        guard let url = components.url else { throw AIError.invalidURL }
        return url
    }

    // MARK: AICompleting

    /// - Parameter apiKey: Sent as `Authorization: Bearer <key>`. When empty (local servers that
    ///   need no key) the header is omitted.
    public func complete(_ request: AIRequest, apiKey: String) async throws -> String {
        let httpRequest = try Self.httpRequest(for: request, apiKey: apiKey)
        try Task.checkCancellation(orThrow: AIError.cancelled)

        let response: HTTPResponseData
        do {
            response = try await send(httpRequest)
        } catch let error as AIError {
            throw error
        } catch let error as HTTPTransportError {
            switch error {
            case .timedOut: throw AIError.timedOut
            case .cancelled: throw AIError.cancelled
            case .network(let message): throw AIError.badResponse("Could not reach the server: \(message)")
            }
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.badResponse("Could not reach the server.")
        }

        guard (200..<300).contains(response.status) else {
            throw AIError.http(status: response.status, message: Self.errorMessage(from: response.body))
        }
        return try Self.content(from: response.body)
    }

    // MARK: Request building

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        var model: String
        var messages: [Message]
        var stream = false
    }

    static func httpRequest(for request: AIRequest, apiKey: String) throws -> HTTPRequestData {
        let url = try endpointURL(baseURL: request.baseURL)
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.notConfigured("No model is set.") }
        guard !request.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.noInput }

        var messages: [ChatRequest.Message] = []
        if !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.init(role: "system", content: request.systemPrompt))
        }
        messages.append(.init(role: "user", content: request.userPrompt))

        let body: Data
        do {
            body = try JSONEncoder().encode(ChatRequest(model: model, messages: messages))
        } catch {
            throw AIError.badResponse("The request could not be encoded.")
        }

        var headers = ["Content-Type": "application/json", "Accept": "application/json"]
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            // A key with control characters or non-ASCII text cannot be a valid header value.
            guard key.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else {
                throw AIError.notConfigured("The API key contains invalid characters.")
            }
            headers["Authorization"] = "Bearer \(key)"
        }

        let timeout = request.timeout.isFinite && request.timeout > 0 ? min(request.timeout, maxTimeout) : defaultTimeout
        return HTTPRequestData(url: url, method: "POST", headers: headers, body: body, timeout: timeout)
    }

    /// Runs the transport with a hard overall deadline (URLSession's own timeout only covers idle time).
    private func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        let transport = self.transport
        return try await withThrowingTaskGroup(of: HTTPResponseData?.self) { group in
            group.addTask { try await transport.send(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(request.timeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            do {
                guard let first = try await group.next(), let response = first else { throw AIError.timedOut }
                return response
            } catch is CancellationError {
                throw AIError.cancelled
            }
        }
    }

    // MARK: Response parsing

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message?
        }
        var choices: [Choice]?
    }

    static func content(from body: Data) throws -> String {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: body)
        } catch {
            throw AIError.badResponse("The server's reply was not valid JSON in the expected format.")
        }
        guard let choice = decoded.choices?.first else { throw AIError.badResponse("The server's reply contained no choices.") }
        guard let content = choice.message?.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.badResponse("The server's reply contained no text.")
        }
        return content
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
        var message: String?

        private enum CodingKeys: String, CodingKey { case error, message }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try? container.decode(String.self, forKey: .message)
            if let detail = try? container.decode(Detail.self, forKey: .error) {
                error = detail
            } else if let text = try? container.decode(String.self, forKey: .error) {
                error = Detail(message: text)
            }
        }
    }

    /// The server's own error text (`error.message`, `error` or `message`), else the start of the body.
    static func errorMessage(from body: Data) -> String {
        var message = ""
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body) {
            message = envelope.error?.message ?? envelope.message ?? ""
        }
        if message.isEmpty, let text = String(data: body.prefix(4096), encoding: .utf8) { message = text }
        message = message.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if message.count > maxErrorMessageLength { message = String(message.prefix(maxErrorMessageLength)) + "…" }
        return message
    }
}

private extension Task where Success == Never, Failure == Never {
    static func checkCancellation(orThrow error: Error) throws {
        if Task.isCancelled { throw error }
    }
}
