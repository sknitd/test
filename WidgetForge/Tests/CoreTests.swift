import XCTest
@testable import WidgetForgeKit

final class JSONAndTemplateTests: XCTestCase {
    let context: JSONValue = [
        "cpu": ["usage": 0.4321, "cores": [0.1, 0.9]],
        "items": [["name": "a", "price": 3], ["name": "b", "price": 4.5]],
        "state": ["text": "hi", "empty": ""],
        "bytes": 1_572_864,
    ]

    func testPathLookup() {
        XCTAssertEqual(context.path("cpu.usage"), .number(0.4321))
        XCTAssertEqual(context.path("items[1].name"), "b")
        XCTAssertEqual(context.path("items.0.price"), 3)
        XCTAssertEqual(context.path("items.count"), 2)
        XCTAssertEqual(context.path("cpu.cores[-1]"), 0.9)
        XCTAssertNil(context.path("cpu.missing"))
        XCTAssertNil(context.path("items[7]"))
    }

    func testRoundTripCoding() throws {
        let data = try JSONEncoder().encode(context)
        XCTAssertEqual(try JSONValue.parse(data), context)
        XCTAssertEqual(try JSONValue.parse("{\"a\":[true,null,1.5,\"x\"]}"), ["a": [true, nil, 1.5, "x"]])
    }

    func testSetting() {
        let updated = context.setting("state.text", to: "bye").setting("new.deep", to: 1)
        XCTAssertEqual(updated.path("state.text"), "bye")
        XCTAssertEqual(updated.path("new.deep"), 1)
        XCTAssertEqual(updated.path("cpu.usage"), .number(0.4321))
    }

    func testTemplateRendering() {
        XCTAssertEqual(TemplateRenderer.render("CPU {{cpu.usage | percent}}", context: context), "CPU 43%")
        XCTAssertEqual(TemplateRenderer.render("{{cpu.usage | percent:1}}", context: context), "43.2%")
        XCTAssertEqual(TemplateRenderer.render("{{bytes | bytes}}", context: context), "1.5 MB")
        XCTAssertEqual(TemplateRenderer.render("{{state.empty | default:n/a}} {{missing | default:–}}", context: context), "n/a –")
        XCTAssertEqual(TemplateRenderer.render("{{state.text | upper}}!", context: context), "HI!")
        XCTAssertEqual(TemplateRenderer.render("no placeholders", context: context), "no placeholders")
        XCTAssertEqual(TemplateRenderer.render("broken {{cpu.usage", context: context), "broken {{cpu.usage")
        XCTAssertEqual(TemplateRenderer.render("{{items | pluck:name | join:+}}", context: context), "a+b")
    }

    func testResolveKeepsStructuredTypes() {
        XCTAssertEqual(TemplateRenderer.resolve("{{cpu.cores}}", context: context), [0.1, 0.9])
        XCTAssertEqual(TemplateRenderer.resolve("{{cpu.usage}}", context: context), .number(0.4321))
        XCTAssertEqual(TemplateRenderer.resolve("x{{cpu.usage | round:1}}", context: context), "x0.4")
        XCTAssertEqual(TemplateRenderer.resolve(12, context: context), 12)
    }

    func testFormatters() {
        XCTAssertEqual(Formatters.duration(93_784), "1d 2h 3m")
        XCTAssertEqual(Formatters.duration(59), "59s")
        XCTAssertEqual(Formatters.clock(125), "02:05")
        XCTAssertEqual(Formatters.clock(3_725), "1:02:05")
        XCTAssertEqual(Formatters.bytes(512), "512 B")
        XCTAssertNotNil(Formatters.date(from: "2027-01-01T00:00"))
        XCTAssertNotNil(Formatters.date(from: "2026-11-22T10:00:00Z"))
    }

