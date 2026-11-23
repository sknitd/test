import XCTest
@testable import WidgetForgeKit

/// Records actions instead of performing them, and can emit follow-up events to exercise the loop guard.
final class RecordingPerformer: AutomationActionPerformer, @unchecked Sendable {
    private let lock = NSLock()
    private var _performed: [String] = []
    var followUps: [String: [AutomationEvent]] = [:]     // rule id -> events its actions cause
    var failOn: String?

    var performed: [String] { lock.lock(); defer { lock.unlock() }; return _performed }

    func perform(_ action: AutomationAction, rule: AutomationRule) async throws -> [AutomationEvent] {
        if action.kind == failOn { throw DataSourceError.unsupported(action.kind) }
        lock.lock(); _performed.append("\(rule.name):\(action.kind)"); lock.unlock()
        return followUps[rule.id] ?? []
    }
}

final class AutomationTests: XCTestCase {
    let lowBattery = AutomationRule(name: "Low battery", trigger: .batteryBelow(percent: 20),
                                    actions: [.showWidget(id: "battery"), .setWidgetState(widgetID: "battery", key: "highlight", value: true),
                                              .notify(title: "Battery low", body: "Plug in")],
                                    cooldown: 0)

    func battery(_ percent: Double, onBattery: Bool = true) -> AutomationEvent {
        AutomationEvent(kind: .battery(percent: percent, onBattery: onBattery), context: ["battery": ["level": .number(percent / 100)]])
    }

