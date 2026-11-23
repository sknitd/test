import XCTest
import MFCore
import MFUtilities
@testable import MFEngine

final class AIFlowTests: XCTestCase {
    private let template = PromptTemplate(name: "Fix grammar", systemPrompt: "You are an editor.",
                                          userPrompt: "Fix: {{input}}", input: .clipboard)

    @MainActor private func makeHarness(enabled: Bool = true, baseURL: String = "https://ai.example.com/v1",
                                        confirm: Bool = true, key: String? = "sk-test",
                                        withPresenter: Bool = true, input: AIInputSource = .clipboard) -> Harness {
        var prompt = template
        prompt.input = input
        let binding = GestureBinding(trigger: .single(.twoFingerTap), action: .ai(templateID: template.id))
        let configuration = TestConfig.with([binding]) { configuration in
            configuration.ai.isEnabled = enabled
            configuration.ai.baseURL = baseURL
            configuration.ai.model = "test-model"
            configuration.ai.confirmBeforeSending = confirm
            configuration.ai.templates = [prompt]
        }
        let harness = Harness(configuration: configuration, withAIPresenter: withPresenter)
        if let key { harness.secrets.values[AISettings.keychainAccount] = key }
        harness.text.clipboard = "teh text"
        harness.text.selection = "selected words"
        harness.model.start()
        return harness
    }

