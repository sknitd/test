import Foundation
import MFCore
import MFUtilities
import MFProfiles
import MFAutomation

// Workflows: one `WorkflowRunner`, tracked in `runningWorkflows`.
extension AppModel {
    func runWorkflow(_ id: UUID, context: ActionContext) async -> Result<Void, ActionError> {
        guard let workflow = configuration.workflows.first(where: { $0.id == id }) else {
            return .failure(.notFound("The workflow"))
        }
        // Whole-workflow trust check up front, so a workflow never runs halfway into a refusal.
        guard ScriptTrust.untrustedScripts(reachableFrom: .workflow(id: id), in: configuration).isEmpty else {
            return .failure(.untrusted)
        }
        let runID = UUID()
        runningWorkflows.append(RunningWorkflow(id: runID, workflowID: workflow.id, name: workflow.name))
        let outcome = await workflowRunner.run(workflow, context: context, runID: runID) { [weak self] progress in
            MainHop.enqueue { [weak self] in self?.noteWorkflowProgress(progress) }
        }
        runningWorkflows.removeAll { $0.id == runID }

        switch outcome.status {
        case .completed:
            logActivity(.info, "Workflow “\(workflow.name)” finished.")
            return .success(())
        case .completedWithErrors:
            let failed = outcome.stepResults.filter { !$0.succeeded }.count
            logActivity(.warning, "Workflow “\(workflow.name)” finished, but \(failed) step(s) failed.")
            return .success(())
        case .failed, .rejected:
            return .failure(outcome.error ?? .failed("The workflow stopped."))
        case .cancelled:
            return .failure(.cancelled)
        case .timedOut:
            return .failure(.timedOut)
        }
    }

    private func noteWorkflowProgress(_ progress: WorkflowProgress) {
        guard let index = runningWorkflows.firstIndex(where: { $0.id == progress.runID }) else { return }
        if runningWorkflows[index].progress != progress.summary { runningWorkflows[index].progress = progress.summary }
    }

    public func cancelAllWorkflows() {
        let runner = workflowRunner
        Task { await runner.cancelAll() }
    }

    /// Validation problems of a workflow (nesting, unknown references, empty), for the builder UI.
    public func validationIssues(for workflow: Workflow) -> [String] {
        WorkflowValidator.issues(for: workflow, in: configuration)
    }

    // MARK: Bridging for workflow steps

    func workflowNotify(title: String, body: String) {
        guard configuration.settings.notificationsEnabled, let notifier = services.notifier else {
            logActivity(.info, "Workflow notification: \(title)")
            return
        }
        notifier.notify(title: title, body: body)
    }

    func workflowRunRouted(_ action: Action, context: ActionContext) async throws {
        if case .failure(let error) = await route(action, context: context, depth: 1) { throw error }
    }
}

/// What workflows need from the outside world, answered on the main actor from `Services`.
final class EngineWorkflowEnvironment: WorkflowEnvironment, @unchecked Sendable {
    @MainActor weak var model: AppModel?

    func frontmostBundleID() async -> String? {
        await MainActor.run { model?.services.frontmostApp.frontmostBundleID }
    }

    func isAppRunning(bundleID: String) async -> Bool {
        await MainActor.run {
            model?.services.frontmostApp.runningApps.contains { $0.bundleID.lowercased() == bundleID.lowercased() } ?? false
        }
    }

    func clipboardString() async -> String? {
        await MainActor.run { model?.services.textAccess.clipboardString() }
    }

    func notify(title: String, body: String) async {
        await MainActor.run { model?.workflowNotify(title: title, body: body) }
    }

    func runRouted(_ action: Action, context: ActionContext) async throws {
        guard let model = await MainActor.run(body: { self.model }) else { throw ActionError.cancelled }
        try await model.workflowRunRouted(action, context: context)
    }
}
