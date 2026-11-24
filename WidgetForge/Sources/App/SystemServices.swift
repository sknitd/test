import AppKit
import SwiftUI
import WebKit
import EventKit
import Network
import UserNotifications
import ServiceManagement
import Carbon.HIToolbox

/// Samples system metrics on a background timer, but only while something is watching: each consumer
/// (a widget runtime, the dashboard, a battery automation) retains the hub and releases it when done.
@MainActor
final class MetricsHub: ObservableObject {
    let collector = SystemMetricsCollector()
    /// Latest sample, published for SwiftUI consumers such as the dashboard.
    @Published private(set) var latest: [String: JSONValue] = [:]
    var onSample: (([String: JSONValue]) -> Void)?

    private var consumers = Set<String>()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.widgetforge.metrics", qos: .utility)
    private(set) var interval: Double = 2
    private var paused = false

    func retain(_ consumer: String) {
        consumers.insert(consumer)
        reschedule()
    }

    func release(_ consumer: String) {
        consumers.remove(consumer)
        reschedule()
    }

    var isSampling: Bool { timer != nil }
    var consumerCount: Int { consumers.count }

    func setInterval(_ seconds: Double) {
        interval = min(60, max(1, seconds))
        if timer != nil { stopTimer(); reschedule() }
    }

    func setPaused(_ value: Bool) {
        paused = value
        reschedule()
    }

    private func reschedule() {
        let shouldRun = !consumers.isEmpty && !paused
        if shouldRun, timer == nil { startTimer() } else if !shouldRun, timer != nil { stopTimer() }
    }

    private func startTimer() {
        let collector = self.collector
        let source = DispatchSource.makeTimerSource(queue: queue)
        // Leeway lets the system batch our wake-ups with others to save energy.
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        source.setEventHandler { [weak self] in
            let sample = collector.sample()
            Task { @MainActor in
                guard let self else { return }
                self.latest = sample
                self.onSample?(sample)
            }
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}

/// Side effects widgets and automations can request. Callers check permissions before calling these.
enum SystemActions {
    static func runShortcut(named name: String) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    static func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Controls the Music app through Apple Events. Returns an error message on failure.
    /// macOS has no public API for system-wide "now playing" control, so other players are not supported.
    static func media(_ command: String) -> String? {
        let verb: String
        switch command {
        case "next": verb = "next track"
        case "previous": verb = "previous track"
        default: verb = "playpause"
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return "Music is not running."
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application id \"com.apple.Music\" to \(verb)")?.executeAndReturnError(&error)
        if let error { return (error[NSAppleScript.errorMessage] as? String) ?? "Music did not accept the command." }
        return nil
    }

    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// A WKWebView locked to an allowlist of hosts: no navigation elsewhere, no pop-ups, non-persistent storage.
/// Web content runs in WebKit's own sandboxed process, which is real OS-level isolation.
struct RestrictedWebView: NSViewRepresentable {
    let url: URL
    let allowedHosts: [String]

    func makeCoordinator() -> Coordinator { Coordinator(allowedHosts: allowedHosts) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .clear
        load(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.allowedHosts = allowedHosts
        if view.url?.host != url.host || view.url == nil { load(view) }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    private func load(_ view: WKWebView) {
        guard let host = url.host, PermissionChecker.hostAllowed(host, allowlist: allowedHosts) else {
            view.loadHTMLString("<body style='font:12px -apple-system;color:#888;text-align:center;padding-top:30px'>\(url.host ?? "This site") is not in this widget's web allowlist.</body>", baseURL: nil)
            return
        }
        view.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var allowedHosts: [String]
        init(allowedHosts: [String]) { self.allowedHosts = allowedHosts }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            if url.scheme == "about" { return decisionHandler(.allow) }
            let allowed = ["https", "http"].contains(url.scheme ?? "") && PermissionChecker.hostAllowed(url.host ?? "", allowlist: allowedHosts)
            // Sub-resources load regardless (that is how pages work); top-level navigation is confined.
            decisionHandler(allowed || navigationAction.targetFrame?.isMainFrame == false ? .allow : .cancel)
        }
    }
}

/// User-selected files, remembered as security-scoped bookmarks. Widgets refer to a file by opaque id only.
final class BookmarkStore: FileAccessProvider, @unchecked Sendable {
    private let db: DocumentStore
    init(db: DocumentStore) { self.db = db }

    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var bookmark: Data
    }

    func entries() -> [Entry] { ((try? db.loadAll(Entry.self, from: Collections.bookmarks)) ?? []).sorted { $0.name < $1.name } }

    func add(url: URL) throws -> Entry {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = Entry(id: "file-" + UUID().uuidString.prefix(8).lowercased(), name: url.lastPathComponent, bookmark: bookmark)
        try db.save(entry, in: Collections.bookmarks, id: entry.id)
        return entry
    }

    func remove(_ id: String) { try? db.delete(Collections.bookmarks, id: id) }

    func read(fileID: String) throws -> Data {
        guard let entry = try db.load(Entry.self, from: Collections.bookmarks, id: fileID) else { throw DataSourceError.fileNotAuthorized }
        var stale = false
        let url = try URL(resolvingBookmarkData: entry.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

/// Upcoming events from EventKit. Access is requested the first time a calendar widget asks.
final class EventKitCalendarProvider: CalendarProvider, @unchecked Sendable {
    private let store = EKEventStore()

    func upcomingEvents(limit: Int) async throws -> JSONValue {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else { throw DataSourceError.notAllowed("calendar access (allow it in System Settings → Privacy & Security → Calendars)") }
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(14 * 86_400), calendars: nil)
        let formatter = ISO8601DateFormatter()
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(limit)
        return .array(events.map { event -> JSONValue in
            ["title": .string(event.title ?? "Untitled"), "start": .string(formatter.string(from: event.startDate)),
             "end": .string(formatter.string(from: event.endDate)), "calendar": .string(event.calendar?.title ?? ""),
             "allDay": .bool(event.isAllDay)]
        })
    }
}

/// Reports reachability changes for the "network change" automation trigger.
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private var lastStatus: NWPath.Status?
    private var lastInterface: String?

    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let interface = path.availableInterfaces.first?.name
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.lastStatus != nil && (self.lastStatus != path.status || self.lastInterface != interface)
                self.lastStatus = path.status
                self.lastInterface = interface
                if changed { onChange(path.status == .satisfied) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.widgetforge.network", qos: .utility))
    }

    func stop() { monitor.cancel() }
}

/// A system-wide keyboard shortcut via Carbon's hot-key API, which needs no Accessibility permission and
/// works in the sandbox. Default: ⌃⌥Space.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey)) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: OSType(0x5746_4743), id: 1)      // 'WFGC'
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }
}

struct AppSettings: Codable, Equatable {
    var gridSize = 8.0
    var snapToGrid = true
    var showAlignmentGuides = true
    var metricsInterval = 2.0
    var hotKeyEnabled = true
    var showWidgetsOnLaunch = true
    var ai = AIConfiguration()
    var hasCompletedFirstRun = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gridSize = try c.decodeIfPresent(Double.self, forKey: .gridSize) ?? 8
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        showAlignmentGuides = try c.decodeIfPresent(Bool.self, forKey: .showAlignmentGuides) ?? true
        metricsInterval = try c.decodeIfPresent(Double.self, forKey: .metricsInterval) ?? 2
        hotKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotKeyEnabled) ?? true
        showWidgetsOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showWidgetsOnLaunch) ?? true
        ai = try c.decodeIfPresent(AIConfiguration.self, forKey: .ai) ?? AIConfiguration()
        hasCompletedFirstRun = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstRun) ?? false
    }
}