    func testConditions() {
        XCTAssertTrue(Condition("cpu.usage", .greaterThan, 0.4).evaluate(in: context))
        XCTAssertFalse(Condition("cpu.usage", .lessThan, 0.4).evaluate(in: context))
        XCTAssertTrue(Condition("state.text", .equals, "hi").evaluate(in: context))
        XCTAssertTrue(Condition("state.text", .notEquals, "no").evaluate(in: context))
        XCTAssertTrue(Condition("state.text", .contains, "H").evaluate(in: context))
        XCTAssertTrue(Condition("cpu", .exists).evaluate(in: context))
        XCTAssertFalse(Condition("nope", .exists).evaluate(in: context))
        XCTAssertFalse(Condition("nope", .greaterThan, 1).evaluate(in: context))
    }

    func testNodeShorthandDecoding() throws {
        let node = try WidgetNode(json: ["type": "column", "spacing": 4, "children": [["type": "text", "value": "Hi"], ["type": "progress", "props": ["value": 0.5]]]])
        XCTAssertEqual(node.type, .column)
        XCTAssertEqual(node.number("spacing"), 4)
        XCTAssertEqual(node.children.count, 2)
        XCTAssertEqual(node.children[0].string("value"), "Hi")
        XCTAssertEqual(node.children[1].number("value"), 0.5)
        XCTAssertThrowsError(try WidgetNode(json: ["type": "exec"]))
        let again = try JSONDecoder().decode(WidgetNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(again, node)
    }

    func testNodeTreeOperations() {
        var root = WidgetNode.column([.text("a"), .row([.text("b")])])
        let target = root.children[1].children[0].id
        XCTAssertTrue(root.update(target) { $0.props["value"] = "changed" })
        XCTAssertEqual(root.find(target)?.string("value"), "changed")
        XCTAssertEqual(root.flattened.count, 4)
        XCTAssertEqual(root.remove([target]).count, 1)
        XCTAssertNil(root.find(target))
        let copy = root.withFreshIDs()
        XCTAssertTrue(Set(copy.flattened.map(\.id)).isDisjoint(with: Set(root.flattened.map(\.id))))
    }

    func testActionsRoundTrip() {
        let actions: [WidgetAction] = [.setState(key: "a", value: 1), .toggleState(key: "b"), .openURL("https://x.dev"), .runShortcut("Go"),
                                       .refresh, .trigger("pressed"), .script("tap"), .media("next"), .copy("t"), .incrementState(key: "n", by: 2), .launchApp("com.apple.Safari")]
        for action in actions { XCTAssertEqual(WidgetAction(json: action.json), action) }
        XCTAssertNil(WidgetAction(json: ["type": "shell", "command": "rm -rf /"]))
    }

    func testFuzzySearch() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "cpu", candidate: "CPU Monitor"))
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "CPU Monitor"))
        let names = ["Network Monitor", "CPU Monitor", "Custom REST API", "Clipboard Utility"]
        XCTAssertEqual(FuzzyMatcher.filter(names, query: "cpu") { $0 }.first, "CPU Monitor")
        XCTAssertEqual(FuzzyMatcher.filter(names, query: "netmon") { $0 }, ["Network Monitor"])
        XCTAssertEqual(FuzzyMatcher.filter(names, query: " ") { $0 }, names)
        XCTAssertEqual(FuzzyMatcher.filter(names, query: "clip") { $0 }.first, "Clipboard Utility")
    }

    func testDiagnostics() {
        let center = DiagnosticsCenter()
        center.log(.info, .app, "started")
        center.log(.error, .script, "boom", widgetID: "w")
        XCTAssertEqual(center.snapshot().count, 2)
        XCTAssertEqual(center.snapshot(widgetID: "w").map(\.message), ["boom"])
        XCTAssertEqual(center.snapshot(minimumLevel: .warning).count, 1)
        for i in 1...10 { center.recordTiming("t", seconds: Double(i)) }
        XCTAssertEqual(center.timing("t").count, 10)
        XCTAssertEqual(center.timing("t").average, 5.5, accuracy: 0.001)
        XCTAssertEqual(center.timing("t").max, 10)
        XCTAssertEqual(center.timing("t").p95, 10)
        for _ in 0..<(DiagnosticsCenter.capacity + 50) { center.log(.debug, .app, "x") }
        XCTAssertEqual(center.snapshot().count, DiagnosticsCenter.capacity)
    }

    func testCSV() {
        let parsed = CSVParser.parse("name,qty,note\nWidget,3,\"a, b\"\n\"Quote \"\"x\"\"\",4.5,\r\n")
        XCTAssertEqual(parsed.arrayValue?.count, 2)
        XCTAssertEqual(parsed.path("[0].qty"), 3)
        XCTAssertEqual(parsed.path("[0].note"), "a, b")
        XCTAssertEqual(parsed.path("[1].name"), "Quote \"x\"")
        XCTAssertEqual(parsed.path("[1].qty"), 4.5)
    }
}