    func testTriggerRunsActionsInOrder() async {
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [lowBattery], performer: performer)
        let started = await engine.handle(battery(15))
        XCTAssertEqual(started, [lowBattery.id])
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed, ["Low battery:showWidget", "Low battery:setWidgetState", "Low battery:notify"])
        let history = await engine.history
        XCTAssertEqual(history.last?.outcome, .completed)
        XCTAssertEqual(history.last?.actionsRun, 3)
    }

    func testThresholdIsEdgeTriggered() async {
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [lowBattery], performer: performer)
        for level in [50.0, 19, 18, 17] {
            await engine.handle(battery(level))
            await engine.waitUntilIdle()
        }
        XCTAssertEqual(performer.performed.count, 3, "fires once when crossing, not on every sample below the threshold")
        await engine.handle(battery(10, onBattery: false))      // plugged in: condition false again
        await engine.handle(battery(12))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.count, 6, "re-arms after recovering")
    }

    func testConditionsGateExecution() async {
        var rule = AutomationRule(name: "Dev tools", trigger: .appActivate(bundleID: ""), actions: [.switchProfile(id: "dev")], cooldown: 0)
        rule.conditions = [Condition("app.bundleID", .contains, "xcode")]
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer)
        await engine.handle(AutomationEvent(kind: .appActivated("com.apple.Safari"), context: ["app": ["bundleID": "com.apple.Safari"]]))
        await engine.waitUntilIdle()
        XCTAssertTrue(performer.performed.isEmpty)
        await engine.handle(AutomationEvent(kind: .appActivated("com.apple.dt.Xcode"), context: ["app": ["bundleID": "com.apple.dt.Xcode"]]))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed, ["Dev tools:switchProfile"])
    }

    func testCooldownSuppressesRepeatRuns() async {
        let clock = Box(Date(timeIntervalSince1970: 1_000_000))
        let rule = AutomationRule(name: "Net", trigger: .networkChange, actions: [.refreshData(widgetID: "w")], cooldown: 300)
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer, now: { clock.value })
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.waitUntilIdle()
        clock.value += 120
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.count, 1)
        let skipped = await engine.history.last?.outcome
        XCTAssertEqual(skipped, .skipped("cooling down"))
        clock.value += 200
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.count, 2)
        let runCount = await engine.rules[0].runCount
        XCTAssertEqual(runCount, 2)
    }

    func testCancellationStopsRemainingActions() async {
        let rule = AutomationRule(name: "Slow", trigger: .manual, actions: [.showWidget(id: "a"), .wait(seconds: 60), .hideWidget(id: "a")], cooldown: 0)
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer)
        let ran = await engine.runManually(rule.id)
        XCTAssertTrue(ran)
        let reachedWait = await eventually { performer.performed.count == 1 }
        XCTAssertTrue(reachedWait)
        let duplicate = await engine.runManually(rule.id)
        XCTAssertFalse(duplicate, "a running workflow is not started twice")
        await engine.cancel(rule.id)
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed, ["Slow:showWidget"])
        let outcome = await engine.history.last?.outcome
        XCTAssertEqual(outcome, .cancelled)
        let running = await engine.isRunning(rule.id)
        XCTAssertFalse(running)
    }

    func testFailureStopsWorkflowAndIsRecorded() async {
        let rule = AutomationRule(name: "Broken", trigger: .manual, actions: [.showWidget(id: "a"), .openURL("https://x.dev"), .hideWidget(id: "a")])
        let performer = RecordingPerformer()
        performer.failOn = "openURL"
        let engine = AutomationEngine(rules: [rule], performer: performer)
        await engine.runManually(rule.id)
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed, ["Broken:showWidget"])
        guard case .failed = await engine.history.last?.outcome else { return XCTFail("expected failure record") }
    }

    func testLoopGuardStopsMutualRecursion() async {
        // A shows a widget whenever "ping" arrives and emits "pong"; B does the reverse. Without a guard this never ends.
        let a = AutomationRule(name: "A", trigger: .widgetInteraction(name: "ping"), actions: [.showWidget(id: "x")], cooldown: 0)
        let b = AutomationRule(name: "B", trigger: .widgetInteraction(name: "pong"), actions: [.hideWidget(id: "x")], cooldown: 0)
        let performer = RecordingPerformer()
        performer.followUps[a.id] = [AutomationEvent(kind: .widgetInteraction(widgetID: "x", name: "pong"))]
        performer.followUps[b.id] = [AutomationEvent(kind: .widgetInteraction(widgetID: "x", name: "ping"))]
        let engine = AutomationEngine(rules: [a, b], performer: performer)
        await engine.handle(AutomationEvent(kind: .widgetInteraction(widgetID: "x", name: "ping")))
        let settled = await eventually {
            await engine.history.contains { $0.ruleName == "Loop guard" }
        }
        XCTAssertTrue(settled)
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.count, AutomationEngine.maxDepth + 1, "chain is cut at the depth limit")
    }

    func testRuleCannotRetriggerItself() async {
        let rule = AutomationRule(name: "Echo", trigger: .widgetInteraction(name: "tap"), actions: [.showWidget(id: "x")], cooldown: 0)
        let performer = RecordingPerformer()
        performer.followUps[rule.id] = [AutomationEvent(kind: .widgetInteraction(widgetID: "x", name: "tap"))]
        let engine = AutomationEngine(rules: [rule], performer: performer)
        await engine.handle(AutomationEvent(kind: .widgetInteraction(widgetID: "x", name: "tap")))
        let settled = await eventually { await engine.history.contains { $0.outcome == .skipped("would re-trigger itself") } }
        XCTAssertTrue(settled)
        XCTAssertEqual(performer.performed.count, 1)
    }

    func testTimerAndDataConditionTriggers() async {
        let timer = AutomationRule(name: "Tick", trigger: .timer(seconds: 60), actions: [.refreshData(widgetID: "w")], cooldown: 0)
        let data = AutomationRule(name: "Down", trigger: .dataCondition(widgetID: "w", condition: Condition("api.status", .notEquals, "ok")),
                                  actions: [.notify(title: "API down", body: "")], cooldown: 0)
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [timer, data], performer: performer)
        let t0 = Date(timeIntervalSince1970: 5_000)
        for offset in [0.0, 30, 61, 90, 125] {
            await engine.handle(AutomationEvent(kind: .timerTick, date: t0.addingTimeInterval(offset)))
            await engine.waitUntilIdle()
        }
        XCTAssertEqual(performer.performed.filter { $0.hasPrefix("Tick") }.count, 2, "fires at 61s and 125s")

        for status in ["ok", "down", "down", "ok", "down"] {
            await engine.handle(AutomationEvent(kind: .dataUpdated(widgetID: "w"), context: ["api": ["status": .string(status)]]))
            await engine.waitUntilIdle()
        }
        XCTAssertEqual(performer.performed.filter { $0.hasPrefix("Down") }.count, 2)
        await engine.handle(AutomationEvent(kind: .dataUpdated(widgetID: "other"), context: ["api": ["status": "down"]]))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.filter { $0.hasPrefix("Down") }.count, 2, "other widgets do not match")
    }

    func testDisabledPausedAndRemovedRules() async {
        var rule = AutomationRule(name: "Off", trigger: .networkChange, actions: [.showWidget(id: "a")], cooldown: 0)
        rule.enabled = false
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer)
        await engine.handle(AutomationEvent(kind: .networkChanged))
        rule.enabled = true
        await engine.upsert(rule)
        await engine.setPaused(true)
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.waitUntilIdle()
        XCTAssertTrue(performer.performed.isEmpty)
        await engine.setPaused(false)
        await engine.remove(rule.id)
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.waitUntilIdle()
        XCTAssertTrue(performer.performed.isEmpty)
    }

    func testRulesAreCodable() throws {
        let rules = [lowBattery, AutomationRule(name: "D", trigger: .dataCondition(widgetID: "w", condition: Condition("a", .lessThan, 3)),
                                                actions: AutomationAction.kinds.map(AutomationAction.make(kind:)))]
        let decoded = try JSONDecoder().decode([AutomationRule].self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
        XCTAssertEqual(AutomationTrigger.kinds.map { AutomationTrigger.make(kind: $0).kind }, AutomationTrigger.kinds)
        XCTAssertEqual(AutomationAction.kinds.map { AutomationAction.make(kind: $0).kind }, AutomationAction.kinds)
    }
}
