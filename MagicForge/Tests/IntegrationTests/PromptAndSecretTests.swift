import XCTest
import MFCore
@testable import MFIntegrations

final class AIPromptBuilderTests: XCTestCase {
    private func settings(_ configure: (inout AISettings) -> Void = { _ in }) -> AISettings {
        var settings = AISettings()
        settings.isEnabled = true
        settings.baseURL = "https://api.example.com/v1"
        settings.model = "test-model"
        settings.timeout = 20
        configure(&settings)
        return settings
    }

    private func assertThrows(_ expected: AIError, template: PromptTemplate = PromptTemplate(name: "T"), input: String = "text",
                              settings: AISettings, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AIPromptBuilder.request(template: template, input: input, settings: settings),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? AIError, expected, file: file, line: line)
        }
    }

    func testBuildsRequest() throws {
        let template = PromptTemplate(name: "Fix", systemPrompt: "  You fix grammar.\n", userPrompt: "Fix this:\n{{input}}\nThanks")
        let request = try AIPromptBuilder.request(template: template, input: "  teh cat \n", settings: settings())
        XCTAssertEqual(request, AIRequest(baseURL: "https://api.example.com/v1", model: "test-model",
                                          systemPrompt: "You fix grammar.", userPrompt: "Fix this:\nteh cat\nThanks", timeout: 20))
    }

    func testSubstitution() {
        XCTAssertEqual(AIPromptBuilder.userPrompt(template: "{{input}}", input: "abc"), "abc")
        XCTAssertEqual(AIPromptBuilder.userPrompt(template: "A {{input}} B {{ input }} C", input: "x"), "A x B x C")
        // Placeholders inside the captured text are not expanded again.
        XCTAssertEqual(AIPromptBuilder.userPrompt(template: "<{{input}}>", input: "{{input}} & {{input}}"),
                       "<{{input}} & {{input}}>")
        // Without a placeholder the input is appended rather than dropped.
        XCTAssertEqual(AIPromptBuilder.userPrompt(template: "Summarize:", input: "abc"), "Summarize:\n\nabc")
        XCTAssertEqual(AIPromptBuilder.userPrompt(template: "  ", input: "abc"), "abc")
        // The system prompt is never substituted.
        let template = PromptTemplate(name: "T", systemPrompt: "sys {{input}}", userPrompt: "{{input}}")
        XCTAssertEqual(try AIPromptBuilder.request(template: template, input: "x", settings: settings()).systemPrompt, "sys {{input}}")
    }

    func testValidation() {
        assertThrows(.disabled, settings: settings { $0.isEnabled = false })
        assertThrows(.disabled, settings: AISettings())
        assertThrows(.notConfigured("No server address is set."), settings: settings { $0.baseURL = "  " })
        assertThrows(.notConfigured("No model is set."), settings: settings { $0.model = "" })
        assertThrows(.invalidURL, settings: settings { $0.baseURL = "http://example.com/v1" })
        assertThrows(.invalidURL, settings: settings { $0.baseURL = "not a url" })
        assertThrows(.noInput, input: "", settings: settings())
        assertThrows(.noInput, input: " \n\t ", settings: settings())
        // Disabled wins over everything else: nothing is examined when AI is off.
        assertThrows(.disabled, input: "", settings: settings { $0.isEnabled = false; $0.baseURL = "" })
    }

    func testInputTruncation() throws {
        let limit = AIPromptBuilder.maxInputCharacters
        let exact = String(repeating: "a", count: limit)
        let fits = try AIPromptBuilder.request(template: PromptTemplate(name: "T"), input: exact, settings: settings())
        XCTAssertEqual(fits.userPrompt, exact)
        XCTAssertFalse(AIPromptBuilder.isTruncated(exact))

        let long = exact + "TAIL-THAT-MUST-NOT-BE-SENT"
        XCTAssertTrue(AIPromptBuilder.isTruncated(long))
        let cut = try AIPromptBuilder.request(template: PromptTemplate(name: "T", userPrompt: "[{{input}}]"), input: long,
                                              settings: settings())
        XCTAssertEqual(cut.userPrompt, "[" + exact + AIPromptBuilder.truncationNotice + "]")
        XCTAssertFalse(cut.userPrompt.contains("TAIL"))

        // Counted in characters, so multi-scalar emoji are never split.
        let emoji = String(repeating: "👨‍👩‍👧", count: limit + 5)
        let emojiRequest = try AIPromptBuilder.request(template: PromptTemplate(name: "T"), input: emoji, settings: settings())
        XCTAssertEqual(emojiRequest.userPrompt, String(repeating: "👨‍👩‍👧", count: limit) + AIPromptBuilder.truncationNotice)
    }

    func testTimeoutAndEndpoint() throws {
        let template = PromptTemplate(name: "T")
        XCTAssertEqual(try AIPromptBuilder.request(template: template, input: "x", settings: settings { $0.timeout = -1 }).timeout, 30)
        XCTAssertEqual(try AIPromptBuilder.request(template: template, input: "x", settings: settings { $0.timeout = 9999 }).timeout, 600)
        XCTAssertEqual(AIPromptBuilder.endpointDescription(for: settings()), "https://api.example.com/v1/chat/completions")
        XCTAssertNil(AIPromptBuilder.endpointDescription(for: settings { $0.baseURL = "http://example.com" }))
    }

    func testBuiltRequestIsAcceptedByClient() async throws {
        let transport = MockTransport(.response(status: 200, body: #"{"choices":[{"message":{"content":"ok"}}]}"#))
        let request = try AIPromptBuilder.request(template: PromptTemplate(name: "T", userPrompt: "Translate: {{input}}"),
                                                  input: "hola", settings: settings { $0.baseURL = "https://api.example.com/v1/ " })
        let result = try await OpenAICompatibleClient(transport: transport).complete(request, apiKey: "key")
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(transport.sent.first?.url.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertTrue(String(decoding: transport.sent.first?.body ?? Data(), as: UTF8.self).contains("Translate: hola"))
    }
}

final class InMemorySecretStoreTests: XCTestCase {
    func testStoreUpdateDelete() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.secret(for: AISettings.keychainAccount))
        try store.setSecret("one", for: AISettings.keychainAccount)
        XCTAssertEqual(try store.secret(for: AISettings.keychainAccount), "one")
        try store.setSecret("two", for: AISettings.keychainAccount)
        XCTAssertEqual(try store.secret(for: AISettings.keychainAccount), "two")
        XCTAssertNil(try store.secret(for: "other"))
        try store.setSecret(nil, for: AISettings.keychainAccount)
        XCTAssertNil(try store.secret(for: AISettings.keychainAccount))
        try store.setSecret(nil, for: "never-existed")
    }

    func testEmptyStringRemovesAndAccountsAreIndependent() throws {
        let store = InMemorySecretStore(["a": "1", "b": "2"])
        try store.setSecret("", for: "a")
        XCTAssertNil(try store.secret(for: "a"))
        XCTAssertEqual(try store.secret(for: "b"), "2")
    }

    func testConcurrentAccess() async throws {
        let store = InMemorySecretStore()
        let box = UncheckedBox(store)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    try? box.value.setSecret("v\(index)", for: "k\(index % 10)")
                    _ = try? box.value.secret(for: "k\(index % 10)")
                }
            }
        }
        for index in 0..<10 { XCTAssertNotNil(try store.secret(for: "k\(index)")) }
    }

    func testUsableAsSecretStoring() throws {
        let store: SecretStoring = InMemorySecretStore()
        try store.setSecret("x", for: "y")
        XCTAssertEqual(try store.secret(for: "y"), "x")
    }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
