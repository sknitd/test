import XCTest
@testable import WidgetForgeKit

final class AIGeneratorTests: XCTestCase {
    let reply = """
    Sure! Here is your widget:
    ```json
    {"name": "Mini Monitor", "size": {"width": 240, "height": 140},
     "root": {"type": "column", "children": [
        {"type": "text", "value": "CPU {{cpu.usage | percent}}"},
        {"type": "progress", "value": "{{memory.usage}}", "label": "RAM {not a brace problem}"}]},
     "dataSources": [{"id": "cpu", "kind": "systemMetric", "metric": "cpu"}, {"id": "memory", "kind": "systemMetric", "metric": "memory"}],
     "permissions": {"systemMetrics": true, "scripting": true, "clipboard": true, "network": ["evil.example.com"]},
     "script": "WidgetForge.defineWidget({})"}
    ```
    Let me know if you want changes.
    """

    func testParsesFencedJSONAndStripsEverythingExecutable() throws {
        let generated = try AIWidgetGenerator.parse(reply)
        XCTAssertEqual(generated.definition.name, "Mini Monitor")
        XCTAssertNil(generated.definition.script, "AI output is declarative only")
        XCTAssertEqual(generated.requestedPermissions, PermissionManifest(systemMetrics: true), "permissions are recomputed from content, not taken from the model")
        XCTAssertEqual(generated.definition.category, "AI")
        XCTAssertEqual(generated.definition.root.children.count, 2)
    }

    func testRejectsInvalidOrUnsafeOutput() {
        XCTAssertThrowsError(try AIWidgetGenerator.parse("I cannot help with that.")) { XCTAssertEqual($0 as? AIError, .noJSON) }
        XCTAssertThrowsError(try AIWidgetGenerator.parse("{\"name\": \"X\", \"root\": {\"type\": \"terminal\"}}")) {
            guard case .invalidWidget = $0 as? AIError else { return XCTFail("expected invalidWidget") }
        }
        XCTAssertThrowsError(try AIWidgetGenerator.parse("{\"name\": \"X\", \"root\": {\"type\": \"web\", \"url\": \"https://example.com\"}}")) {
            guard case .invalidWidget = $0 as? AIError else { return XCTFail("expected invalidWidget") }
        }
    }

