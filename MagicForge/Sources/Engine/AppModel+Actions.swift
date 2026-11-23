import Foundation
import MFCore
import MFUtilities
import MFProfiles
import MFAutomation

// Action routing: leaf actions, workflows, radial menus, AI prompts and control actions.
extension AppModel {
    public func availability(of action: Action) -> ActionAvailability {
        switch action {
        case .none:
            return .available
        case .system, .window, .app, .keyboard, .mouse, .text, .script:
            return services.performer.availability(of: action)
        case .workflow(let id):
            return configuration.workflows.contains { $0.id == id }
                ? .available : .unavailable(reason: "The workflow no longer exists.")
        case .radialMenu(let id):
            guard configuration.radialMenus.contains(where: { $0.id == id }) else {
                return .unavailable(reason: "The radial menu no longer exists.")
            }
            return services.radialMenu == nil
                ? .unavailable(reason: "Radial menus cannot be shown in this build.") : .available
        case .ai(let templateID):
            guard configuration.ai.isEnabled else { return .unavailable(reason: "AI is turned off.") }
            return configuration.ai.templates.contains { $0.id == templateID }
                ? .available : .unavailable(reason: "The AI prompt no longer exists.")
        case .control(let control):
            if control == .openDashboard, services.openDashboard == nil {
                return .unavailable(reason: "The main window cannot be opened in this build.")
            }
            return .available
        }
    }

    /// Runs any action (leaf or routed). Never throws; failures are returned and logged.
    @discardableResult public func run(_ action: Action, source: ActionSource) async -> Result<Void, ActionError> {
        await runTopLevel(action, context: ActionContext(source: source, frontmostBundleID: frontmostBundleID))
    }

    /// One user-visible execution: routes the action, then counts and logs the outcome once.
    func runTopLevel(_ action: Action, context: ActionContext) async -> Result<Void, ActionError> {
        if case .none = action { return .success(()) }
        let name = action.displayName(in: configuration)
        let result = await route(action, context: context, depth: 0)
        switch result {
        case .success:
            metrics.actionsExecuted += 1
        case .failure(.cancelled):
            logActivity(.info, "“\(name)” was cancelled.")
        case .failure(let error):
            metrics.actionFailures += 1
            logActivity(.error, "“\(name)” failed: \(EngineText.describe(error))")
            if case .permissionDenied = error { refreshPermissions() }
        }
        return result
    }

    /// Executes without counting or logging; used for nested actions too.
    func route(_ action: Action, context: ActionContext, depth: Int) async -> Result<Void, ActionError> {
        guard depth <= AppModel.maxRoutingDepth else {
            return .failure(.failed("Too many actions are nested inside each other."))
        }
        switch action {
        case .none:
            return .success(())
        case .system, .window, .app, .keyboard, .mouse, .text, .script:
            return await performLeaf(action, context: context)
        case .workflow(let id):
            return await runWorkflow(id, context: context)
        case .radialMenu(let id):
            return await presentRadialMenu(id, context: context, depth: depth)
        case .ai(let templateID):
            switch await runAITemplate(templateID) {
            case .success: return .success(())
            case .failure(let error): return .failure(AppModel.actionError(from: error))
            }
        case .control(let control):
            return runControl(control)
        }
    }

    private func performLeaf(_ action: Action, context: ActionContext) async -> Result<Void, ActionError> {
        // Trust first: an unapproved script never reaches the performer.
        if let script = action.script, !ScriptTrust.isTrusted(script, in: configuration) {
            return .failure(.untrusted)
        }
        let performer = services.performer
        do {
            try await performer.perform(action, context: context)
            return .success(())
        } catch let error as ActionError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    // MARK: Radial menus

    public func showRadialMenu(_ id: UUID) {
        Task { [weak self] in
            _ = await self?.run(.radialMenu(id: id), source: .radialMenu)
        }
    }

    private func presentRadialMenu(_ id: UUID, context: ActionContext, depth: Int) async -> Result<Void, ActionError> {
        guard let menu = configuration.radialMenus.first(where: { $0.id == id }) else {
            return .failure(.notFound("The radial menu"))
        }
        guard let presenter = services.radialMenu else {
            return .failure(.unsupported("Radial menus cannot be shown in this build."))
        }
        let recent = menu.theme.showRecentActions ? recentRadialItems : []
        guard let item = await presenter.present(menu, recent: recent) else { return .success(()) }
        // An item with children opens a submenu; its own action is ignored by definition.
        guard item.children.isEmpty, item.action != .none else { return .success(()) }
        recentRadialItems.removeAll { $0.id == item.id }
        recentRadialItems.insert(item, at: 0)
        if recentRadialItems.count > AppModel.recentRadialItemLimit {
            recentRadialItems.removeLast(recentRadialItems.count - AppModel.recentRadialItemLimit)
        }
        var itemContext = context
        itemContext.source = .radialMenu
        return await route(item.action, context: itemContext, depth: depth + 1)
    }

    // MARK: Control actions

    private func runControl(_ control: ControlAction) -> Result<Void, ActionError> {
        switch control {
        case .toggleGesturesPaused:
            setPaused(!isPaused)
        case .openDashboard:
            guard let open = services.openDashboard else {
                return .failure(.unsupported("The main window cannot be opened in this build."))
            }
            open()
        case .nextProfile:
            let candidates = configuration.profiles.filter { $0.isEnabled || $0.id == configuration.globalProfileID }
            guard candidates.count > 1 else { return .success(()) }
            let index = candidates.firstIndex { $0.id == activeProfileID } ?? -1
            setProfileOverride(candidates[(index + 1) % candidates.count].id)
        case .clearProfileOverride:
            setProfileOverride(nil)
        case .cancelWorkflows:
            cancelAllWorkflows()
        }
        return .success(())
    }

    static func actionError(from error: AIError) -> ActionError {
        switch error {
        case .disabled: return .unsupported("AI is turned off.")
        case .notConfigured(let reason): return .failed(reason)
        case .missingAPIKey: return .failed("No API key is stored.")
        case .invalidURL: return .failed("The AI server address is not valid.")
        case .http(let status, let message): return .failed("The AI server answered with status \(status). \(message)")
        case .timedOut: return .timedOut
        case .badResponse(let reason): return .failed("The AI server sent an unexpected answer. \(reason)")
        case .cancelled, .declinedByUser: return .cancelled
        case .noInput: return .failed("There was no text to send.")
        }
    }
}
