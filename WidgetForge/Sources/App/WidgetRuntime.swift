import SwiftUI
import AppKit

/// Everything a running widget needs from the app. `AppModel` is the real implementation; the builder's
/// live preview uses the same services with a throw-away instance.
@MainActor
protocol WidgetRuntimeServices: AnyObject {
    var dataEngine: DataSourceEngine { get }
    var diagnostics: DiagnosticsCenter { get }
    var metricsHub: MetricsHub { get }
    var updatesPaused: Bool { get }
    func runtime(_ runtime: WidgetRuntime, didChange instance: WidgetInstance)
    func runtime(_ runtime: WidgetRuntime, didEmit event: AutomationEvent)
    func notify(title: String, body: String)
}

/// The live half of a widget: subscribes to its data, runs its script, handles its actions and publishes the
/// context its views render from. One exists per visible widget; hidden widgets have none, so they cost nothing.
@MainActor
final class WidgetRuntime: ObservableObject {
    @Published private(set) var instance: WidgetInstance
    @Published private(set) var context: JSONValue = .object([:])
    @Published private(set) var scriptNode: WidgetNode?
    @Published private(set) var scriptMessage: String?
    @Published private(set) var lastNotice: String?

    private weak var services: WidgetRuntimeServices?
    private var data: [String: JSONValue] = [:]
    private var statuses: [String: DataSourceStatus] = [:]
    private var publishScheduled = false
    private var pendingSince: DispatchTime?
    private var started = false
    private var usesMetrics = false
    /// When false, state changes stay in memory (builder preview).
    let persistsState: Bool

    private var script: ScriptRuntime?
    private var scriptTask: Task<Void, Never>?
    private var scriptState: JSONValue = .object([:])
    private var scriptHost: RuntimeScriptHost?

    init(instance: WidgetInstance, services: WidgetRuntimeServices, persistsState: Bool = true) {
        self.instance = instance
        self.services = services
        self.persistsState = persistsState
        rebuildContext()
    }

    var id: String { instance.id }
    var isRunning: Bool { started }
    var sourceStatuses: [String: DataSourceStatus] { statuses }

    // MARK: Lifecycle

    func start() {
        guard !started, let services else { return }
        started = true
        let sources = WidgetContextBuilder.effectiveSources(for: instance.definition)
        usesMetrics = sources.contains { $0.kind == .systemMetric } || instance.scriptEnabled
        if usesMetrics, instance.effectivePermissions.systemMetrics { services.metricsHub.retain(id) }
        let fetchContext = FetchContext(permissions: instance.effectivePermissions, settings: instance.definition.settings, widgetID: id)
        let engine = services.dataEngine
        let owner = id
        for source in sources {
            statuses[source.id] = .loading
            Task { [weak self] in
                await engine.subscribe(owner: owner, config: source, context: fetchContext) { result in
                    Task { @MainActor in self?.receive(source.id, result) }
                }
            }
        }
        rebuildContext()
        startScript()
    }

    func stop() {
        guard started else { return }
        started = false
        let engine = services?.dataEngine
        let owner = id
        Task { await engine?.unsubscribe(owner: owner) }
        services?.metricsHub.release(id)
        scriptTask?.cancel()
        scriptTask = nil
        script?.cancel()
        script = nil
        scriptHost = nil
    }

    /// Drop all subscriptions and start again (used by "Refresh" and after settings or permission changes).
    func restart() {
        stop()
        data.removeAll()
        statuses.removeAll()
        scriptNode = nil
        scriptMessage = nil
        start()
    }

    /// Adopt a changed instance from the store. Restarts only if something that affects data or code changed.
    func adopt(_ updated: WidgetInstance) {
        let needsRestart = updated.definition != instance.definition || updated.granted != instance.granted
            || updated.scriptTrusted != instance.scriptTrusted
        instance = updated
        scriptHost?.update(instance: updated, data: data)
        if needsRestart, started { restart() } else { rebuildContext() }
    }

    // MARK: Data

    private func receive(_ sourceID: String, _ result: DataSourceResult) {
        guard started else { return }
        if let value = result.value { data[sourceID] = value } else { data[sourceID] = nil }
        let previous = statuses[sourceID]
        statuses[sourceID] = result.status
        if previous != result.status, let detail = result.status.detail {
            services?.diagnostics.log(result.status.isHealthy ? .info : .warning, .network, "\(instance.name) · \(sourceID): \(detail)", widgetID: id)
        }
        services?.diagnostics.increment("data.updates")
        schedulePublish()
    }

