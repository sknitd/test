import XCTest
import MFCore
import MFUtilities
@testable import MFIntegrations

/// Scripted transport: records requests, replies with a canned response or error. No network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String)
        case failure(Error)
        /// Suspends until cancelled.
        case hang
    }

    private let requests = Locked([HTTPRequestData]())
    private let reply: Reply
    var sent: [HTTPRequestData] { requests.current }

    init(_ reply: Reply) { self.reply = reply }

    func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        requests.withLock { $0.append(request) }
        switch reply {
        case .response(let status, let body):
            return HTTPResponseData(status: status, body: Data(body.utf8))
        case .failure(let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            throw HTTPTransportError.timedOut
        }
    }
}

final class OpenAICompatibleClientTests: XCTestCase {
    private let success = #"{"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":"Hello there"}}]}"#

    private func request(baseURL: String = "https://api.example.com/v1", model: String = "test-model",
                         system: String = "Be brief.", user: String = "Say hi", timeout: Double = 12) -> AIRequest {
        AIRequest(baseURL: baseURL, model: model, systemPrompt: system, userPrompt: user, timeout: timeout)
    }

    private func assertThrows(_ expected: AIError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> String) async {
        do {
            let value = try await body()
            XCTFail("expected \(expected), got \(value)", file: file, line: line)
        } catch let error as AIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error type \(error)", file: file, line: line)
        }
    }

    // MARK: Request shape

    func testRequestShape() async throws {
        let transport = MockTransport(.response(status: 200, body: success))
        let client = OpenAICompatibleClient(transport: transport)
        let result = try await client.complete(request(), apiKey: "sk-test-123")
        XCTAssertEqual(result, "Hello there")

        XCTAssertEqual(transport.sent.count, 1, "exactly one request, no retries")
        let sent = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(sent.url.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.timeout, 12)
        XCTAssertEqual(sent.headers["Authorization"], "Bearer sk-test-123")
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")
        XCTAssertEqual(sent.headers["Accept"], "application/json")
        XCTAssertEqual(Set(sent.headers.keys), ["Authorization", "Content-Type", "Accept"])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["model", "messages", "stream"])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "Be brief."], ["role": "user", "content": "Say hi"]])
        XCTAssertFalse(String(decoding: sent.body, as: UTF8.self).contains("sk-test-123"), "the key is never in the body")
    }

    func testSystemMessageOmittedWhenEmptyAndSpecialCharactersSurvive() async throws {
        let transport = MockTransport(.response(status: 200, body: success))
        let prompt = "Quote \"this\" \\ and\nnewline, emoji 🙂, </script> {{input}}"
        _ = try await OpenAICompatibleClient(transport: transport).complete(request(system: "  \n", user: prompt), apiKey: "k")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(transport.sent.first).body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": prompt]])
    }

    func testEmptyKeyOmitsAuthorizationHeader() async throws {
        let transport = MockTransport(.response(status: 200, body: success))
        _ = try await OpenAICompatibleClient(transport: transport)
            .complete(request(baseURL: "http://localhost:11434/v1"), apiKey: "  ")
        XCTAssertNil(transport.sent.first?.headers["Authorization"])
        XCTAssertEqual(transport.sent.first?.url.absoluteString, "http://localhost:11434/v1/chat/completions")
    }

    func testKeyWithControlCharactersIsRejectedBeforeSending() async {
        let transport = MockTransport(.response(status: 200, body: success))
        let client = OpenAICompatibleClient(transport: transport)
        await assertThrows(.notConfigured("The API key contains invalid characters.")) {
            try await client.complete(self.request(), apiKey: "abc\r\nX-Injected: 1")
        }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testTimeoutIsSanitized() throws {
        XCTAssertEqual(try OpenAICompatibleClient.httpRequest(for: request(timeout: 0), apiKey: "k").timeout, 30)
        XCTAssertEqual(try OpenAICompatibleClient.httpRequest(for: request(timeout: .nan), apiKey: "k").timeout, 30)
        XCTAssertEqual(try OpenAICompatibleClient.httpRequest(for: request(timeout: 1e9), apiKey: "k").timeout, 600)
        XCTAssertEqual(try OpenAICompatibleClient.httpRequest(for: request(timeout: 5), apiKey: "k").timeout, 5)
    }

    // MARK: URL handling

    func testURLJoining() throws {
        let cases: [(String, String)] = [
            ("https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions"),
            ("https://api.openai.com/v1/", "https://api.openai.com/v1/chat/completions"),
            ("https://api.openai.com/v1///", "https://api.openai.com/v1/chat/completions"),
            ("  https://api.openai.com/v1\n", "https://api.openai.com/v1/chat/completions"),
            ("https://example.com", "https://example.com/chat/completions"),
            ("https://example.com/", "https://example.com/chat/completions"),
            ("HTTPS://Example.com/api/openai", "https://Example.com/api/openai/chat/completions"),
            ("https://example.com:8443/proxy/v1", "https://example.com:8443/proxy/v1/chat/completions"),
            ("https://gw.example.com/openai?api-version=2024-02-01",
             "https://gw.example.com/openai/chat/completions?api-version=2024-02-01"),
            ("http://localhost:1234/v1", "http://localhost:1234/v1/chat/completions"),
            ("http://127.0.0.1:11434", "http://127.0.0.1:11434/chat/completions"),
            ("http://[::1]:8080/v1/", "http://[::1]:8080/v1/chat/completions"),
        ]
        for (base, expected) in cases {
            XCTAssertEqual(try OpenAICompatibleClient.endpointURL(baseURL: base).absoluteString, expected, base)
        }
    }

    func testURLValidation() async {
        let invalid = [
            "", "   ", "api.openai.com/v1", "ftp://example.com/v1", "file:///etc/passwd", "javascript:alert(1)",
            "http://example.com/v1", "http://192.168.1.10:8080/v1", "http://localhost.evil.com/v1",
            "http://127.0.0.1.evil.com", "https://", "https:///v1", "https://user:pass@example.com/v1",
            "https://example.com/v1#frag", "https://exa mple.com/v1", "ws://localhost:1234",
        ]
        for base in invalid {
            XCTAssertThrowsError(try OpenAICompatibleClient.endpointURL(baseURL: base), base) { error in
                XCTAssertEqual(error as? AIError, .invalidURL, base)
            }
        }
        let transport = MockTransport(.response(status: 200, body: success))
        let client = OpenAICompatibleClient(transport: transport)
        await assertThrows(.invalidURL) { try await client.complete(self.request(baseURL: "http://example.com/v1"), apiKey: "k") }
        XCTAssertTrue(transport.sent.isEmpty, "nothing is sent to a rejected URL")
    }

    func testMissingModelAndPrompt() async {
        let transport = MockTransport(.response(status: 200, body: success))
        let client = OpenAICompatibleClient(transport: transport)
        await assertThrows(.notConfigured("No model is set.")) { try await client.complete(self.request(model: " "), apiKey: "k") }
        await assertThrows(.noInput) { try await client.complete(self.request(user: "\n "), apiKey: "k") }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: Responses

    private func complete(_ reply: MockTransport.Reply, timeout: Double = 12) async throws -> String {
        try await OpenAICompatibleClient(transport: MockTransport(reply)).complete(request(timeout: timeout), apiKey: "k")
    }

    func testSuccessParsing() async throws {
        let multiple = #"{"choices":[{"message":{"content":"first\nline"}},{"message":{"content":"second"}}],"usage":{"total_tokens":3}}"#
        let first = try await complete(.response(status: 200, body: multiple))
        XCTAssertEqual(first, "first\nline")
        let created = try await complete(.response(status: 201, body: success))
        XCTAssertEqual(created, "Hello there")
    }

    func testBadResponses() async {
        let bodies = [
            "", "not json", "<html>502</html>", "[]", "{}", #"{"choices":[]}"#, #"{"choices":[{"message":{}}]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#, #"{"choices":[{"message":{"content":"  "}}]}"#,
            #"{"choices":[{"text":"legacy"}]}"#, #"{"choices":"nope"}"#,
        ]
        for body in bodies {
            do {
                let value = try await complete(.response(status: 200, body: body))
                XCTFail("expected badResponse for \(body), got \(value)")
            } catch let error as AIError {
                guard case .badResponse(let message) = error else { XCTFail("\(error) for \(body)"); continue }
                XCTAssertFalse(message.isEmpty)
            } catch {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testHTTPErrorMapping() async {
        await assertThrows(.http(status: 401, message: "Incorrect API key provided.")) {
            try await self.complete(.response(status: 401, body: #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error"}}"#))
        }
        await assertThrows(.http(status: 404, message: "model not found")) {
            try await self.complete(.response(status: 404, body: #"{"error":"model not found"}"#))
        }
        await assertThrows(.http(status: 429, message: "Slow down")) {
            try await self.complete(.response(status: 429, body: #"{"message":"Slow down"}"#))
        }
        await assertThrows(.http(status: 502, message: "Bad Gateway upstream")) {
            try await self.complete(.response(status: 502, body: "Bad Gateway\nupstream"))
        }
        await assertThrows(.http(status: 500, message: "")) { try await self.complete(.response(status: 500, body: "")) }
        await assertThrows(.http(status: 302, message: "")) { try await self.complete(.response(status: 302, body: "")) }
        let long = String(repeating: "x", count: 5000)
        await assertThrows(.http(status: 500, message: String(repeating: "x", count: 300) + "…")) {
            try await self.complete(.response(status: 500, body: long))
        }
        // A 4xx body that happens to look like a success is still an error.
        await assertThrows(.http(status: 400, message: success)) { try await self.complete(.response(status: 400, body: self.success)) }
    }

    func testTransportErrorMapping() async {
        await assertThrows(.timedOut) { try await self.complete(.failure(HTTPTransportError.timedOut)) }
        await assertThrows(.cancelled) { try await self.complete(.failure(HTTPTransportError.cancelled)) }
        await assertThrows(.cancelled) { try await self.complete(.failure(CancellationError())) }
        await assertThrows(.badResponse("Could not reach the server: offline")) {
            try await self.complete(.failure(HTTPTransportError.network("offline")))
        }
        struct Odd: Error {}
        await assertThrows(.badResponse("Could not reach the server.")) { try await self.complete(.failure(Odd())) }
    }

    func testOverallTimeoutIsEnforcedEvenIfTransportHangs() async {
        let started = Date()
        await assertThrows(.timedOut) { try await self.complete(.hang, timeout: 0.15) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testCancellation() async {
        let transport = MockTransport(.hang)
        let client = OpenAICompatibleClient(transport: transport)
        let request = request(timeout: 30)
        let task = Task { try await client.complete(request, apiKey: "k") }
        let deadline = Date().addingTimeInterval(5)
        while transport.sent.isEmpty, Date() < deadline { try? await Task.sleep(nanoseconds: 2_000_000) }
        task.cancel()
        do {
            let value = try await task.value
            XCTFail("expected cancellation, got \(value)")
        } catch {
            XCTAssertEqual(error as? AIError, .cancelled)
        }
    }

    func testAlreadyCancelledTaskSendsNothing() async {
        let transport = MockTransport(.response(status: 200, body: success))
        let client = OpenAICompatibleClient(transport: transport)
        let request = request()
        let task = Task { () -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.complete(request, apiKey: "k")
        }
        do { _ = try await task.value; XCTFail("expected cancellation") } catch { XCTAssertEqual(error as? AIError, .cancelled) }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testDefaultInitializerBuildsURLSessionTransport() {
        // Construction only: no request is made (the test machine has no network access to rely on).
        _ = OpenAICompatibleClient()
        _ = URLSessionTransport()
    }
}
