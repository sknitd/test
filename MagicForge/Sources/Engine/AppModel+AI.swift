import Foundation
import MFCore
import MFUtilities
import MFIntegrations

// Optional AI integration. Nothing here runs unless the user triggers it, and nothing is sent
// without the consent step when `confirmBeforeSending` is on.
extension AppModel {
    public var hasAPIKey: Bool {
        _ = apiKeyRevision
        if let cached = cachedHasAPIKey { return cached }
        let present = !storedAPIKey().isEmpty
        cachedHasAPIKey = present
        return present
    }

    public func setAPIKey(_ key: String?) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try services.secrets.setSecret(trimmed.isEmpty ? nil : trimmed, for: AISettings.keychainAccount)
        cachedHasAPIKey = !trimmed.isEmpty
        apiKeyRevision += 1
    }

    private func storedAPIKey() -> String {
        ((try? services.secrets.secret(for: AISettings.keychainAccount)) ?? nil) ?? ""
    }

    /// An empty key is acceptable only for a server on this machine.
    private func keyRequirementMet(_ key: String, settings: AISettings) -> Bool {
        if !key.isEmpty { return true }
        guard let host = URLComponents(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    @discardableResult public func runAITemplate(_ id: UUID) async -> Result<String, AIError> {
        let settings = configuration.ai
        guard settings.isEnabled else { return .failure(.disabled) }
        guard let template = settings.templates.first(where: { $0.id == id }) else {
            return .failure(.notConfigured("The AI prompt no longer exists."))
        }
        // Check server, model and key before touching the user's text.
        do {
            _ = try AIPromptBuilder.request(template: template, input: "check", settings: settings)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.notConfigured(error.localizedDescription))
        }
        let key = storedAPIKey()
        guard keyRequirementMet(key, settings: settings) else { return .failure(.missingAPIKey) }

        // The only place user text is captured, and only because the user triggered this prompt.
        let captured: String?
        switch template.input {
        case .selectedText: captured = await services.textAccess.selectedText()
        case .clipboard: captured = services.textAccess.clipboardString()
        }
        let request: AIRequest
        do {
            request = try AIPromptBuilder.request(template: template, input: captured ?? "", settings: settings)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.notConfigured(error.localizedDescription))
        }

        if settings.confirmBeforeSending {
            // No way to ask means no consent: never send.
            guard let presenter = services.aiPresenter else { return .failure(.declinedByUser) }
            let endpoint = AIPromptBuilder.endpointDescription(for: settings) ?? settings.baseURL
            guard await presenter.confirmSend(text: request.userPrompt, template: template, endpoint: endpoint) else {
                return .failure(.declinedByUser)
            }
        }

        let reply: String
        switch await complete(request, apiKey: key) {
        case .success(let text): reply = text
        case .failure(let error):
            logActivity(.error, "AI prompt “\(template.name)” failed.")
            return .failure(error)
        }
        logActivity(.info, "AI prompt “\(template.name)” finished.")
        await deliver(reply, template: template)
        return .success(reply)
    }

    /// Sends a minimal test request to verify endpoint, model and key. The prompt is fixed
    /// ("Reply with OK"); no user data is included.
    public func testAIConnection() async -> Result<String, AIError> {
        let settings = configuration.ai
        let template = PromptTemplate(name: "Connection test", systemPrompt: "", userPrompt: "{{input}}", input: .clipboard)
        let request: AIRequest
        do {
            request = try AIPromptBuilder.request(template: template, input: "Reply with OK", settings: settings)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.notConfigured(error.localizedDescription))
        }
        let key = storedAPIKey()
        guard keyRequirementMet(key, settings: settings) else { return .failure(.missingAPIKey) }
        return await complete(request, apiKey: key)
    }

    /// Calls the client with a hard deadline slightly beyond the request's own timeout, so a
    /// client that ignores its timeout cannot hang the action.
    private func complete(_ request: AIRequest, apiKey: String) async -> Result<String, AIError> {
        let client = services.ai
        let limit = request.timeout + 2
        do {
            let reply = try await withThrowingTaskGroup(of: String.self) { group -> String in
                group.addTask { try await client.complete(request, apiKey: apiKey) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                    throw AIError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw AIError.badResponse("No answer.") }
                return first
            }
            return .success(reply)
        } catch let error as AIError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.badResponse(error.localizedDescription))
        }
    }

    private func deliver(_ reply: String, template: PromptTemplate) async {
        guard let presenter = services.aiPresenter else {
            services.textAccess.setClipboardString(reply)
            if configuration.settings.notificationsEnabled {
                services.notifier?.notify(title: template.name, body: "The AI result was copied to the clipboard.")
            }
            return
        }
        switch await presenter.presentResult(reply, template: template) {
        case .copy:
            services.textAccess.setClipboardString(reply)
        case .paste:
            let context = ActionContext(source: .manualTest, frontmostBundleID: frontmostBundleID)
            if case .failure(let error) = await route(.text(.pasteText(reply)), context: context, depth: 1) {
                // Keep the result reachable even though pasting failed.
                services.textAccess.setClipboardString(reply)
                logActivity(.warning, "The AI result could not be pasted and was copied instead: \(EngineText.describe(error))")
            }
        case .dismiss:
            break
        }
    }
}
