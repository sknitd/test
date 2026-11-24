import SwiftUI
import AppKit
import WidgetKit

/// The application's composition root and the single source of UI state. Owns the store and every engine,
/// keeps widget runtimes and overlay windows in step with the store, and performs automation side effects.
@MainActor
final class AppModel: ObservableObject, WidgetRuntimeServices, OverlayHost {
    static let shared = AppModel()

    // MARK: Published UI state
    @Published private(set) var widgets: [WidgetInstance] = []
    @Published private(set) var trash: [WidgetInstance] = []
    @Published private(set) var layouts: [SavedLayout] = []
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileID: String?
    @Published private(set) var automaticProfiles = true
    @Published private(set) var rules: [AutomationRule] = []
    @Published private(set) var automationHistory: [AutomationRunRecord] = []
    @Published private(set) var library: [WidgetDefinition] = []
    @Published private(set) var secretNames: [String] = []
    @Published private(set) var files: [BookmarkStore.Entry] = []
    @Published private(set) var recentEvents: [LogEntry] = []
    @Published private(set) var isEditMode = false
    @Published private(set) var isClickThroughEnabled = false
    @Published private(set) var updatesPaused = false
    @Published private(set) var widgetsVisible = true
    @Published private(set) var storageNote: String?
    @Published var settings = AppSettings() { didSet { if settings != oldValue { settingsChanged(from: oldValue) } } }
    @Published var section: AppSection = .dashboard
    @Published var builderDocument: WidgetDefinition?
    /// Widget id the builder is editing in place; nil when editing a library definition or a new widget.
    @Published var builderWidgetID: String?
    @Published var pendingApproval: PendingApproval?
    @Published var alertMessage: String?

    // MARK: Engines
    let db: DocumentStore
    let store: WidgetStore
    let profileManager: ProfileManager
    let diagnostics = DiagnosticsCenter()
    let secrets: SecretStore
    let bookmarks: BookmarkStore
    let metricsHub = MetricsHub()
    let dataEngine: DataSourceEngine
    let automation: AutomationEngine
    private(set) var overlay: OverlayManager!
    private var runtimes: [String: WidgetRuntime] = [:]
    private var performer: ActionPerformer!
    private let networkWatcher = NetworkWatcher()
    private var hotKey: GlobalHotKey?
    private var housekeeping: Timer?
    private var observers: [NSObjectProtocol] = []
    private var snapshotScheduled = false
    private var logRefreshScheduled = false
    private var lastBatteryEvent = Date.distantPast
    private(set) var launchedAt = Date()
    private var started = false

    struct PendingApproval: Identifiable {
        let id = UUID()
        var definition: WidgetDefinition
        var origin: WidgetOrigin
        var warnings: [String]
    }

