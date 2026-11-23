import Foundation

struct ScriptLimits: Sendable {
    /// Wall-clock budget for any single synchronous stretch of JavaScript (enforced by the VM watchdog).
    var syncTimeout = 1.0
    /// Budget for an asynchronous `update()` / action, including awaited fetches.
    var asyncTimeout = 15.0
    /// Largest state or layout a script may return, as JSON bytes.
    var maxOutputBytes = 256_000
    var maxFetchesPerRun = 8
    var maxStorageBytes = 64_000
    var maxLogsPerRun = 50
}

enum ScriptError: Error, LocalizedError, Equatable {
    case unavailable
    case compile(String)
    case runtime(String)
    case timeout
    case cancelled
    case notDefined
    case resourceLimit(String)
    case permission(String)
    case invalidOutput([String])

    var errorDescription: String? {
        switch self {
        case .unavailable: return "JavaScript is not available on this platform"
        case .compile(let m): return "Script error: \(m)"
        case .runtime(let m): return "Script error: \(m)"
        case .timeout: return "The script exceeded its time limit and was stopped"
        case .cancelled: return "The script was cancelled"
        case .notDefined: return "The script never called WidgetForge.defineWidget()"
        case .resourceLimit(let m): return "Resource limit: \(m)"
        case .permission(let m): return "Permission denied: \(m)"
        case .invalidOutput(let errors): return "render() returned an invalid layout: " + errors.joined(separator: "; ")
        }
    }
}

struct ScriptMetadata: Equatable, Sendable {
    var id: String?
    var name: String?
    var size: WidgetSize?
    var interval: Double?
    var hasUpdate: Bool
    var hasRender: Bool
    var actions: [String]
}

/// The narrow bridge between a widget script and the app. Every method re-checks the widget's *current*
/// permissions, so revoking a permission takes effect on the very next call. Implementations must be thread-safe.
protocol ScriptHost: AnyObject {
    func scriptPermissions() -> PermissionManifest
    func scriptSettings() -> JSONValue
    func scriptMetric(_ name: String) -> JSONValue?
    func scriptDataSource(_ id: String) -> JSONValue?
    func scriptFetch(url: String, options: JSONValue) async throws -> JSONValue
    func scriptStorageGet(_ key: String) -> JSONValue?
    func scriptStorageSet(_ key: String, _ value: JSONValue)
    func scriptLog(_ level: String, _ message: String)
}

#if canImport(JavaScriptCore)
import JavaScriptCore

/// Runs one widget script in its own JavaScriptCore virtual machine.
///
/// What this is: a capability-restricted interpreter. A bare `JSContext` has no network, filesystem,
/// process, timer or DOM APIs; the only way out is the `context` object built here, and each of its
/// functions is permission-checked natively.
///
/// What this is **not**: an OS-level sandbox. The script shares the app's address space, so a JavaScriptCore
/// engine bug could in principle escape it. That is why scripts from imported packages stay disabled until
/// the user explicitly trusts them, and why `docs/SECURITY.md` describes an out-of-process design as the
/// prerequisite for ever running untrusted code automatically.
final class ScriptRuntime {
    private let source: String
    private let limits: ScriptLimits
    private weak var host: ScriptHost?
    private let queue = DispatchQueue(label: "com.widgetforge.script", qos: .utility)

    private var vm: JSVirtualMachine?
    private var context: JSContext?
    private var api: JSValue?
    private var lastException: String?
    private let terminated = Box(false)
    private var cancelled = false
    private var fetchCount = 0
    private var logCount = 0
    private var pending: [UUID: Once] = [:]

    init(source: String, host: ScriptHost?, limits: ScriptLimits = ScriptLimits()) {
        self.source = source; self.host = host; self.limits = limits
    }

    // MARK: Watchdog (WebKit SPI, looked up dynamically)

    private typealias ShouldTerminate = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Bool
    private typealias SetTimeLimit = @convention(c) (OpaquePointer?, Double, ShouldTerminate?, UnsafeMutableRawPointer?) -> Void