    @MainActor func testDisabledSendsNothingAndReadsNothing() async {
        let harness = makeHarness(enabled: false)
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .disabled)
        XCTAssertTrue(harness.ai.calls.isEmpty)
        XCTAssertEqual(harness.text.clipboardReads, 0, "no text is captured for a refused request")
        let test = await harness.model.testAIConnection()
        XCTAssertEqual(test.failureValue, .disabled)
        guard case .unavailable = harness.model.availability(of: .ai(templateID: template.id)) else {
            return XCTFail("AI off means unavailable")
        }
        harness.model.stop()
    }

    @MainActor func testMissingKey() async {
        let harness = makeHarness(key: nil)
        XCTAssertFalse(harness.model.hasAPIKey)
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .missingAPIKey)
        XCTAssertTrue(harness.ai.calls.isEmpty)
        XCTAssertEqual(harness.text.clipboardReads, 0)
        XCTAssertTrue(harness.aiPresenter.confirmations.isEmpty)

        try? harness.model.setAPIKey("  sk-new  ")
        XCTAssertTrue(harness.model.hasAPIKey)
        XCTAssertEqual(harness.secrets.values[AISettings.keychainAccount], "sk-new")
        try? harness.model.setAPIKey(nil)
        XCTAssertFalse(harness.model.hasAPIKey)
        XCTAssertNil(harness.secrets.values[AISettings.keychainAccount])
        harness.model.stop()
    }

    @MainActor func testLocalServerNeedsNoKey() async {
        let harness = makeHarness(baseURL: "http://localhost:11434/v1", key: nil)
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(try? result.get(), "AI reply")
        XCTAssertEqual(harness.ai.calls.first?.apiKey, "")
        harness.model.stop()
    }

    @MainActor func testNotConfiguredAndUnknownTemplate() async {
        let harness = makeHarness(baseURL: "")
        let result = await harness.model.runAITemplate(template.id)
        guard case .notConfigured = result.failureValue else { return XCTFail("expected notConfigured") }
        let unknown = await harness.model.runAITemplate(UUID())
        guard case .notConfigured = unknown.failureValue else { return XCTFail("expected notConfigured") }
        XCTAssertTrue(harness.ai.calls.isEmpty)
        harness.model.stop()
    }

    @MainActor func testNoInput() async {
        let harness = makeHarness()
        harness.text.clipboard = "   "
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .noInput)
        XCTAssertTrue(harness.ai.calls.isEmpty)
        harness.model.stop()
    }

    @MainActor func testDeclinedConsentNeverCallsTheClient() async {
        let harness = makeHarness()
        harness.aiPresenter.allowSending = false
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .declinedByUser)
        XCTAssertTrue(harness.ai.calls.isEmpty, "nothing is sent without consent")
        XCTAssertEqual(harness.aiPresenter.confirmations.first?.text, "Fix: teh text", "the user sees exactly what would be sent")
        XCTAssertEqual(harness.aiPresenter.confirmations.first?.endpoint, "https://ai.example.com/v1/chat/completions")

        // As an action, declining is a cancellation, not a failure.
        let action = await harness.model.run(.ai(templateID: template.id), source: .manualTest)
        XCTAssertEqual(action.failureValue, .cancelled)
        XCTAssertEqual(harness.model.metrics.actionFailures, 0)
        XCTAssertTrue(harness.ai.calls.isEmpty)
        harness.model.stop()
    }

    @MainActor func testConfirmationRequiredButNoPresenterNeverSends() async {
        let harness = makeHarness(withPresenter: false)
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .declinedByUser)
        XCTAssertTrue(harness.ai.calls.isEmpty)
        harness.model.stop()
    }

    @MainActor func testSuccessWithConsentAndPaste() async {
        let harness = makeHarness()
        harness.aiPresenter.choice = .paste
        harness.perform(.twoFingerTap)
        await harness.wait("AI call") { harness.ai.calls.count == 1 }
        await harness.wait("paste") { harness.performer.performed.count == 1 }

        let call = harness.ai.calls[0]
        XCTAssertEqual(call.apiKey, "sk-test")
        XCTAssertEqual(call.request.userPrompt, "Fix: teh text")
        XCTAssertEqual(call.request.systemPrompt, "You are an editor.")
        XCTAssertEqual(call.request.model, "test-model")
        XCTAssertEqual(harness.aiPresenter.presentedResults, ["AI reply"])
        XCTAssertEqual(harness.performer.performed, [.text(.pasteText("AI reply"))])
        await harness.wait("counted") { harness.model.metrics.actionsExecuted == 1 }
        harness.model.stop()
    }

    @MainActor func testCopyChoiceAndSelectedTextInput() async {
        let harness = makeHarness(input: .selectedText)
        harness.aiPresenter.choice = .copy
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(try? result.get(), "AI reply")
        XCTAssertEqual(harness.text.selectionReads, 1)
        XCTAssertEqual(harness.ai.calls.first?.request.userPrompt, "Fix: selected words")
        XCTAssertEqual(harness.text.clipboard, "AI reply")
        XCTAssertTrue(harness.performer.performed.isEmpty)
        harness.model.stop()
    }

    @MainActor func testWithoutPresenterResultIsCopiedAndAnnounced() async {
        let harness = makeHarness(confirm: false, withPresenter: false)
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(try? result.get(), "AI reply")
        XCTAssertEqual(harness.text.clipboard, "AI reply")
        XCTAssertEqual(harness.notifier.notifications.count, 1)
        harness.model.stop()
    }

    @MainActor func testServerErrorIsReturned() async {
        let harness = makeHarness(confirm: false)
        harness.ai.result = .failure(.http(status: 401, message: "bad key"))
        let result = await harness.model.runAITemplate(template.id)
        XCTAssertEqual(result.failureValue, .http(status: 401, message: "bad key"))
        XCTAssertTrue(harness.aiPresenter.presentedResults.isEmpty)
        let action = await harness.model.run(.ai(templateID: template.id), source: .manualTest)
        guard case .failed = action.failureValue else { return XCTFail("expected failed") }
        XCTAssertEqual(harness.model.metrics.actionFailures, 1)
        harness.model.stop()
    }

    @MainActor func testConnectionTestSendsOnlyTheFixedPrompt() async {
        let harness = makeHarness()
        harness.ai.result = .success("OK")
        let result = await harness.model.testAIConnection()
        XCTAssertEqual(try? result.get(), "OK")
        XCTAssertEqual(harness.ai.calls.count, 1)
        XCTAssertEqual(harness.ai.calls.first?.request.userPrompt, "Reply with OK")
        XCTAssertEqual(harness.ai.calls.first?.request.systemPrompt, "")
        XCTAssertEqual(harness.text.clipboardReads, 0, "no user data is read")
        XCTAssertEqual(harness.text.selectionReads, 0)
        XCTAssertTrue(harness.aiPresenter.confirmations.isEmpty)
        harness.model.stop()
    }
}