    private init() {
        // Persistence: SQLite in Application Support (inside the sandbox container). If it cannot be opened the
        // app still runs, in memory, and says so instead of silently losing data later.
        var note: String?
        var opened: DocumentStore
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("WidgetForge", isDirectory: true)
            opened = try SQLiteDocumentStore(url: directory.appendingPathComponent("widgetforge.sqlite"))
        } catch {
            opened = InMemoryDocumentStore()
            note = "Could not open the database (\(error.localizedDescription)). Changes will not be saved this session."
        }
        db = opened
        store = WidgetStore(db: opened)
        profileManager = ProfileManager(db: opened, store: store)
        secrets = KeychainSecretStore()
        bookmarks = BookmarkStore(db: opened)
        let diagnosticsRef = diagnostics
        dataEngine = DataSourceEngine(transport: URLSessionTransport(), streams: URLSessionStreamTransport(), secrets: secrets, files: bookmarks,
                                      metrics: metricsHub.collector, calendar: EventKitCalendarProvider(), store: opened,
                                      log: { level, message in
                                          diagnosticsRef.log(level == "warning" ? .warning : .info, .network, message)
                                          diagnosticsRef.increment("network.events")
                                      })
        let database = opened
        automation = AutomationEngine(performer: nil,
                                      persist: { rules in try? database.save(rules, in: Collections.automations, id: "rules") },
                                      log: { record in
                                          let level: LogEntry.Level
                                          if case .failed = record.outcome { level = .error } else { level = .info }
                                          diagnosticsRef.log(level, .automation, "\(record.ruleName): \(AppModel.describe(record.outcome)) (\(record.actionsRun) action(s))")
                                      })
        storageNote = note
    }

    nonisolated static func describe(_ outcome: AutomationRunRecord.Outcome) -> String {
        switch outcome {
        case .completed: return "completed"
        case .cancelled: return "cancelled"
        case .failed(let message): return "failed – \(message)"
        case .skipped(let reason): return "skipped – \(reason)"
        }
    }

    // MARK: Startup

    func start() {
        guard !started else { return }
        started = true
        launchedAt = Date()
        settings = (try? db.load(AppSettings.self, from: Collections.settings, id: "app")) ?? AppSettings()
        store.gridSize = settings.gridSize
        store.snapToGrid = settings.snapToGrid
        store.onError = { [weak self] message in self?.diagnostics.log(.error, .app, message) }
        store.load()
        profileManager.load()
        library = ((try? db.loadAll(WidgetDefinition.self, from: Collections.library)) ?? []).sorted { $0.name < $1.name }
        files = bookmarks.entries()
        secretNames = secrets.secretNames()
        widgetsVisible = settings.showWidgetsOnLaunch

        overlay = OverlayManager(host: self)
        performer = ActionPerformer(model: self)
        store.onChange = { [weak self] _ in self?.storeChanged() }
        profileManager.onSwitch = { [weak self] profile, automatic in
            self?.diagnostics.log(.info, .app, "\(automatic ? "Automatically switched" : "Switched") to \(profile?.name ?? "All Widgets")")
        }
        diagnostics.onChange = { [weak self] in
            Task { @MainActor in self?.scheduleLogRefresh() }
        }

        let savedRules = (try? db.load([AutomationRule].self, from: Collections.automations, id: "rules")) ?? []
        rules = savedRules
        let performer = self.performer
        Task {
            await automation.setPerformer(performer)
            await automation.setRules(savedRules)
        }

        if !settings.hasCompletedFirstRun { installStarterContent() }
        profileManager.apply()            // automatic profile restoration after relaunch
        metricsHub.setInterval(settings.metricsInterval)
        metricsHub.onSample = { [weak self] sample in self?.metricsSampled(sample) }
        observeSystem()
        configureHotKey()
        storeChanged()
        applyPendingWidgetKitChanges()
        diagnostics.log(.info, .app, "WidgetForge started with \(store.widgets.count) widget(s)")
        if let storageNote { diagnostics.log(.error, .app, storageNote) }
    }

    /// First launch: put the three core widgets on the desktop and create the example profiles.
    private func installStarterContent() {
        let clock = store.create(from: TemplateLibrary.digitalClock, placement: Placement(x: 40, y: 40, width: 220, height: 110, displayID: nil))
        let cpu = store.create(from: TemplateLibrary.cpuMonitor, placement: Placement(x: 40, y: 168, width: 280, height: 210, displayID: nil))
        let notes = store.create(from: TemplateLibrary.notes, placement: Placement(x: 40, y: 396, width: 260, height: 200, displayID: nil))
        profileManager.upsert(Profile(name: "Work", symbol: "briefcase", widgetIDs: [clock.id, notes.id]))
        profileManager.upsert(Profile(name: "Development", symbol: "hammer", widgetIDs: [clock.id, cpu.id]))
        profileManager.upsert(Profile(name: "Personal", symbol: "house", widgetIDs: [clock.id, notes.id]))
        profileManager.upsert(Profile(name: "Focus", symbol: "moon", widgetIDs: [clock.id]))
        settings.hasCompletedFirstRun = true
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ body: @escaping @MainActor (Notification) -> Void) {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { body(note) }
            })
        }
        watch(NSWorkspace.willSleepNotification) { [weak self] _ in self?.systemWillSleep() }
        watch(NSWorkspace.didWakeNotification) { [weak self] _ in self?.systemDidWake() }
        watch(NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.applyPauseState(screenAsleep: true) }
        watch(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.applyPauseState(screenAsleep: false) }
        watch(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            self?.emit(AutomationEvent(kind: .appLaunched(id), context: ["app": ["bundleID": .string(id)]]))
        }
        watch(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            self?.emit(AutomationEvent(kind: .appActivated(id), context: ["app": ["bundleID": .string(id)]]))
            self?.evaluateProfiles(frontmost: id)
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(SharedContainer.changeNotification), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPendingWidgetKitChanges() }
        })
        networkWatcher.start { [weak self] connected in
            Task { @MainActor in
                self?.diagnostics.log(.info, .network, connected ? "Network available" : "Network unavailable")
                self?.emit(AutomationEvent(kind: .networkChanged, context: ["network": ["connected": .bool(connected)]]))
            }
        }
        // One low-frequency timer drives time-based profiles and timer automations. Tolerance lets macOS coalesce it.
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.housekeepingTick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        housekeeping = timer
    }

    private func housekeepingTick() {
        guard !updatesPaused else { return }
        emit(AutomationEvent(kind: .timerTick))
        evaluateProfiles(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func configureHotKey() {
        hotKey?.unregister()
        hotKey = nil
        guard settings.hotKeyEnabled else { return }
        let key = GlobalHotKey { CommandCenterController.shared.toggle() }
        if !key.register() { diagnostics.log(.warning, .app, "Could not register the ⌃⌥Space shortcut (another app may be using it)") }
        hotKey = key
    }

    private func settingsChanged(from old: AppSettings) {
        try? db.save(settings, in: Collections.settings, id: "app")
        store.gridSize = settings.gridSize
        store.snapToGrid = settings.snapToGrid
        if settings.metricsInterval != old.metricsInterval { metricsHub.setInterval(settings.metricsInterval) }
        if settings.hotKeyEnabled != old.hotKeyEnabled, started { configureHotKey() }
    }

    // MARK: Store synchronisation

    private func storeChanged() {
        widgets = store.widgets
        trash = store.trash
        layouts = store.layouts
        profiles = profileManager.profiles
        activeProfileID = profileManager.state.activeID
        automaticProfiles = profileManager.state.automaticSwitching
        syncRuntimes()
        overlay?.sync()
        scheduleSnapshot()
        updateBatteryWatch()
    }

    /// Runtimes exist only for widgets that are actually on screen; everything else is fully suspended.
    private func syncRuntimes() {
        let active = widgetsVisible ? store.widgets.filter { !$0.hidden } : []
        let activeIDs = Set(active.map(\.id))
        for (id, runtime) in runtimes where !activeIDs.contains(id) {
            runtime.stop()
            runtimes[id] = nil
        }
        for widget in active {
            if let runtime = runtimes[widget.id] {
                if runtime.instance != widget { runtime.adopt(widget) }
            } else {
                let runtime = WidgetRuntime(instance: widget, services: self)
                runtimes[widget.id] = runtime
                runtime.start()
            }
        }
    }

    func runtime(for widgetID: String) -> WidgetRuntime? { runtimes[widgetID] }
    var runningRuntimeCount: Int { runtimes.count }

    func runtime(_ runtime: WidgetRuntime, didChange instance: WidgetInstance) {
        store.update(instance.id) { $0.state = instance.state }
    }

    func runtime(_ runtime: WidgetRuntime, didEmit event: AutomationEvent) { emit(event) }

    func notify(title: String, body: String) { SystemActions.notify(title: title, body: body) }

    func overlayDidLog(_ message: String) { diagnostics.log(.info, .layout, message) }

    private func scheduleLogRefresh() {
        guard !logRefreshScheduled else { return }
        logRefreshScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            self.logRefreshScheduled = false
            self.recentEvents = Array(self.diagnostics.snapshot(minimumLevel: .info).suffix(200))
            self.automationHistory = await self.automation.history
        }
    }

    // MARK: Widget commands

    /// Add a widget. Content the user did not author here (imports, AI output) goes through the approval sheet.
    func addWidget(_ definition: WidgetDefinition, origin: WidgetOrigin = .template) {
        if origin == .imported || origin == .ai {
            let report = SchemaValidator.validate(definition: (try? JSONValue.encode(definition)) ?? .null)
            guard report.isValid else { alertMessage = report.errors.joined(separator: "\n"); return }
            pendingApproval = PendingApproval(definition: definition, origin: origin, warnings: report.warnings)
            return
        }
        place(definition, granted: definition.permissions, origin: origin, trustScript: true)
    }

    /// Called by the approval sheet with exactly the permissions the user left switched on.
    func approve(_ approval: PendingApproval, granted: PermissionManifest, trustScript: Bool) {
        pendingApproval = nil
        place(approval.definition, granted: granted, origin: approval.origin, trustScript: trustScript)
    }

    @discardableResult
    private func place(_ definition: WidgetDefinition, granted: PermissionManifest, origin: WidgetOrigin, trustScript: Bool) -> WidgetInstance {
        let displays = ScreenGeometry.displays()
        let occupied = store.widgets.filter { !$0.hidden }.compactMap { LayoutEngine.globalRect(for: $0.placement, in: displays) }
        var placement: Placement?
        if let main = displays.first(where: \.isMain) ?? displays.first {
            let slot = LayoutEngine.freeSlot(size: definition.size, occupied: occupied, in: main.frame)
            placement = LayoutEngine.placement(forGlobal: slot, in: displays)
        }
        let widget = store.create(from: definition, placement: placement, granted: granted, origin: origin, scriptTrusted: trustScript)
        if let active = profileManager.active { profileManager.setMembership(widget.id, in: active.id, member: true); storeChanged() }
        if !widgetsVisible { setWidgetsVisible(true) }
        diagnostics.log(.info, .widget, "Added \(widget.name)", widgetID: widget.id)
        return widget
    }

    func deleteWidget(_ id: String) { store.delete(id) }
    func restoreWidget(_ id: String) { store.restore(id) }
    func emptyTrash() { store.emptyTrash() }
    func duplicateWidget(_ id: String) { store.duplicate(id) }
    func updateWidget(_ id: String, _ body: (inout WidgetInstance) -> Void) { store.update(id, body) }
    func refreshWidget(_ id: String) { runtimes[id]?.restart() }
    func alignWidgets(_ ids: [String], _ mode: AlignMode) { store.align(ids, mode: mode) }
    func groupWidgets(_ ids: [String]) { store.group(ids) }
    func ungroupWidgets(_ groupID: String) { store.ungroup(groupID) }
    func snapAllToGrid() { store.snapAll() }
    func saveLayout(named name: String) { store.saveLayout(named: name) }
    func restoreLayout(_ id: String) { store.restoreLayout(id) }
    func deleteLayout(_ id: String) { store.deleteLayout(id) }

    /// Replace a widget's definition after editing its settings or redesigning it in the builder. Hosts the
    /// user typed themselves are added to the allowlist; nothing else is granted implicitly.
    func updateDefinition(_ id: String, _ definition: WidgetDefinition) {
        store.update(id) { widget in
            var updated = definition
            updated.id = widget.definition.id
            let required = PermissionChecker.required(for: updated)
            updated.permissions = updated.permissions.union(required)
            if widget.origin != .imported && widget.origin != .ai {
                widget.granted = widget.granted.union(required)
            } else {
                widget.granted.network = Array(Set(widget.granted.network + required.network.filter { host in
                    updated.settings.values.contains { $0.stringValue?.contains(host) == true }
                })).sorted()
            }
            widget.definition = updated
        }
    }

    func setEditMode(_ on: Bool) {
        isEditMode = on
        if on, !widgetsVisible { setWidgetsVisible(true) }
        overlay.sync()
    }

    func setClickThrough(_ on: Bool) {
        isClickThroughEnabled = on
        overlay.sync()
    }

    func setWidgetsVisible(_ visible: Bool) {
        widgetsVisible = visible
        overlay.setVisible(visible)
        storeChanged()
    }

    func setUpdatesPaused(_ paused: Bool) {
        updatesPaused = paused
        applyPauseState(screenAsleep: false)
        diagnostics.log(.info, .app, paused ? "Updates paused" : "Updates resumed")
    }

    private func applyPauseState(screenAsleep: Bool) {
        let suspend = updatesPaused || screenAsleep
        metricsHub.setPaused(suspend)
        Task {
            if suspend { await dataEngine.suspend() } else { await dataEngine.resume() }
            await automation.setPaused(updatesPaused)
        }
    }

    private func systemWillSleep() {
        diagnostics.log(.info, .app, "System sleeping: suspending all widget work")
        applyPauseState(screenAsleep: true)
    }

    private func systemDidWake() {
        diagnostics.log(.info, .app, "System woke: resuming")
        applyPauseState(screenAsleep: false)
        overlay.sync()
    }

    func widgetMenu(for widgetID: String) -> NSMenu {
        let menu = NSMenu()
        guard let widget = store.widget(widgetID) else { return menu }
        func item(_ title: String, state: Bool? = nil, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, handler: action)
            if let state { item.state = state ? .on : .off }
            menu.addItem(item)
        }
        item("Edit in Builder…") { [weak self] in self?.openInBuilder(widgetID) }
        item("Refresh") { [weak self] in self?.refreshWidget(widgetID) }
        menu.addItem(.separator())
        item("Lock Position", state: widget.locked) { [weak self] in self?.updateWidget(widgetID) { $0.locked.toggle() } }
        item("Pin Above Windows", state: widget.pinned) { [weak self] in self?.updateWidget(widgetID) { $0.pinned.toggle() } }
        item("Click-Through", state: widget.clickThrough) { [weak self] in self?.updateWidget(widgetID) { $0.clickThrough.toggle() } }
        menu.addItem(.separator())
        item(isEditMode ? "Finish Arranging" : "Arrange Widgets") { [weak self] in self?.setEditMode(!(self?.isEditMode ?? false)) }
        item("Duplicate") { [weak self] in self?.duplicateWidget(widgetID) }
        item("Hide") { [weak self] in self?.updateWidget(widgetID) { $0.hidden = true } }
        item("Delete") { [weak self] in self?.deleteWidget(widgetID) }
        return menu
    }

    // MARK: Builder and library

    func openInBuilder(_ widgetID: String) {
        guard let widget = store.widget(widgetID) else { return }
        builderDocument = widget.definition
        builderWidgetID = widgetID
        section = .builder
        NotificationCenter.default.post(name: .widgetForgeShowMainWindow, object: nil)
    }

    func newBuilderDocument(from definition: WidgetDefinition? = nil) {
        var document = definition ?? WidgetDefinition(name: "New Widget", size: WidgetSize(320, 200), root: WidgetNode(.canvas))
        document.id = UUID().uuidString
        builderDocument = document
        builderWidgetID = nil
        section = .builder
    }

    func saveToLibrary(_ definition: WidgetDefinition) {
        var saved = definition
        saved.permissions = saved.permissions.union(PermissionChecker.required(for: saved))
        library.removeAll { $0.id == saved.id }
        library.append(saved)
        library.sort { $0.name < $1.name }
        try? db.save(saved, in: Collections.library, id: saved.id)
    }

    func removeFromLibrary(_ id: String) {
        library.removeAll { $0.id == id }
        try? db.delete(Collections.library, id: id)
    }

    func exportWidget(_ definition: WidgetDefinition) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(definition.name).\(WidgetPackage.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try WidgetPackageCodec.export(definition).write(to: url, options: .atomic) }
        catch { alertMessage = "Export failed: \(error.localizedDescription)" }
    }

    func importWidget() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a .wfwidget or .json widget file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importWidget(from: url)
    }

    func importWidget(from url: URL) {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let imported = try WidgetPackageCodec.importPackage(try Data(contentsOf: url))
            pendingApproval = PendingApproval(definition: imported.definition, origin: .imported, warnings: imported.report.warnings)
            diagnostics.log(.info, .security, "Validated import \"\(imported.definition.name)\"")
        } catch {
            alertMessage = "Import failed: \(error.localizedDescription)"
            diagnostics.log(.warning, .security, "Rejected import: \(error.localizedDescription)")
        }
    }

    // MARK: Secrets and files

    func saveSecret(name: String, value: String, hosts: [String]) {
        do {
            try secrets.setSecret(Secret(value: value, hosts: hosts), named: name)
            secretNames = secrets.secretNames()
            runtimes.values.forEach { $0.restart() }
        } catch { alertMessage = "Could not save to the Keychain: \(error.localizedDescription)" }
    }

    func deleteSecret(_ name: String) {
        try? secrets.setSecret(nil, named: name)
        secretNames = secrets.secretNames()
    }

    func secretHosts(_ name: String) -> [String] { secrets.secret(named: name)?.hosts ?? [] }

    func chooseFile() -> BookmarkStore.Entry? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = "Choose a JSON or CSV file to use as a data source"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let entry = try bookmarks.add(url: url)
            files = bookmarks.entries()
            return entry
        } catch {
            alertMessage = "Could not remember that file: \(error.localizedDescription)"
            return nil
        }
    }

    func removeFile(_ id: String) {
        bookmarks.remove(id)
        files = bookmarks.entries()
    }

    // MARK: Profiles

    func activateProfile(_ id: String?) {
        profileManager.activate(id)
        storeChanged()
    }

    func saveProfile(_ profile: Profile) {
        profileManager.upsert(profile)
        if profile.id == profileManager.state.activeID { profileManager.apply() }
        storeChanged()
    }

    func deleteProfile(_ id: String) {
        let wasActive = profileManager.state.activeID == id
        profileManager.delete(id)
        if wasActive { profileManager.apply() }
        storeChanged()
    }

    func setAutomaticProfiles(_ enabled: Bool) {
        profileManager.setAutomaticSwitching(enabled)
        storeChanged()
    }

    private func evaluateProfiles(frontmost: String?) {
        // Our own windows becoming frontmost must not flip profiles.
        guard frontmost != Bundle.main.bundleIdentifier else { return }
        let context = ProfileContext(date: Date(), frontmostBundleID: frontmost, displays: ScreenGeometry.displays())
        if profileManager.evaluate(context) { storeChanged() }
    }

    // MARK: Automation

    func emit(_ event: AutomationEvent) {
        guard !rules.isEmpty else { return }
        Task { await automation.handle(event) }
    }

    func saveRule(_ rule: AutomationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
        Task { await automation.upsert(rule) }
        updateBatteryWatch()
    }

    func deleteRule(_ id: String) {
        rules.removeAll { $0.id == id }
        Task { await automation.remove(id) }
        updateBatteryWatch()
    }

    func runRule(_ id: String) {
        Task {
            await automation.runManually(id)
            rules = await automation.rules
        }
    }

    func cancelRule(_ id: String) { Task { await automation.cancel(id) } }

    /// Battery automations need periodic samples even when no battery widget is visible.
    private func updateBatteryWatch() {
        let needed = rules.contains { rule in
            if rule.enabled, case .batteryBelow = rule.trigger { return true }
            return false
        }
        if needed { metricsHub.retain("automation.battery") } else { metricsHub.release("automation.battery") }
    }

    private func metricsSampled(_ sample: [String: JSONValue]) {
        guard let battery = sample["battery"], battery["present"]?.boolValue == true, let level = battery["level"]?.doubleValue,
              Date().timeIntervalSince(lastBatteryEvent) >= 30 else { return }
        lastBatteryEvent = Date()
        emit(AutomationEvent(kind: .battery(percent: level * 100, onBattery: battery["onBattery"]?.boolValue ?? false), context: ["battery": battery]))
    }

    // MARK: WidgetKit bridge

    private func scheduleSnapshot() {
        guard !snapshotScheduled else { return }
        snapshotScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.snapshotScheduled = false
            self?.publishSnapshot()
        }
    }

    /// Write the data the WidgetKit extension draws from, then ask WidgetKit to reload (it decides when).
    func publishSnapshot() {
        let snapshot = SharedSnapshot(widgets: store.widgets.map { widget in
            let runtime = runtimes[widget.id]
            var data: [String: JSONValue] = [:]
            if let context = runtime?.context.objectValue {
                for source in widget.definition.dataSources where source.kind != .systemMetric { data[source.id] = context[source.id] }
            }
            return SnapshotWidget(id: widget.id, name: widget.name, symbol: widget.definition.symbol, definition: widget.definition,
                                  state: widget.state, allowsSystemMetrics: widget.effectivePermissions.systemMetrics, data: data,
                                  statuses: (runtime?.sourceStatuses ?? [:]).mapValues(\.json), scriptNode: runtime?.scriptNode)
        }, updatedAt: Date())
        if SharedContainer.writeSnapshot(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.widgetKind)
        }
    }

    private func applyPendingWidgetKitChanges() {
        for change in SharedContainer.drainPending() {
            store.update(change.widgetID) { $0.state[change.key] = change.value }
        }
    }

    // MARK: Diagnostics

    /// Measured resource use of this process since launch.
    func resourceUsage() -> (memoryBytes: Double?, cpuSeconds: Double?, uptime: Double) {
        (ProcessMetrics.memoryFootprint(), ProcessMetrics.cpuTime(), Date().timeIntervalSince(launchedAt))
    }

    func shutdown() {
        profileManager.captureActiveLayout()
        publishSnapshot()
        runtimes.values.forEach { $0.stop() }
        networkWatcher.stop()
        hotKey?.unregister()
        housekeeping?.invalidate()
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// Performs automation actions on behalf of the engine. Automations are authored by the user, so they act
/// with the user's authority rather than a widget's permission manifest.
final class ActionPerformer: AutomationActionPerformer, @unchecked Sendable {
    private weak var model: AppModel?
    init(model: AppModel) { self.model = model }

    func perform(_ action: AutomationAction, rule: AutomationRule) async throws -> [AutomationEvent] {
        await MainActor.run { () -> [AutomationEvent] in
            guard let model else { return [] }
            switch action {
            case .showWidget(let id): model.updateWidget(id) { $0.hidden = false }
            case .hideWidget(let id): model.updateWidget(id) { $0.hidden = true }
            case .switchProfile(let id): model.activateProfile(id.isEmpty ? nil : id)
            case .refreshData(let id):
                if id.isEmpty { model.widgets.forEach { model.refreshWidget($0.id) } } else { model.refreshWidget(id) }
            case .notify(let title, let body): SystemActions.notify(title: title, body: body)
            case .openURL(let text):
                if let url = URL(string: text), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            case .launchApp(let bundleID): SystemActions.launchApp(bundleID: bundleID)
            case .runShortcut(let name): SystemActions.runShortcut(named: name)
            case .setWidgetState(let id, let key, let value): model.updateWidget(id) { $0.state[key] = value }
            case .wait: break
            }
            return []
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, widgets, builder, templates, dataSources, automations, profiles, marketplace, diagnostics, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .widgets: return "My Widgets"
        case .builder: return "Widget Builder"
        case .templates: return "Templates"
        case .dataSources: return "Data Sources"
        case .automations: return "Automations"
        case .profiles: return "Profiles"
        case .marketplace: return "Marketplace"
        case .diagnostics: return "Diagnostics"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .widgets: return "rectangle.3.group"
        case .builder: return "hammer"
        case .templates: return "square.stack.3d.up"
        case .dataSources: return "antenna.radiowaves.left.and.right"
        case .automations: return "bolt"
        case .profiles: return "person.crop.rectangle.stack"
        case .marketplace: return "shippingbox"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}