    private static let setTimeLimit: SetTimeLimit? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else { return nil }
        return unsafeBitCast(symbol, to: SetTimeLimit.self)
    }()

    /// Whether runaway synchronous code (e.g. `while(true){}`) can be interrupted on this OS build.
    /// When false, the app refuses to run scripts rather than risk a hung thread.
    static var watchdogAvailable: Bool { setTimeLimit != nil }

    // MARK: Lifecycle

    /// Compile the script and capture its `defineWidget` call.
    func load() async throws -> ScriptMetadata {
        try await onQueue { try self.loadLocked() }
    }

    private func loadLocked() throws -> ScriptMetadata {
        guard !cancelled else { throw ScriptError.cancelled }
        guard let vm = JSVirtualMachine(), let context = JSContext(virtualMachine: vm) else { throw ScriptError.unavailable }
        self.vm = vm
        self.context = context
        context.name = "WidgetForge widget"
        context.exceptionHandler = { [weak self] _, exception in
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
            self?.lastException = "\(exception?.toString() ?? "unknown error") (line \(line))"
        }
        if let setLimit = ScriptRuntime.setTimeLimit {
            let callback: ShouldTerminate = { _, info in
                if let info { Unmanaged<Box<Bool>>.fromOpaque(info).takeUnretainedValue().value = true }
                return true
            }
            setLimit(JSContextGetGroup(context.jsGlobalContextRef), limits.syncTimeout, callback, Unmanaged.passUnretained(terminated).toOpaque())
        }
        installBridge(in: context)
        let apiValue = context.evaluateScript(ScriptRuntime.prelude, withSourceURL: URL(string: "widgetforge-sdk.js"))
        if let message = takeException() { throw ScriptError.compile("SDK failed to load: \(message)") }
        api = apiValue
        context.evaluateScript(source, withSourceURL: URL(string: "widget.js"))
        if let failure = takeFailure() { throw failure == .timeout ? failure : ScriptError.compile(failure.message) }
        guard let metaText = api?.invokeMethod("meta", withArguments: [])?.toString(), takeException() == nil,
              let meta = try? JSONValue.parse(metaText), meta["defined"]?.boolValue == true else {
            throw ScriptError.notDefined
        }
        var size: WidgetSize?
        if let w = meta.path("size.width")?.doubleValue, let h = meta.path("size.height")?.doubleValue { size = WidgetSize(w, h) }
        return ScriptMetadata(id: meta["id"]?.stringValue, name: meta["name"]?.stringValue, size: size,
                              interval: meta["interval"]?.doubleValue, hasUpdate: meta["hasUpdate"]?.boolValue ?? false,
                              hasRender: meta["hasRender"]?.boolValue ?? false,
                              actions: (meta["actions"]?.arrayValue ?? []).compactMap(\.stringValue))
    }

    /// Run `update(context, state)` and return the new state.
    func update(state: JSONValue) async throws -> JSONValue {
        try await callAsync("update", arguments: [state.compactJSONString])
    }

    /// Run a named handler from the definition's `actions` map and return the new state.
    func runAction(_ name: String, state: JSONValue, payload: JSONValue = .null) async throws -> JSONValue {
        try await callAsync("action", arguments: [name, state.compactJSONString, payload.compactJSONString])
    }

    /// Run `render(state)` and validate what it returns before it is turned into a node tree.
    func render(state: JSONValue) async throws -> WidgetNode {
        try await onQueue {
            guard let api = self.api, !self.cancelled else { throw ScriptError.cancelled }
            let output = api.invokeMethod("render", withArguments: [state.compactJSONString])
            if let failure = self.takeFailure() { throw failure }
            guard let text = output?.toString(), output?.isString == true else { throw ScriptError.invalidOutput(["render() must return a component object"]) }
            guard text.utf8.count <= self.limits.maxOutputBytes else { throw ScriptError.resourceLimit("layout larger than \(self.limits.maxOutputBytes / 1000) KB") }
            guard let json = try? JSONValue.parse(text) else { throw ScriptError.invalidOutput(["not JSON"]) }
            var report = ValidationReport()
            var count = 0
            SchemaValidator.validate(node: json, path: "render()", depth: 1, count: &count, limits: SchemaValidator.Limits(), report: &report)
            guard report.isValid else { throw ScriptError.invalidOutput(report.errors) }
            do { return try WidgetNode(json: json) } catch { throw ScriptError.invalidOutput([error.localizedDescription]) }
        }
    }

    /// Stop the script: pending async work fails with `.cancelled` and no further calls are accepted.
    /// Synchronous code already executing is bounded by the watchdog.
    func cancel() {
        queue.async {
            self.cancelled = true
            let waiting = self.pending.values
            self.pending.removeAll()
            waiting.forEach { $0.fail(.cancelled) }
            self.api = nil
            self.context = nil
            self.vm = nil
        }
    }

    // MARK: Internals

    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func callAsync(_ method: String, arguments: [Any]) async throws -> JSONValue {
        let limits = self.limits
        let text: String = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let api = self.api, !self.cancelled else { continuation.resume(throwing: ScriptError.cancelled); return }
                let id = UUID()
                let once = Once(continuation) { [weak self] in self?.pending[id] = nil }
                self.pending[id] = once
                self.fetchCount = 0
                self.logCount = 0
                let done: @convention(block) (String) -> Void = { once.succeed($0) }
                let fail: @convention(block) (String) -> Void = { once.fail(.runtime($0)) }
                api.invokeMethod(method, withArguments: arguments + [unsafeBitCast(done, to: AnyObject.self), unsafeBitCast(fail, to: AnyObject.self)])
                if let failure = self.takeFailure() { once.fail(failure) }
                self.queue.asyncAfter(deadline: .now() + limits.asyncTimeout) { once.fail(.timeout) }
            }
        }
        guard text.utf8.count <= limits.maxOutputBytes else { throw ScriptError.resourceLimit("state larger than \(limits.maxOutputBytes / 1000) KB") }
        guard let value = try? JSONValue.parse(text) else { throw ScriptError.runtime("update() must return a JSON-serialisable value") }
        return value
    }

    private func takeException() -> String? {
        defer { lastException = nil }
        return lastException
    }

    /// The failure (if any) left behind by the JavaScript call that just returned.
    private func takeFailure() -> ScriptError? {
        let message = takeException()
        if terminated.value {
            terminated.value = false
            return .timeout
        }
        if let message { return message.contains("execution terminated") ? .timeout : .runtime(message) }
        return nil
    }

    private func installBridge(in context: JSContext) {
        let native = JSValue(newObjectIn: context)

        let metric: @convention(block) (String) -> String = { [weak self] name in
            guard let host = self?.host, host.scriptPermissions().systemMetrics else { return "{\"__error\":\"system metrics permission not granted\"}" }
            return (host.scriptMetric(name) ?? .null).compactJSONString
        }
        let data: @convention(block) (String) -> String = { [weak self] id in
            (self?.host?.scriptDataSource(id) ?? .null).compactJSONString
        }
        let settings: @convention(block) () -> String = { [weak self] in
            (self?.host?.scriptSettings() ?? .object([:])).compactJSONString
        }
        let storageGet: @convention(block) (String) -> String = { [weak self] key in
            (self?.host?.scriptStorageGet(key) ?? .null).compactJSONString
        }
        let storageSet: @convention(block) (String, String) -> String = { [weak self] key, json in
            guard let self, let host = self.host else { return "unavailable" }
            guard json.utf8.count <= self.limits.maxStorageBytes else { return "value exceeds the \(self.limits.maxStorageBytes / 1000) KB storage quota" }
            guard key.count <= 64, let value = try? JSONValue.parse(json) else { return "invalid key or value" }
            host.scriptStorageSet(key, value)
            return ""
        }
        let log: @convention(block) (String, String) -> Void = { [weak self] level, message in
            guard let self, self.logCount < self.limits.maxLogsPerRun else { return }
            self.logCount += 1
            self.host?.scriptLog(level, String(message.prefix(1000)))
        }
        let fetch: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] url, optionsJSON, resolve, reject in
            guard let self, let host = self.host else { reject.call(withArguments: ["unavailable"]); return }
            self.fetchCount += 1
            guard self.fetchCount <= self.limits.maxFetchesPerRun else {
                reject.call(withArguments: ["fetch limit of \(self.limits.maxFetchesPerRun) per run exceeded"])
                return
            }
            let options = (try? JSONValue.parse(optionsJSON)) ?? .object([:])
            let queue = self.queue
            Task {
                do {
                    let value = try await host.scriptFetch(url: url, options: options)
                    let json = value.compactJSONString
                    queue.async { [weak self] in
                        guard self?.cancelled == false else { return }
                        resolve.call(withArguments: [json])
                        _ = self?.takeFailure()
                    }
                } catch {
                    let message = error.localizedDescription
                    queue.async { [weak self] in
                        guard self?.cancelled == false else { return }
                        reject.call(withArguments: [message])
                        _ = self?.takeFailure()
                    }
                }
            }
        }
        native?.setObject(unsafeBitCast(metric, to: AnyObject.self), forKeyedSubscript: "metric" as NSString)
        native?.setObject(unsafeBitCast(data, to: AnyObject.self), forKeyedSubscript: "data" as NSString)
        native?.setObject(unsafeBitCast(settings, to: AnyObject.self), forKeyedSubscript: "settings" as NSString)
        native?.setObject(unsafeBitCast(storageGet, to: AnyObject.self), forKeyedSubscript: "storageGet" as NSString)
        native?.setObject(unsafeBitCast(storageSet, to: AnyObject.self), forKeyedSubscript: "storageSet" as NSString)
        native?.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        native?.setObject(unsafeBitCast(fetch, to: AnyObject.self), forKeyedSubscript: "fetch" as NSString)
        context.setObject(native, forKeyedSubscript: "__wf_native" as NSString)
    }

    /// The SDK. It captures the native bridge in a closure, removes it from the global object, and exposes a
    /// frozen `WidgetForge` object. The returned entry points are held natively, out of the script's reach.
    static let prelude = """
    (function (global) {
      "use strict";
      const native = global.__wf_native;
      delete global.__wf_native;
      let definition = null;

      const parse = (text) => {
        const value = JSON.parse(text);
        if (value && value.__error) throw new Error(value.__error);
        return value;
      };
      const stringify = (value) => {
        const text = JSON.stringify(value === undefined ? null : value);
        return text === undefined ? "null" : text;
      };
      const say = (level) => (...parts) => native.log(level, parts.map((p) => typeof p === "string" ? p : stringify(p)).join(" "));

      const metric = (name, pick) => async () => { const m = parse(native.metric(name)); return pick ? pick(m) : m; };
      const makeContext = () => Object.freeze({
        system: Object.freeze({
          cpu: metric("cpu", (m) => m.usage),
          cpuDetail: metric("cpu"),
          memory: metric("memory", (m) => m.usage),
          memoryDetail: metric("memory"),
          storage: metric("storage"),
          network: metric("network"),
          battery: metric("battery"),
          info: metric("system"),
        }),
        settings: parse(native.settings()),
        data: (id) => parse(native.data(String(id))),
        fetch: (url, options) => new Promise((resolve, reject) => {
          native.fetch(String(url), stringify(options || {}), (text) => resolve(JSON.parse(text)), (message) => reject(new Error(message)));
        }),
        storage: Object.freeze({
          get: (key) => parse(native.storageGet(String(key))),
          set: (key, value) => { const error = native.storageSet(String(key), stringify(value)); if (error) throw new Error(error); },
        }),
        log: say("info"),
        warn: say("warning"),
        error: say("error"),
      });

      Object.defineProperty(global, "WidgetForge", {
        value: Object.freeze({
          version: "1.0",
          defineWidget(spec) {
            if (definition) throw new Error("WidgetForge.defineWidget() may only be called once");
            if (!spec || typeof spec !== "object") throw new Error("defineWidget() expects an object");
            if (typeof spec.render !== "function") throw new Error("defineWidget() requires a render(state) function");
            definition = spec;
          },
        }),
        writable: false, configurable: false, enumerable: true,
      });
      Object.defineProperty(global, "console", {
        value: Object.freeze({ log: say("info"), info: say("info"), warn: say("warning"), error: say("error") }),
        writable: false, configurable: false,
      });

      const settle = (work, done, fail) => {
        Promise.resolve().then(work).then(
          (result) => { try { done(stringify(result)); } catch (e) { fail(String(e && e.message || e)); } },
          (e) => fail(String(e && e.message || e)));
      };

      return Object.freeze({
        meta() {
          if (!definition) return stringify({ defined: false });
          return stringify({
            defined: true, id: definition.id, name: definition.name, size: definition.size,
            interval: definition.interval, hasUpdate: typeof definition.update === "function",
            hasRender: typeof definition.render === "function",
            actions: Object.keys(definition.actions || {}),
          });
        },
        update(stateText, done, fail) {
          const state = JSON.parse(stateText);
          settle(() => typeof definition.update === "function" ? definition.update(makeContext(), state) : state, done, fail);
        },
        action(name, stateText, payloadText, done, fail) {
          const handler = (definition.actions || {})[name];
          if (typeof handler !== "function") { fail("Unknown action: " + name); return; }
          const state = JSON.parse(stateText);
          settle(() => handler(makeContext(), state, JSON.parse(payloadText)), done, fail);
        },
        render(stateText) {
          return stringify(definition.render(JSON.parse(stateText)));
        },
      });
    })(this);
    """
}

/// Resumes a continuation exactly once, whichever of success, failure, timeout or cancellation comes first.
private final class Once {
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()
    private let cleanup: () -> Void

    init(_ continuation: CheckedContinuation<String, Error>, cleanup: @escaping () -> Void) {
        self.continuation = continuation
        self.cleanup = cleanup
    }

    private func take() -> CheckedContinuation<String, Error>? {
        lock.lock(); defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }

    func succeed(_ value: String) {
        guard let c = take() else { return }
        cleanup()
        c.resume(returning: value)
    }

    func fail(_ error: ScriptError) {
        guard let c = take() else { return }
        cleanup()
        c.resume(throwing: error)
    }
}

private extension ScriptError {
    var message: String {
        switch self {
        case .compile(let m), .runtime(let m): return m
        default: return errorDescription ?? "error"
        }
    }
}
#endif
