import Foundation
import XCTest
import MFCore
import MFUtilities
@testable import MFAutomation

/// Records every action and can fail or hang on demand. Never touches the OS.
final class MockPerformer: ActionPerforming, @unchecked Sendable {
    private struct State {
        var performed: [Action] = []
        var sources: [ActionSource] = []
        var failures: [Action: ActionError] = [:]
        var hanging: Set<Action> = []
    }
    private let state = Locked(State())

    var performed: [Action] { state.current.performed }
    var sources: [ActionSource] { state.current.sources }

    func fail(_ action: Action, with error: ActionError) { state.withLock { $0.failures[action] = error } }
    /// The action suspends until its task is cancelled.
    func hang(on action: Action) { state.withLock { _ = $0.hanging.insert(action) } }

    func perform(_ action: Action, context: ActionContext) async throws {
        let (failure, hangs) = state.withLock { state -> (ActionError?, Bool) in
            state.performed.append(action)
            state.sources.append(context.source)
            return (state.failures[action], state.hanging.contains(action))
        }
        if hangs { try await Task.sleep(nanoseconds: 60 * 1_000_000_000) }
        if let failure { throw failure }
    }

    func availability(of action: Action) -> ActionAvailability { .available }
}

/// Virtual clock: `sleep` advances `now()` instantly unless `blockSleeps` is set, in which case
/// it suspends until the task is cancelled (to test cancellation mid-delay).
final class MockEnvironment: WorkflowEnvironment, @unchecked Sendable {
    private struct State {
        var time: TimeInterval = 1000
        var frontmost: String?
        var running: Set<String> = []
        var clipboard: String?
        var notifications: [String] = []
        var routed: [Action] = []
        var routedError: ActionError?
        var sleeps: [Double] = []
        var blockSleeps = false
        var blockedSleepers = 0
        /// Virtual time at which `frontmost` switches to `pendingFrontmost`.
        var frontmostChange: (at: TimeInterval, bundleID: String)?
        var clipboardReads = 0
    }
    private let state = Locked(State())

    var frontmost: String? {
        get { state.current.frontmost }
        set { state.withLock { $0.frontmost = newValue } }
    }
    var running: Set<String> {
        get { state.current.running }
        set { state.withLock { $0.running = newValue } }
    }
    var clipboard: String? {
        get { state.current.clipboard }
        set { state.withLock { $0.clipboard = newValue } }
    }
    var blockSleeps: Bool {
        get { state.current.blockSleeps }
        set { state.withLock { $0.blockSleeps = newValue } }
    }
    var routedError: ActionError? {
        get { state.current.routedError }
        set { state.withLock { $0.routedError = newValue } }
    }
    var notifications: [String] { state.current.notifications }
    var routed: [Action] { state.current.routed }
    var sleeps: [Double] { state.current.sleeps }
    var blockedSleepers: Int { state.current.blockedSleepers }
    var clipboardReads: Int { state.current.clipboardReads }

    func bringToFront(_ bundleID: String, afterVirtualSeconds seconds: Double) {
        state.withLock { $0.frontmostChange = ($0.time + seconds, bundleID) }
    }

    func frontmostBundleID() async -> String? {
        state.withLock { state in
            if let change = state.frontmostChange, state.time >= change.at {
                state.frontmost = change.bundleID
                state.frontmostChange = nil
            }
            return state.frontmost
        }
    }

    func isAppRunning(bundleID: String) async -> Bool { state.current.running.contains(bundleID) }

    func clipboardString() async -> String? {
        state.withLock { $0.clipboardReads += 1; return $0.clipboard }
    }

    func notify(title: String, body: String) async { state.withLock { $0.notifications.append("\(title)|\(body)") } }

    func sleep(seconds: Double) async throws {
        let blocks = state.withLock { state -> Bool in
            state.sleeps.append(seconds)
            if state.blockSleeps { state.blockedSleepers += 1 }
            return state.blockSleeps
        }
        if blocks {
            try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        } else {
            try Task.checkCancellation()
            state.withLock { $0.time += seconds }
            await Task.yield()
        }
    }

    func now() -> TimeInterval { state.current.time }

    func runRouted(_ action: Action, context: ActionContext) async throws {
        let error = state.withLock { state -> ActionError? in
            state.routed.append(action)
            return state.routedError
        }
        if let error { throw error }
    }
}

/// Polls (in real time) until `condition` holds; fails the test after `timeout`.
func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
               _ condition: @Sendable () async -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTFail("Condition not met within \(timeout) s", file: file, line: line)
}

let testContext = ActionContext(source: .manualTest, frontmostBundleID: "com.example.front")

extension Action {
    static let a = Action.system(.missionControl)
    static let b = Action.system(.launchpad)
    static let c = Action.system(.spotlight)
    static let d = Action.window(.maximize)
}