    func testRequestShapeAndKeyHandling() async throws {
        let transport = MockTransport { _, _ in
            let content = "{\\\"name\\\": \\\"Clock\\\", \\\"root\\\": {\\\"type\\\": \\\"clock\\\"}}"
            return HTTPResponse(status: 200, body: Data("{\"choices\":[{\"message\":{\"content\":\"\(content)\"}}]}".utf8))
        }
        let secrets = InMemorySecretStore(["AI_API_KEY": Secret(value: "sk-test", hosts: ["api.openai.com"])])
        var configuration = AIConfiguration()
        configuration.enabled = true
        let generated = try await AIWidgetGenerator(configuration: configuration, transport: transport).generate(prompt: "a clock", secrets: secrets)
        XCTAssertEqual(generated.definition.root.type, .clock)
        let request = transport.requests[0]
        XCTAssertEqual(request.url.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-test")
        let body = try JSONValue.parse(request.body ?? Data())
        XCTAssertEqual(body["model"], "gpt-4o-mini")
        XCTAssertEqual(body.path("messages[1].content"), "a clock")
    }

    func testDisabledOrUnconfiguredNeverCallsOut() async {
        let transport = MockTransport.json("{}")
        var configuration = AIConfiguration()
        do { _ = try await AIWidgetGenerator(configuration: configuration, transport: transport).generate(prompt: "x", secrets: InMemorySecretStore()); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? AIError, .disabled) }
        configuration.enabled = true
        do { _ = try await AIWidgetGenerator(configuration: configuration, transport: transport).generate(prompt: "x", secrets: InMemorySecretStore()); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? AIError, .missingKey) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testServiceErrorIsSurfaced() async {
        let transport = MockTransport.json("{\"error\":\"quota\"}", status: 429)
        var configuration = AIConfiguration()
        configuration.enabled = true
        configuration.endpoint = "http://localhost:11434/v1/"
        configuration.secretName = ""
        do { _ = try await AIWidgetGenerator(configuration: configuration, transport: transport).generate(prompt: "x", secrets: InMemorySecretStore()); XCTFail("should throw") }
        catch { guard case .http(429, _) = error as? AIError else { return XCTFail("expected http error, got \(error)") } }
        XCTAssertEqual(transport.requests.first?.url.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(transport.requests.first?.headers["Authorization"])
    }
}

#if canImport(JavaScriptCore)
final class MockScriptHost: ScriptHost, @unchecked Sendable {
    var permissions = PermissionManifest(network: ["api.example.com"], systemMetrics: true, scripting: true)
    var metrics: [String: JSONValue] = ["cpu": ["usage": 0.5], "memory": ["usage": 0.25]]
    var storage: [String: JSONValue] = [:]
    var logs: [String] = []
    var fetched: [String] = []
    var fetchDelay: UInt64 = 0
    private let lock = NSLock()

    func scriptPermissions() -> PermissionManifest { permissions }
    func scriptSettings() -> JSONValue { ["city": "Paris"] }
    func scriptMetric(_ name: String) -> JSONValue? { metrics[name] }
    func scriptDataSource(_ id: String) -> JSONValue? { id == "api" ? ["items": [1, 2, 3]] : nil }
    func scriptFetch(url: String, options: JSONValue) async throws -> JSONValue {
        guard let parsed = URL(string: url), let host = parsed.host, PermissionChecker.hostAllowed(host, allowlist: permissions.network) else {
            throw PermissionError.hostNotAllowed(url)
        }
        if fetchDelay > 0 { try await Task.sleep(nanoseconds: fetchDelay) }
        lock.lock(); fetched.append(url); lock.unlock()
        return ["url": .string(url), "ok": true]
    }
    func scriptStorageGet(_ key: String) -> JSONValue? { lock.lock(); defer { lock.unlock() }; return storage[key] }
    func scriptStorageSet(_ key: String, _ value: JSONValue) { lock.lock(); storage[key] = value; lock.unlock() }
    func scriptLog(_ level: String, _ message: String) { lock.lock(); logs.append("\(level): \(message)"); lock.unlock() }
}

final class ScriptRuntimeTests: XCTestCase {
    func runtime(_ source: String, host: MockScriptHost = MockScriptHost(), limits: ScriptLimits = ScriptLimits()) -> (ScriptRuntime, MockScriptHost) {
        (ScriptRuntime(source: source, host: host, limits: limits), host)
    }

    func testSDKExampleFromTheDocsRuns() async throws {
        let (script, _) = runtime(TemplateLibrary.customScript.script!)
        let meta = try await script.load()
        XCTAssertEqual(meta.id, "system-monitor")
        XCTAssertEqual(meta.name, "System Monitor")
        XCTAssertEqual(meta.size, WidgetSize(320, 220))
        XCTAssertEqual(meta.interval, 2)
        XCTAssertTrue(meta.hasUpdate && meta.hasRender)

        var state = try await script.update(state: [:])
        XCTAssertEqual(state["cpu"], 0.5)
        XCTAssertEqual(state["memory"], 0.25)
        state = try await script.update(state: state)
        XCTAssertEqual(state["history"], [0.5, 0.5])

        let tree = try await script.render(state: state)
        XCTAssertEqual(tree.type, .column)
        XCTAssertEqual(tree.children.map(\.type), [.text, .progress, .progress, .chart])
        XCTAssertEqual(tree.children[1].number("value"), 0.5)
        XCTAssertEqual(tree.children[1].string("valueLabel"), "50%")
    }

    func testCompileErrorsAndMissingDefinition() async {
        let (broken, _) = runtime("WidgetForge.defineWidget({ render( {")
        do { _ = try await broken.load(); XCTFail("should throw") }
        catch { guard case .compile = error as? ScriptError else { return XCTFail("expected compile error, got \(error)") } }

        let (empty, _) = runtime("var x = 1;")
        do { _ = try await empty.load(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .notDefined) }

        let (noRender, _) = runtime("WidgetForge.defineWidget({ name: 'x' })")
        do { _ = try await noRender.load(); XCTFail("should throw") }
        catch { guard case .compile = error as? ScriptError else { return XCTFail("expected compile error") } }
    }

    func testRenderOutputIsValidatedLikeAnyUntrustedLayout() async throws {
        let (script, _) = runtime("""
        WidgetForge.defineWidget({
          render(state) { return state.bad ? { type: "column", children: [{ type: "shell", command: "rm -rf ~" }] } : { type: "text", value: "ok" }; }
        });
        """)
        _ = try await script.load()
        let good = try await script.render(state: ["bad": false])
        XCTAssertEqual(good.string("value"), "ok")
        do { _ = try await script.render(state: ["bad": true]); XCTFail("should throw") }
        catch { guard case .invalidOutput = error as? ScriptError else { return XCTFail("expected invalidOutput, got \(error)") } }
    }

    func testRuntimeErrorsAreReported() async throws {
        let (script, _) = runtime("WidgetForge.defineWidget({ update() { throw new Error('kaput'); }, render() { return null.x; } });")
        _ = try await script.load()
        do { _ = try await script.update(state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .runtime("kaput")) }
        do { _ = try await script.render(state: [:]); XCTFail("should throw") }
        catch { guard case .runtime = error as? ScriptError else { return XCTFail("expected runtime error, got \(error)") } }
    }

    func testNoAmbientAuthority() async throws {
        // Nothing that reaches the outside world exists unless the bridge provides it.
        let (script, _) = runtime("""
        WidgetForge.defineWidget({
          update() {
            return {
              fetch: typeof fetch, xhr: typeof XMLHttpRequest, require: typeof require, process: typeof process,
              timers: typeof setTimeout, native: typeof __wf_native, frozen: Object.isFrozen(WidgetForge),
              tamper: (() => { try { WidgetForge.defineWidget = null; WidgetForge = 1; } catch (e) {} return typeof WidgetForge.defineWidget; })()
            };
          },
          render() { return { type: "text" }; }
        });
        """)
        _ = try await script.load()
        let probe = try await script.update(state: [:])
        for key in ["fetch", "xhr", "require", "process", "timers", "native"] { XCTAssertEqual(probe[key], "undefined", key) }
        XCTAssertEqual(probe["frozen"], true)
        XCTAssertEqual(probe["tamper"], "function")
    }

    func testUnauthorizedAccessIsDenied() async throws {
        let host = MockScriptHost()
        host.permissions = PermissionManifest(network: ["api.example.com"], scripting: true)   // no systemMetrics
        let (script, _) = runtime("""
        WidgetForge.defineWidget({
          async update(context, state) {
            if (state.mode === "metrics") return { cpu: await context.system.cpu() };
            return await context.fetch(state.url);
          },
          render() { return { type: "text" }; }
        });
        """, host: host)
        _ = try await script.load()
        do { _ = try await script.update(state: ["mode": "metrics"]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .runtime("system metrics permission not granted")) }
        do { _ = try await script.update(state: ["url": "https://evil.example.org/steal"]); XCTFail("should throw") }
        catch { guard case .runtime(let message) = error as? ScriptError else { return XCTFail("expected runtime error") }; XCTAssertTrue(message.contains("allowlist")) }
        XCTAssertTrue(host.fetched.isEmpty)

        let ok = try await script.update(state: ["url": "https://api.example.com/v1"])
        XCTAssertEqual(ok["ok"], true)
        XCTAssertEqual(host.fetched, ["https://api.example.com/v1"])

        // Revocation applies to the next call; nothing is cached inside the runtime.
        host.permissions.network = []
        do { _ = try await script.update(state: ["url": "https://api.example.com/v1"]); XCTFail("should throw") }
        catch { XCTAssertNotNil(error as? ScriptError) }
        XCTAssertEqual(host.fetched.count, 1)
    }

    func testInfiniteLoopIsTerminated() async throws {
        try XCTSkipUnless(ScriptRuntime.watchdogAvailable, "JSContextGroupSetExecutionTimeLimit is not exported by this JavaScriptCore build")
        var limits = ScriptLimits()
        limits.syncTimeout = 0.3
        let (script, _) = runtime("WidgetForge.defineWidget({ update() { while (true) {} }, render() { for (;;) {} } });", limits: limits)
        _ = try await script.load()
        let started = Date()
        do { _ = try await script.update(state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .timeout) }
        do { _ = try await script.render(state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        let (topLevel, _) = runtime("while (true) {}", limits: limits)
        do { _ = try await topLevel.load(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .timeout) }
    }

    func testAsyncTimeout() async throws {
        var limits = ScriptLimits()
        limits.asyncTimeout = 0.2
        let (script, _) = runtime("WidgetForge.defineWidget({ update() { return new Promise(() => {}); }, render() { return { type: 'text' }; } });", limits: limits)
        _ = try await script.load()
        do { _ = try await script.update(state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .timeout) }
    }

    func testResourceLimits() async throws {
        var limits = ScriptLimits()
        limits.maxOutputBytes = 2_000
        limits.maxFetchesPerRun = 2
        limits.maxStorageBytes = 100
        limits.maxLogsPerRun = 3
        let (script, host) = runtime("""
        WidgetForge.defineWidget({
          async update(context, state) {
            if (state.mode === "big") return { blob: "x".repeat(5000) };
            if (state.mode === "fetch") { for (let i = 0; i < 5; i++) await context.fetch("https://api.example.com/" + i); return {}; }
            if (state.mode === "store") { context.storage.set("k", "y".repeat(500)); return {}; }
            if (state.mode === "log") { for (let i = 0; i < 50; i++) context.log("line", i); return {}; }
            return {};
          },
          render(state) { return { type: "text", value: "x".repeat(state.n || 1) }; }
        });
        """, limits: limits)
        _ = try await script.load()
        do { _ = try await script.update(state: ["mode": "big"]); XCTFail("should throw") }
        catch { guard case .resourceLimit = error as? ScriptError else { return XCTFail("expected resourceLimit, got \(error)") } }
        do { _ = try await script.update(state: ["mode": "fetch"]); XCTFail("should throw") }
        catch { guard case .runtime(let m) = error as? ScriptError else { return XCTFail("expected runtime") }; XCTAssertTrue(m.contains("fetch limit")) }
        XCTAssertEqual(host.fetched.count, 2)
        do { _ = try await script.update(state: ["mode": "store"]); XCTFail("should throw") }
        catch { guard case .runtime(let m) = error as? ScriptError else { return XCTFail("expected runtime") }; XCTAssertTrue(m.contains("quota")) }
        XCTAssertTrue(host.storage.isEmpty)
        _ = try await script.update(state: ["mode": "log"])
        XCTAssertEqual(host.logs.count, 3)
        do { _ = try await script.render(state: ["n": 5000]); XCTFail("should throw") }
        catch { guard case .resourceLimit = error as? ScriptError else { return XCTFail("expected resourceLimit, got \(error)") } }
    }

    func testStorageSettingsDataAndActions() async throws {
        let (script, host) = runtime("""
        WidgetForge.defineWidget({
          update(context, state) {
            const runs = (context.storage.get("runs") || 0) + 1;
            context.storage.set("runs", runs);
            console.log("run", runs);
            return { runs, city: context.settings.city, total: context.data("api").items.reduce((a, b) => a + b, 0), missing: context.data("nope") };
          },
          actions: { add(context, state, payload) { return { ...state, count: (state.count || 0) + payload.by }; } },
          render(state) { return { type: "text", value: String(state.count) }; }
        });
        """)
        let meta = try await script.load()
        XCTAssertEqual(meta.actions, ["add"])
        _ = try await script.update(state: [:])
        let second = try await script.update(state: [:])
        XCTAssertEqual(second, ["runs": 2, "city": "Paris", "total": 6, "missing": nil])
        XCTAssertEqual(host.storage["runs"], 2)
        XCTAssertEqual(host.logs.last, "info: run 2")
        let afterAction = try await script.runAction("add", state: ["count": 1], payload: ["by": 4])
        XCTAssertEqual(afterAction["count"], 5)
        do { _ = try await script.runAction("nope", state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .runtime("Unknown action: nope")) }
    }

    func testCancellation() async throws {
        let host = MockScriptHost()
        host.fetchDelay = 5_000_000_000
        let (script, _) = runtime("""
        WidgetForge.defineWidget({ async update(context) { return await context.fetch("https://api.example.com/slow"); }, render() { return { type: "text" }; } });
        """, host: host)
        _ = try await script.load()
        let pending = Task { try await script.update(state: [:]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        script.cancel()
        let started = Date()
        do { _ = try await pending.value; XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .cancelled) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        do { _ = try await script.update(state: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? ScriptError, .cancelled) }
    }
}
#endif

#if canImport(Darwin)
final class SystemMetricsTests: XCTestCase {
    /// Reads the real machine. Asserts plausibility only, since actual values differ per host.
    func testCollectorReturnsRealPlausibleValues() async throws {
        let collector = SystemMetricsCollector()
        collector.sample()
        try await Task.sleep(nanoseconds: 400_000_000)
        let sample = collector.sample()

        let cpu = try XCTUnwrap(sample["cpu"])
        let usage = try XCTUnwrap(cpu["usage"]?.doubleValue)
        XCTAssertTrue((0...1).contains(usage))
        XCTAssertEqual(cpu["cores"]?.arrayValue?.count, ProcessInfo.processInfo.activeProcessorCount)

        let memory = try XCTUnwrap(sample["memory"])
        let used = try XCTUnwrap(memory["usedBytes"]?.doubleValue), total = try XCTUnwrap(memory["totalBytes"]?.doubleValue)
        XCTAssertEqual(total, Double(ProcessInfo.processInfo.physicalMemory))
        XCTAssertTrue(used > 0 && used <= total)

        let storage = try XCTUnwrap(sample["storage"])
        XCTAssertGreaterThan(try XCTUnwrap(storage["totalBytes"]?.doubleValue), 0)
        XCTAssertGreaterThan(try XCTUnwrap(storage["freeBytes"]?.doubleValue), 0)

        let network = try XCTUnwrap(sample["network"])
        XCTAssertNotNil(network["downBytesPerSec"]?.doubleValue)
        XCTAssertNotNil(network["connected"]?.boolValue)

        let battery = try XCTUnwrap(sample["battery"])
        if battery["present"]?.boolValue == true {
            XCTAssertTrue((0...1).contains(try XCTUnwrap(battery["level"]?.doubleValue)))
        } else {
            XCTAssertEqual(battery["level"], .null, "no battery must not be reported as a percentage")
        }

        let system = try XCTUnwrap(sample["system"])
        XCTAssertGreaterThan(try XCTUnwrap(system["uptimeSeconds"]?.doubleValue), 0)
        XCTAssertFalse(try XCTUnwrap(system["hostname"]?.stringValue).isEmpty)
        XCTAssertTrue(try XCTUnwrap(system["osVersion"]?.stringValue).hasPrefix("macOS "))
        XCTAssertTrue(["arm64", "x86_64"].contains(try XCTUnwrap(system["architecture"]?.stringValue)))

        XCTAssertNotNil(ProcessMetrics.memoryFootprint())
        XCTAssertNotNil(ProcessMetrics.cpuTime())
        XCTAssertNil(collector.snapshot(metric: "nonsense"))
    }
}
#endif
