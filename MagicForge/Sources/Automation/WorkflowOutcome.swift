import Foundation
import MFCore

/// Reported before each step starts.
public struct WorkflowProgress: Sendable, Equatable {
    public var runID: UUID
    public var workflowID: UUID
    /// Indices from the top-level step down to the step that is starting. A step inside a
    /// conditional has the conditional's path plus its index within the branch that was taken.
    public var stepPath: [Int]
    /// Number of top-level steps.
    public var topLevelCount: Int
    /// e.g. "3 / 5" (top-level step number of total), suitable for `RunningWorkflow.progress`.
    public var summary: String

    public init(runID: UUID, workflowID: UUID, stepPath: [Int], topLevelCount: Int) {
        self.runID = runID; self.workflowID = workflowID; self.stepPath = stepPath; self.topLevelCount = topLevelCount
        self.summary = "\((stepPath.first ?? 0) + 1) / \(topLevelCount)"
    }
}

public struct WorkflowStepResult: Sendable, Equatable {
    /// Same convention as `WorkflowProgress.stepPath`.
    public var path: [Int]
    /// Nil when the step succeeded.
    public var error: ActionError?
    /// Seconds on the environment's clock.
    public var duration: TimeInterval
    public var succeeded: Bool { error == nil }

    public init(path: [Int], error: ActionError? = nil, duration: TimeInterval = 0) {
        self.path = path; self.error = error; self.duration = duration
    }
}

/// Result of one workflow run. `WorkflowRunner.run` never throws; everything is reported here.
public struct WorkflowOutcome: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        /// Every executed step succeeded.
        case completed
        /// Ran to the end with `continueOnError`, but at least one step failed.
        case completedWithErrors
        /// A step failed and the workflow stopped there.
        case failed
        case cancelled
        /// The whole-workflow timeout elapsed.
        case timedOut
        /// Never started: invalid, already running, or too many workflows running.
        case rejected
    }

    public var runID: UUID
    public var workflowID: UUID
    public var status: Status
    /// One entry per step that started, in execution order. A conditional is recorded after its branch.
    public var stepResults: [WorkflowStepResult]
    /// Path of the first step that failed, if any.
    public var failedStepPath: [Int]?
    /// First step error, or the reason for `cancelled` / `timedOut` / `rejected`.
    public var error: ActionError?
    /// Seconds on the environment's clock.
    public var duration: TimeInterval

    public var succeeded: Bool { status == .completed }

    public init(runID: UUID, workflowID: UUID, status: Status, stepResults: [WorkflowStepResult] = [],
                failedStepPath: [Int]? = nil, error: ActionError? = nil, duration: TimeInterval = 0) {
        self.runID = runID; self.workflowID = workflowID; self.status = status; self.stepResults = stepResults
        self.failedStepPath = failedStepPath; self.error = error; self.duration = duration
    }
}