    /// Coalesce bursts of updates into one view refresh per run-loop turn.
    private func schedulePublish() {
        if pendingSince == nil { pendingSince = .now() }
        guard !publishScheduled else { return }
        publishScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publishScheduled = false
            self.rebuildContext()
            if let since = self.pendingSince {
                self.services?.diagnostics.recordTiming("widget.updateLatency", seconds: Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1e9)
                self.pendingSince = nil
            }
            self.scriptHost?.update(instance: self.instance, data: self.data)
            self.services?.runtime(self, didEmit: AutomationEvent(kind: .dataUpdated(widgetID: self.id), context: self.context))
        }
    }

    private func rebuildContext() {
        let next = WidgetContextBuilder.context(state: instance.state, settings: instance.definition.settings, data: data,
                                                statuses: statuses.mapValues(\.json))
        if next != context { context = next }
    }

    // MARK: State and actions

    func setState(_ key: String, _ value: JSONValue) {
        guard instance.state[key] != value else { return }
        instance.state[key] = value
        rebuildContext()
        if persistsState { services?.runtime(self, didChange: instance) }
    }

    func perform(_ action: WidgetAction) {
        let permissions = instance.effectivePermissions
        func deny(_ capability: String) {
            lastNotice = "Blocked: this widget does not have the \(capability) permission."
            services?.diagnostics.log(.warning, .security, "\(instance.name) tried to use \(capability) without permission", widgetID: id)
        }
        switch action {
        case .setState(let key, let value): setState(key, value)
        case .toggleState(let key): setState(key, .bool(!(instance.state[key]?.boolValue ?? false)))
        case .incrementState(let key, let by): setState(key, .number((instance.state[key]?.doubleValue ?? 0) + by))
        case .refresh: if started { restart() }
        case .trigger(let name):
            services?.runtime(self, didEmit: AutomationEvent(kind: .widgetInteraction(widgetID: id, name: name), context: context))
        case .openURL(let text):
            guard permissions.openURLs else { return deny("open links") }
            guard let url = URL(string: text), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                lastNotice = "That link cannot be opened."
                return
            }
            NSWorkspace.shared.open(url)
        case .runShortcut(let name):
            guard permissions.shortcuts else { return deny("run shortcuts") }
            SystemActions.runShortcut(named: name)
        case .launchApp(let bundleID):
            guard permissions.launchApps else { return deny("launch apps") }
            SystemActions.launchApp(bundleID: bundleID)
        case .media(let command):
            guard permissions.mediaControl else { return deny("media control") }
            if let error = SystemActions.media(command) { lastNotice = error }
        case .copy(let text):
            guard permissions.clipboard else { return deny("clipboard") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .script(let name):
            guard let script else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    self.scriptState = try await script.runAction(name, state: self.scriptState)
                    self.scriptNode = try await script.render(state: self.scriptState)
                } catch { self.reportScript(error) }
            }
        }
    }

    func readClipboard() -> String? {
        guard instance.effectivePermissions.clipboard else {
            lastNotice = "Blocked: this widget does not have the clipboard permission."
            return nil
        }
        return NSPasteboard.general.string(forType: .string)
    }

    func clearNotice() { lastNotice = nil }

    /// The environment handed to this widget's views.
    func environment(interactive: Bool = true) -> RenderEnvironment {
        var env = RenderEnvironment()
        env.context = context
        env.isInteractive = interactive
        env.scriptNode = scriptNode
        env.scriptMessage = scriptMessage
        env.imageHosts = instance.effectivePermissions.network
        env.perform = { [weak self] action in self?.perform(action) }
        env.setState = { [weak self] key, value in self?.setState(key, value) }
        env.readClipboard = { [weak self] in self?.readClipboard() }
        env.notify = { [weak self] title, body in
            guard let self, self.instance.effectivePermissions.notifications else { return }
            self.services?.notify(title: title, body: body)
        }
        let webHosts = instance.effectivePermissions.webContent
        env.webView = { url in AnyView(RestrictedWebView(url: url, allowedHosts: webHosts)) }
        return env
    }

    // MARK: Script

    private func startScript() {
        guard instance.definition.hasScript, let source = instance.definition.script, let services else { return }
        guard instance.scriptEnabled else {
            scriptMessage = instance.scriptTrusted ? "Scripting permission is off for this widget." : "This widget's script has not been trusted yet. Review it in the Builder to enable it."
            return
        }
        guard ScriptRuntime.watchdogAvailable else {
            scriptMessage = "Scripts are disabled: this macOS build cannot interrupt runaway scripts."
            return
        }
        let host = RuntimeScriptHost(instance: instance, data: data, engine: services.dataEngine, metrics: services.metricsHub.collector,
                                     diagnostics: services.diagnostics) { [weak self] storage in
            Task { @MainActor in self?.setState("__storage", .object(storage)) }
        }
        scriptHost = host
        let runtime = ScriptRuntime(source: source, host: host)
        script = runtime
        scriptState = .object([:])
        scriptMessage = "Starting script…"
        let diagnostics = services.diagnostics
        scriptTask = Task { [weak self] in
            do {
                let meta = try await runtime.load()
                let interval = min(3600, max(1, meta.interval ?? 5))
                while !Task.isCancelled {
                    guard let self else { return }
                    if !(self.services?.updatesPaused ?? false) {
                        let begun = DispatchTime.now()
                        if meta.hasUpdate { self.scriptState = try await runtime.update(state: self.scriptState) }
                        let node = try await runtime.render(state: self.scriptState)
                        diagnostics.recordTiming("script.run", seconds: Double(DispatchTime.now().uptimeNanoseconds - begun.uptimeNanoseconds) / 1e9)
                        if Task.isCancelled { return }
                        self.scriptNode = node
                        self.scriptMessage = nil
                    }
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            } catch is CancellationError {
            } catch {
                self?.reportScript(error)
            }
        }
    }

    private func reportScript(_ error: Error) {
        if let scriptError = error as? ScriptError, scriptError == .cancelled { return }
        scriptMessage = error.localizedDescription
        scriptNode = nil
        services?.diagnostics.log(.error, .script, "\(instance.name): \(error.localizedDescription)", widgetID: id)
        // A script that failed or timed out is stopped, not retried in a loop.
        scriptTask?.cancel()
        script?.cancel()
        script = nil
    }
}

