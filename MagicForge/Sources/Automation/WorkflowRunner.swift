import Foundation
import MFCore
import MFUtilities

/// Runs workflows step by step. All OS interaction goes through the injected performer and
/// environment, so the runner itself is portable and fully testable.
///
/// Guarantees:
/// - `run` never throws; the result is always a `WorkflowOutcome`.
/// - Steps run strictly in order. Nothing runs after the workflow is cancelled or timed out.
/// - A workflow id runs at most once at a time, and at most `WorkflowLimits.maxConcurrentRuns`
///   workflows run concurrently. Extra requests are rejected, not queued.
/// - Workflows that fail `WorkflowValidator.structuralIssues` (including any nested
///   `.workflow` action) are rejected before the first step.
/// - Script actions for which `isScriptTrusted` returns false fail with `ActionError.untrusted`
///   and are never handed to the performer.
public actor WorkflowRunner {
    private struct ActiveRun {
        var workflowID: UUID
        var task: Task<WorkflowOutcome, Never>
        var timedOut = false
    }

    private let performer: ActionPerforming
    private let environment: WorkflowEnvironment
    private let isScriptTrusted: @Sendable (ScriptAction) -> Bool
    private var runs: [UUID: ActiveRun] = [:]
    private let log = Log("workflow")

    public init(performer: ActionPerforming, environment: WorkflowEnvironment,
                isScriptTrusted: @escaping @Sendable (ScriptAction) -> Bool) {
        self.performer = performer
        self.environment = environment
        self.isScriptTrusted = isScriptTrusted
    }

    // MARK: Public API

    /// Runs `workflow` to completion, failure, cancellation or timeout.
    /// - Parameters:
    ///   - context: Passed to every action with `source` replaced by `.workflow`.
    ///   - runID: Identifies this run for `cancel(runID:)` and progress reports.
    ///   - onProgress: Called on the runner's executor before each step starts.
    public func run(_ workflow: Workflow, context: ActionContext, runID: UUID = UUID(),
                    onProgress: (@Sendable (WorkflowProgress) -> Void)? = nil) async -> WorkflowOutcome {
        if let reason = rejectionReason(for: workflow, runID: runID) {
            log.notice("Workflow rejected: \(reason)")
            return WorkflowOutcome(runID: runID, workflowID: workflow.id, status: .rejected, error: reason)
        }

        var stepContext = context
        stepContext.source = .workflow
        let task = Task { [stepContext] in
            await self.execute(workflow, context: stepContext, runID: runID, onProgress: onProgress)
        }
        runs[runID] = ActiveRun(workflowID: workflow.id, task: task)

        // Real-time safety net for an action that hangs: step boundaries and sleeps check the
        // deadline on the environment's clock, this covers time spent inside a single action.
        let timeout = workflow.timeout
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
            self.expire(runID: runID)
        }

        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        watchdog.cancel()
        runs[runID] = nil
        return outcome
    }

    /// Cancels one run. Returns false when no such run is active.
    @discardableResult
    public func cancel(runID: UUID) -> Bool {
        guard let run = runs[runID] else { return false }
        run.task.cancel()
        return true
    }

    /// Cancels every active run. Each `run` call still returns its (cancelled) outcome.
    public func cancelAll() {
        for run in runs.values { run.task.cancel() }
    }

    public var activeRunIDs: [UUID] { Array(runs.keys) }
    public var activeRunCount: Int { runs.count }
    public func isRunning(workflowID: UUID) -> Bool { runs.values.contains { $0.workflowID == workflowID } }

    // MARK: Admission

    private func rejectionReason(for workflow: Workflow, runID: UUID) -> ActionError? {
        if runs[runID] != nil { return .failed("This run identifier is already in use.") }
        if isRunning(workflowID: workflow.id) { return .failed("The workflow “\(workflow.name)” is already running.") }
        if runs.count >= WorkflowLimits.maxConcurrentRuns {
            return .failed("Too many workflows are running (limit \(WorkflowLimits.maxConcurrentRuns)).")
        }
        if WorkflowValidator.containsNestedWorkflow(workflow.steps) {
            return .unsupported("Workflows cannot run other workflows.")
        }
        if let issue = WorkflowValidator.structuralIssues(for: workflow).first { return .unsupported(issue) }
        return nil
    }

    private func expire(runID: UUID) {
        guard var run = runs[runID] else { return }
        run.timedOut = true
        runs[runID] = run
        run.task.cancel()
    }

    // MARK: Execution

    private enum Abort { case failed, cancelled, timedOut }
    private enum Flow { case proceed, abort(Abort) }
    /// Thrown by steps when the whole-workflow deadline passes.
    private struct WorkflowDeadlinePassed: Error {}

    /// Mutable state of one run; only touched from the actor.
    private final class RunState {
        let runID: UUID
        let workflow: Workflow
        let context: ActionContext
        let deadline: TimeInterval
        let onProgress: (@Sendable (WorkflowProgress) -> Void)?
        var results: [WorkflowStepResult] = []
        var firstFailure: (path: [Int], error: ActionError)?

        init(runID: UUID, workflow: Workflow, context: ActionContext, deadline: TimeInterval,
             onProgress: (@Sendable (WorkflowProgress) -> Void)?) {
            self.runID = runID; self.workflow = workflow; self.context = context
            self.deadline = deadline; self.onProgress = onProgress
        }

        func record(_ path: [Int], error: ActionError?, duration: TimeInterval) {
            results.append(WorkflowStepResult(path: path, error: error, duration: max(0, duration)))
            if let error, firstFailure == nil { firstFailure = (path, error) }
        }
    }

    private func execute(_ workflow: Workflow, context: ActionContext, runID: UUID,
                         onProgress: (@Sendable (WorkflowProgress) -> Void)?) async -> WorkflowOutcome {
        let start = environment.now()
        let state = RunState(runID: runID, workflow: workflow, context: context, deadline: start + workflow.timeout,
                             onProgress: onProgress)
        let flow = await runSteps(workflow.steps, parentPath: [], state: state)

        let status: WorkflowOutcome.Status
        var error = state.firstFailure?.error
        switch flow {
        case .abort(.cancelled): status = .cancelled; error = .cancelled
        case .abort(.timedOut): status = .timedOut; error = .timedOut
        case .abort(.failed): status = .failed
        case .proceed: status = state.firstFailure == nil ? .completed : .completedWithErrors
        }
        return WorkflowOutcome(runID: runID, workflowID: workflow.id, status: status, stepResults: state.results,
                               failedStepPath: state.firstFailure?.path, error: error,
                               duration: max(0, environment.now() - start))
    }

    /// Cancellation or timeout that must stop the run now, if any.
    private func interruption(_ state: RunState) -> Abort? {
        if runs[state.runID]?.timedOut == true { return .timedOut }
        if Task.isCancelled { return .cancelled }
        if environment.now() >= state.deadline { return .timedOut }
        return nil
    }

    private func runSteps(_ steps: [WorkflowStep], parentPath: [Int], state: RunState) async -> Flow {
        for (index, step) in steps.enumerated() {
            if let abort = interruption(state) { return .abort(abort) }
            let path = parentPath + [index]
            state.onProgress?(WorkflowProgress(runID: state.runID, workflowID: state.workflow.id, stepPath: path,
                                               topLevelCount: state.workflow.steps.count))
            let started = environment.now()
            do {
                let flow = try await run(step, path: path, state: state)
                if case .abort = flow { return flow }
                state.record(path, error: nil, duration: environment.now() - started)
            } catch {
                let elapsed = environment.now() - started
                if error is WorkflowDeadlinePassed {
                    state.record(path, error: .timedOut, duration: elapsed)
                    return .abort(.timedOut)
                }
                if let abort = interruption(state), abort == .timedOut || Task.isCancelled {
                    state.record(path, error: abort == .timedOut ? .timedOut : .cancelled, duration: elapsed)
                    return .abort(abort)
                }
                state.record(path, error: Self.actionError(from: error), duration: elapsed)
                if !state.workflow.continueOnError { return .abort(.failed) }
            }
        }
        return .proceed
    }

    private func run(_ step: WorkflowStep, path: [Int], state: RunState) async throws -> Flow {
        switch step {
        case .action(let action):
            try await perform(action, state: state)
        case .delay(let seconds):
            try await pause(seconds, state: state)
        case .waitForApp(let bundleID, let timeout):
            try await waitForApp(bundleID, timeout: timeout, state: state)
        case .notify(let title, let body):
            await environment.notify(title: title, body: body)
        case .conditional(let condition, let then, let otherwise):
            let branch = await evaluate(condition) ? then : otherwise
            return await runSteps(branch, parentPath: path, state: state)
        }
        return .proceed
    }

    private func perform(_ action: Action, state: RunState) async throws {
        switch action {
        case .none:
            return
        case .workflow:
            throw ActionError.unsupported("Workflows cannot run other workflows.")
        case .radialMenu, .ai, .control:
            try await environment.runRouted(action, context: state.context)
        case .system, .window, .app, .keyboard, .mouse, .text, .script:
            if let script = action.script, !isScriptTrusted(script) { throw ActionError.untrusted }
            try await performer.perform(action, context: state.context)
        }
    }

    /// Sleeps for `seconds`, but never past the workflow deadline.
    private func pause(_ seconds: Double, state: RunState) async throws {
        let remaining = state.deadline - environment.now()
        guard remaining > 0 else { throw WorkflowDeadlinePassed() }
        try await environment.sleep(seconds: min(seconds, remaining))
        try Task.checkCancellation()
        if seconds >= remaining { throw WorkflowDeadlinePassed() }
    }

    /// Polls the frontmost app every `waitForAppPollInterval` until it matches or `timeout` passes.
    private func waitForApp(_ bundleID: String, timeout: Double, state: RunState) async throws {
        let interval = WorkflowLimits.waitForAppPollInterval
        let started = environment.now()
        // Bounded even if the environment's clock does not advance.
        let maxPolls = Int((timeout / interval).rounded(.up)) + 2
        for _ in 0..<maxPolls {
            if await environment.frontmostBundleID() == bundleID { return }
            try Task.checkCancellation()
            let now = environment.now()
            let stepRemaining = timeout - (now - started)
            let workflowRemaining = state.deadline - now
            if workflowRemaining <= 0 { throw WorkflowDeadlinePassed() }
            if stepRemaining <= 0 { throw ActionError.timedOut }
            try await environment.sleep(seconds: max(0.001, min(interval, stepRemaining, workflowRemaining)))
            try Task.checkCancellation()
        }
        if await environment.frontmostBundleID() == bundleID { return }
        throw ActionError.timedOut
    }

    private func evaluate(_ condition: WorkflowCondition) async -> Bool {
        var negated = false
        var current = condition
        while case .not(let inner) = current {
            negated.toggle()
            current = inner
        }
        let value: Bool
        switch current {
        case .frontmostAppIs(let bundleID):
            value = await environment.frontmostBundleID() == bundleID
        case .appIsRunning(let bundleID):
            value = await environment.isAppRunning(bundleID: bundleID)
        case .clipboardContains(let text):
            if let clipboard = await environment.clipboardString() {
                value = text.isEmpty ? !clipboard.isEmpty : clipboard.contains(text)
            } else {
                value = false
            }
        case .not:
            value = false // unreachable: unwrapped above
        }
        return negated ? !value : value
    }

    private static func actionError(from error: Error) -> ActionError {
        if let error = error as? ActionError { return error }
        if error is CancellationError { return .cancelled }
        return .failed(String(describing: error))
    }
}
