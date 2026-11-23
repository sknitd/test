import XCTest
import MFCore
import MFUtilities
import MFProfiles
@testable import MFEngine

final class ActionRoutingTests: XCTestCase {
    private func workflowConfiguration(_ workflow: Workflow) -> Configuration {
        TestConfig.with([GestureBinding(trigger: .single(.twoFingerTap), action: .workflow(id: workflow.id))]) {
            $0.workflows = [workflow]
        }
    }

    @MainActor func testNoneAndLeafActions() async {
        let harness = Harness()
        harness.model.start()
        let none = await harness.model.run(.none, source: .manualTest)
        XCTAssertNil(none.failureValue)
        XCTAssertEqual(harness.model.metrics.actionsExecuted, 0, "“No Action” is not an execution")
        let leaf = await harness.model.run(TestConfig.keyA, source: .menuBar)
        XCTAssertNil(leaf.failureValue)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA])
        XCTAssertEqual(harness.model.metrics.actionsExecuted, 1)
        XCTAssertEqual(harness.model.availability(of: TestConfig.keyA), .available)
        harness.model.stop()
    }

    @MainActor func testWorkflowRunsStepsInOrderAndIsTracked() async {
        let workflow = Workflow(name: "Two keys", steps: [
            .action(TestConfig.keyA), .delay(seconds: 0.3), .action(TestConfig.keyB),
            .notify(title: "Done", body: "Finished"),
        ])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        XCTAssertTrue(harness.model.validationIssues(for: workflow).isEmpty)
        XCTAssertEqual(harness.model.availability(of: .workflow(id: workflow.id)), .available)

        harness.perform(.twoFingerTap)
        await harness.wait("workflow start") { harness.model.runningWorkflows.count == 1 }
        XCTAssertEqual(harness.model.runningWorkflows.first?.workflowID, workflow.id)
        XCTAssertEqual(harness.model.runningWorkflows.first?.name, "Two keys")
        await harness.wait("progress") { harness.model.runningWorkflows.first?.progress == "2 / 4" }
        await harness.wait("workflow end") { harness.model.runningWorkflows.isEmpty }
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA, TestConfig.keyB])
        XCTAssertEqual(harness.notifier.notifications.map(\.title), ["Done"])
        await harness.wait("counted") { harness.model.metrics.actionsExecuted == 1 }
        XCTAssertNil(harness.model.recentGestures.first?.failure)
        harness.model.stop()
    }

    @MainActor func testWorkflowCancel() async {
        let workflow = Workflow(name: "Slow", steps: [.action(TestConfig.keyA), .delay(seconds: 5), .action(TestConfig.keyB)])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        let model = harness.model!
        let run = Task { @MainActor in await model.run(.workflow(id: workflow.id), source: .manualTest) }
        await harness.wait("first step") { harness.performer.performed.count == 1 }
        XCTAssertEqual(harness.model.runningWorkflows.count, 1)

        // The same workflow cannot be started twice.
        let second = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertNotNil(second.failureValue)
        XCTAssertEqual(harness.model.runningWorkflows.count, 1)

        harness.model.cancelAllWorkflows()
        let result = await run.value
        XCTAssertEqual(result.failureValue, .cancelled)
        XCTAssertTrue(harness.model.runningWorkflows.isEmpty)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA], "nothing runs after cancellation")

        let viaControl = Task { @MainActor in await model.run(.workflow(id: workflow.id), source: .manualTest) }
        await harness.wait("running again") { harness.model.runningWorkflows.count == 1 }
        _ = await harness.model.run(.control(.cancelWorkflows), source: .menuBar)
        let cancelled = await viaControl.value
        XCTAssertEqual(cancelled.failureValue, .cancelled)
        harness.model.stop()
    }

    @MainActor func testStopCancelsRunningWorkflows() async {
        let workflow = Workflow(name: "Slow", steps: [.delay(seconds: 5), .action(TestConfig.keyB)])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        let model = harness.model!
        let run = Task { @MainActor in await model.run(.workflow(id: workflow.id), source: .manualTest) }
        await harness.wait("running") { harness.model.runningWorkflows.count == 1 }
        harness.model.stop()
        let result = await run.value
        XCTAssertEqual(result.failureValue, .cancelled)
        XCTAssertTrue(harness.performer.performed.isEmpty)
    }

    @MainActor func testWorkflowFailureAndMissingWorkflow() async {
        let workflow = Workflow(name: "Fails", steps: [.action(TestConfig.keyA), .action(TestConfig.keyB)])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        harness.performer.error = .failed("No window.")
        let failed = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertEqual(failed.failureValue, .failed("No window."))
        XCTAssertEqual(harness.model.metrics.actionFailures, 1)
        XCTAssertEqual(harness.model.activityLog.first?.level, .error)

        let missing = await harness.model.run(.workflow(id: UUID()), source: .manualTest)
        guard case .notFound = missing.failureValue else { return XCTFail("expected notFound") }
        guard case .unavailable = harness.model.availability(of: .workflow(id: UUID())) else {
            return XCTFail("a missing workflow is unavailable")
        }
        harness.model.stop()
    }

    @MainActor func testWorkflowWithUntrustedScriptNeverStarts() async {
        let script = ScriptAction.shell(command: "rm -rf /tmp/example")
        let workflow = Workflow(name: "Scripted", steps: [.action(TestConfig.keyA), .action(.script(script))])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        let refused = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertEqual(refused.failureValue, .untrusted)
        XCTAssertTrue(harness.performer.performed.isEmpty, "not even the harmless first step runs")
        XCTAssertTrue(harness.model.runningWorkflows.isEmpty)

        harness.model.approve(script)
        let allowed = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertNil(allowed.failureValue)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA, .script(script)])
        harness.model.stop()
    }

    @MainActor func testWorkflowCanRouteControlActions() async {
        let workflow = Workflow(name: "Pause", steps: [.action(.control(.toggleGesturesPaused)),
                                                        .action(.control(.openDashboard))])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        let result = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertNil(result.failureValue)
        XCTAssertTrue(harness.model.isPaused)
        XCTAssertEqual(harness.dashboardOpenCount, 1)
        harness.model.stop()
    }

    @MainActor func testWorkflowConditionsUseLiveAppAndClipboard() async {
        let workflow = Workflow(name: "Conditional", steps: [
            .conditional(.frontmostAppIs(bundleID: "com.example.front"), then: [.action(TestConfig.keyA)], otherwise: []),
            .conditional(.appIsRunning(bundleID: "com.example.running"), then: [.action(TestConfig.keyB)], otherwise: []),
            .conditional(.clipboardContains("needle"), then: [.action(TestConfig.keyC)], otherwise: []),
        ])
        let harness = Harness(configuration: workflowConfiguration(workflow))
        harness.model.start()
        harness.frontmost.activate("com.example.front")
        harness.frontmost.runningApps = [RunningApp(bundleID: "com.example.running", name: "Running")]
        harness.text.clipboard = "hay needle hay"
        let result = await harness.model.run(.workflow(id: workflow.id), source: .manualTest)
        XCTAssertNil(result.failureValue)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA, TestConfig.keyB, TestConfig.keyC])
        harness.model.stop()
    }

    @MainActor func testRadialMenuRunsChosenItemAndRemembersIt() async {
        let first = RadialMenuItem(title: "A", action: TestConfig.keyA)
        let second = RadialMenuItem(title: "B", action: TestConfig.keyB)
        let menu = RadialMenu(name: "Quick", items: [first, second],
                              hotKey: KeyCombo(keyCode: 49, control: true, label: "⌃Space"))
        let binding = GestureBinding(trigger: .single(.twoFingerTap), action: .radialMenu(id: menu.id))
        let harness = Harness(configuration: TestConfig.with([binding]) { $0.radialMenus = [menu] })
        harness.model.start()
        XCTAssertEqual(harness.pointer.hotKeys, [menu.id: KeyCombo(keyCode: 49, control: true, label: "⌃Space")])

        harness.radial.choose = { menu, _ in menu.items[1] }
        harness.perform(.twoFingerTap)
        await harness.wait("item action") { harness.performer.performed.count == 1 }
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyB])
        XCTAssertEqual(harness.radial.presented.map(\.id), [menu.id])
        XCTAssertEqual(harness.radial.recents.first, [])

        // The hot key opens the same menu; the previous choice is offered as recent.
        harness.radial.choose = { _, _ in nil }
        harness.pointer.handlers?.onHotKey(menu.id)
        await harness.wait("hot key menu") { harness.radial.presented.count == 2 }
        XCTAssertEqual(harness.radial.recents.last?.map(\.id), [second.id])
        await harness.settle()
        XCTAssertEqual(harness.performer.performed.count, 1, "dismissing runs nothing")

        harness.model.showRadialMenu(menu.id)
        await harness.wait("shown") { harness.radial.presented.count == 3 }
        harness.model.stop()
        XCTAssertEqual(harness.radial.dismissCount, 1)
    }

    @MainActor func testRadialMenuUnavailableWithoutPresenterOrMenu() async {
        let menu = RadialMenu(name: "Quick", items: [RadialMenuItem(title: "A", action: TestConfig.keyA)])
        let harness = Harness(configuration: TestConfig.with([]) { $0.radialMenus = [menu] }, withRadialPresenter: false)
        harness.model.start()
        let result = await harness.model.run(.radialMenu(id: menu.id), source: .manualTest)
        guard case .unsupported = result.failureValue else { return XCTFail("expected unsupported") }
        guard case .unavailable = harness.model.availability(of: .radialMenu(id: menu.id)) else {
            return XCTFail("no presenter, not available")
        }
        let missing = await harness.model.run(.radialMenu(id: UUID()), source: .manualTest)
        guard case .notFound = missing.failureValue else { return XCTFail("expected notFound") }
        harness.model.stop()
    }

    @MainActor func testRadialMenuItemWithUntrustedScriptIsRefused() async {
        let script = ScriptAction.shortcut(name: "Do Things")
        let menu = RadialMenu(name: "Quick", items: [RadialMenuItem(title: "Script", action: .script(script))])
        let harness = Harness(configuration: TestConfig.with([]) { $0.radialMenus = [menu] })
        harness.model.start()
        let result = await harness.model.run(.radialMenu(id: menu.id), source: .manualTest)
        XCTAssertEqual(result.failureValue, .untrusted)
        XCTAssertTrue(harness.performer.performed.isEmpty)
        harness.model.stop()
    }

    @MainActor func testMetricsCountersAndReset() async {
        let harness = Harness()
        harness.model.start()
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.model.metrics.actionsExecuted == 1 }
        harness.performer.error = .failed("Nope.")
        _ = await harness.model.run(TestConfig.keyB, source: .manualTest)

        let metrics = harness.model.metrics
        XCTAssertEqual(metrics.gesturesRecognized, 1)
        XCTAssertEqual(metrics.actionsExecuted, 1)
        XCTAssertEqual(metrics.actionFailures, 1)
        XCTAssertEqual(metrics.framesProcessed, TestFrames.gesture(.twoFingerTap).count)
        XCTAssertGreaterThan(metrics.averageProcessingTime, 0)
        XCTAssertGreaterThanOrEqual(metrics.maxProcessingTime, metrics.averageProcessingTime)
        XCTAssertGreaterThanOrEqual(metrics.averageDispatchLatency, 0)
        XCTAssertLessThan(metrics.averageDispatchLatency, 1)
        XCTAssertEqual(harness.model.touchFeed.snapshot().totalFrames, metrics.framesProcessed)

        harness.model.resetMetrics()
        XCTAssertEqual(harness.model.metrics, EngineMetrics())
        harness.model.clearRecentGestures()
        XCTAssertTrue(harness.model.recentGestures.isEmpty)
        harness.model.stop()
    }

    @MainActor func testFrameMetricsArriveWithoutAnyGesture() async {
        let harness = Harness()
        harness.model.start()
        // A slow drift that is no gesture: only the coalesced statistics update can report it.
        let frames = TestFrames.gesture(.oneFingerSwipeUp)
        harness.adapter.push(frames)
        await harness.wait("frame statistics") { harness.model.metrics.framesProcessed == frames.count }
        XCTAssertEqual(harness.model.metrics.gesturesRecognized, 0)
        harness.model.stop()
    }

    @MainActor func testActivityLogIsCapped() async {
        let harness = Harness()
        harness.model.start()
        harness.performer.error = .failed("Nope.")
        for _ in 0..<(AppModel.activityLogLimit + 20) {
            _ = await harness.model.run(TestConfig.keyA, source: .manualTest)
        }
        XCTAssertEqual(harness.model.activityLog.count, AppModel.activityLogLimit)
        harness.model.stop()
    }

    @MainActor func testPermissionRationaleFollowsConfiguration() async {
        let harness = Harness(configuration: TestConfig.with([]))
        harness.model.start()
        XCTAssertNil(harness.model.permissionRationale(.accessibility), "nothing configured needs it")
        XCTAssertNil(harness.model.permissionRationale(.automation))
        XCTAssertNil(harness.model.permissionRationale(.inputMonitoring))

        harness.model.update { configuration in
            configuration.profiles[0].bindings = [
                GestureBinding(trigger: .single(.chordLeftClick), action: .app(.hideFrontmost)),
                GestureBinding(trigger: .single(.twoFingerTap), action: .script(.appleScript(source: "beep"))),
            ]
        }
        XCTAssertEqual(harness.model.permissionRationale(.accessibility)?.contains("fallback"), true)
        XCTAssertNotNil(harness.model.permissionRationale(.automation))
        XCTAssertNil(harness.model.permissionRationale(.inputMonitoring))
        harness.model.stop()
    }

    @MainActor func testDiagnosticsReport() async throws {
        let harness = Harness()
        harness.model.start()
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }

        let data = harness.model.diagnosticsReport(includeTouchFrames: false)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(report["touch"], "touch coordinates are opt-in")
        XCTAssertEqual(report["touchFramesIncluded"] as? Bool, false)
        XCTAssertEqual((report["adapter"] as? [String: Any])?["state"] as? String, "running")
        XCTAssertEqual((report["capabilities"] as? [String: Any])?["rawContacts"] as? Bool, true)
        XCTAssertEqual((report["permissions"] as? [String: Any])?["accessibility"] as? String, "granted")
        XCTAssertEqual((report["metrics"] as? [String: Any])?["gesturesRecognized"] as? Int, 1)
        XCTAssertEqual(report["recentGestureKinds"] as? [String], ["twoFingerTap"])
        XCTAssertEqual((report["counts"] as? [String: Any])?["profiles"] as? Int, 2)
        let devices = try XCTUnwrap(report["devices"] as? [[String: Any]])
        XCTAssertEqual(devices.first?["model"] as? String, "magicMouse2")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(TestConfig.mouse.id), "no device identifiers")
        XCTAssertFalse(text.contains(TestConfig.mouse.name), "no device names")
        XCTAssertFalse(text.contains("\"x\""))

        let full = harness.model.diagnosticsReport(includeTouchFrames: true)
        let fullReport = try XCTUnwrap(JSONSerialization.jsonObject(with: full) as? [String: Any])
        XCTAssertNotNil(fullReport["touch"])
        XCTAssertEqual(fullReport["touchFramesIncluded"] as? Bool, true)
        harness.model.stop()
    }
}