final class SharedSnapshotTests: XCTestCase {
    func testSnapshotAndPendingChangesRoundTripThroughFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let widget = SnapshotWidget(id: "w1", name: "To-do", symbol: "checklist", definition: TemplateLibrary.todo,
                                    state: ["items": []], allowsSystemMetrics: false, data: [:], statuses: [:], scriptNode: nil)
        XCTAssertTrue(SharedContainer.writeSnapshot(SharedSnapshot(widgets: [widget]), in: dir))
        XCTAssertEqual(SharedContainer.readSnapshot(in: dir)?.widgets.map(\.id), ["w1"])

        let change = PendingStateChange(widgetID: "w1", key: "items", value: [["title": "Ship", "done": true]])
        SharedContainer.appendPending(change, in: dir)
        SharedContainer.apply(change, in: dir)
        XCTAssertEqual(SharedContainer.readSnapshot(in: dir)?.widgets[0].state["items"], [["title": "Ship", "done": true]])
        XCTAssertEqual(SharedContainer.drainPending(in: dir).map(\.key), ["items"])
        XCTAssertTrue(SharedContainer.drainPending(in: dir).isEmpty, "draining clears the queue")
        XCTAssertNil(SharedContainer.readSnapshot(in: nil))
    }

    func testStateChangesForActions() {
        let state: [String: JSONValue] = ["on": true, "n": 2]
        XCTAssertEqual(SharedContainer.stateChange(for: .toggleState(key: "on"), current: state)?.value, false)
        XCTAssertEqual(SharedContainer.stateChange(for: .incrementState(key: "n", by: 3), current: state)?.value, 5)
        XCTAssertEqual(SharedContainer.stateChange(for: .setState(key: "x", value: "y"), current: state)?.key, "x")
        XCTAssertNil(SharedContainer.stateChange(for: .openURL("https://x.dev"), current: state))
    }

    func testContextAndImplicitMetricSources() {
        let definition = WidgetDefinition(name: "M", size: WidgetSize(200, 100),
                                          root: .column([WidgetNode(.metric, props: ["metric": "memory"]), WidgetNode(.metric, props: ["metric": "cpu"])]),
                                          dataSources: [.metric("cpu", interval: 5)])
        let sources = WidgetContextBuilder.effectiveSources(for: definition)
        XCTAssertEqual(sources.map(\.id), ["cpu", "memory"])
        XCTAssertEqual(sources[0].interval, 5, "explicit sources are not duplicated")
        let context = WidgetContextBuilder.context(state: ["a": 1], settings: ["b": 2], data: ["cpu": ["usage": 0.5]],
                                                   statuses: ["cpu": DataSourceStatus.ok.json])
        XCTAssertEqual(context.path("state.a"), 1)
        XCTAssertEqual(context.path("settings.b"), 2)
        XCTAssertEqual(context.path("cpu.usage"), 0.5)
        XCTAssertEqual(context.path("sources.cpu.state"), "ok")
        XCTAssertEqual(context.path("sources.cpu.healthy"), true)
    }
}