/// Thread-safe bridge between a script (running on its own queue) and the app. It holds a snapshot of the
/// widget's current permissions and data that the main actor refreshes after every change, so a revoked
/// permission is honoured by the script's very next call.
final class RuntimeScriptHost: ScriptHost, @unchecked Sendable {
    private let lock = NSLock()
    private var permissions: PermissionManifest
    private var settings: [String: JSONValue]
    private var data: [String: JSONValue]
    private var storage: [String: JSONValue]
    private let widgetID: String
    private let widgetName: String
    private let engine: DataSourceEngine
    private let metrics: SystemMetricsCollector
    private let diagnostics: DiagnosticsCenter
    private let persist: ([String: JSONValue]) -> Void

    init(instance: WidgetInstance, data: [String: JSONValue], engine: DataSourceEngine, metrics: SystemMetricsCollector,
         diagnostics: DiagnosticsCenter, persist: @escaping ([String: JSONValue]) -> Void) {
        permissions = instance.effectivePermissions
        settings = instance.definition.settings
        self.data = data
        storage = instance.state["__storage"]?.objectValue ?? [:]
        widgetID = instance.id
        widgetName = instance.name
        self.engine = engine; self.metrics = metrics; self.diagnostics = diagnostics; self.persist = persist
    }

    func update(instance: WidgetInstance, data: [String: JSONValue]) {
        lock.lock(); defer { lock.unlock() }
        permissions = instance.effectivePermissions
        settings = instance.definition.settings
        self.data = data
    }

    func scriptPermissions() -> PermissionManifest { lock.lock(); defer { lock.unlock() }; return permissions }
    func scriptSettings() -> JSONValue { lock.lock(); defer { lock.unlock() }; return .object(settings) }
    func scriptMetric(_ name: String) -> JSONValue? { metrics.snapshot(metric: name) }
    func scriptDataSource(_ id: String) -> JSONValue? { lock.lock(); defer { lock.unlock() }; return data[id] }
    func scriptStorageGet(_ key: String) -> JSONValue? { lock.lock(); defer { lock.unlock() }; return storage[key] }

    func scriptStorageSet(_ key: String, _ value: JSONValue) {
        lock.lock()
        storage[key] = value.isNull ? nil : value
        if storage.count > 64 { storage.removeValue(forKey: storage.keys.sorted()[0]) }
        let copy = storage
        lock.unlock()
        persist(copy)
    }

    func scriptLog(_ level: String, _ message: String) {
        let mapped: LogEntry.Level = level == "error" ? .error : (level == "warning" ? .warning : .info)
        diagnostics.log(mapped, .script, "\(widgetName): \(message)", widgetID: widgetID)
    }

    func scriptFetch(url: String, options: JSONValue) async throws -> JSONValue {
        let current = scriptPermissions()
        var headers: [String: String] = [:]
        for (name, value) in options["headers"]?.objectValue ?? [:] { headers[name] = value.displayString }
        let config = DataSourceConfig(id: "script.fetch", name: "\(widgetName) fetch", kind: .rest, url: url,
                                      method: options["method"]?.stringValue ?? "GET", headers: headers,
                                      body: options["body"].map { $0.stringValue ?? $0.compactJSONString }, interval: 0,
                                      cacheTTL: options["cacheSeconds"]?.doubleValue ?? 0, retry: .none, timeout: 15)
        let result = await engine.fetch(config, context: FetchContext(permissions: current, settings: scriptSettings().objectValue ?? [:], widgetID: widgetID))
        if case .ok = result.status, let value = result.value { return value }
        throw ScriptError.permission(result.status.detail ?? "request failed")
    }
}
