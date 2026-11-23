import Foundation
import MFCore
import MFUtilities

/// Everything a workflow needs beyond leaf actions. The engine supplies the real
/// implementation; tests inject a mock so nothing touches the OS or really sleeps.
public protocol WorkflowEnvironment: Sendable {
    func frontmostBundleID() async -> String?
    func isAppRunning(bundleID: String) async -> Bool
    /// Only read when a `.clipboardContains` condition is evaluated.
    func clipboardString() async -> String?
    func notify(title: String, body: String) async
    /// Suspends for `seconds`. Must throw `CancellationError` when the task is cancelled.
    func sleep(seconds: Double) async throws
    /// Monotonic seconds; only differences are used. Must agree with `sleep(seconds:)`.
    func now() -> TimeInterval
    /// Runs a non-leaf action (`.radialMenu`, `.ai`, `.control`). Throw `ActionError` on failure.
    /// Never called with `.workflow`, `.none` or leaf actions.
    func runRouted(_ action: Action, context: ActionContext) async throws
}

public extension WorkflowEnvironment {
    func sleep(seconds: Double) async throws {
        guard seconds.isFinite, seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 86_400) * 1_000_000_000))
    }

    func now() -> TimeInterval { MonotonicClock.now() }
}
