import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: Data Sources

struct DataSourcesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var secretName = ""
    @State private var secretValue = ""
    @State private var secretHosts = ""
    @State private var probe = DataSourceConfig(id: "test", kind: .rest, url: "https://", interval: 0)
    @State private var probeResult = ""
    @State private var probing = false

    var body: some View {
        Page(title: "Data Sources", subtitle: "Live data, credentials and files your widgets may use") {
            Button("Clear Cache") { Task { await model.dataEngine.clearCache() } }
        } content: {
            Card(title: "Sources in Use") {
                let rows = model.widgets.flatMap { widget in WidgetContextBuilder.effectiveSources(for: widget.definition).map { (widget, $0) } }
                if rows.isEmpty { Text("No widget uses a data source yet.").foregroundStyle(.secondary) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let status = model.runtime(for: row.0.id)?.sourceStatuses[row.1.id] ?? (row.0.hidden ? .suspended : .idle)
                    HStack {
                        Circle().fill(status == .ok ? Color.green : (status.isHealthy ? Color.gray : Color.orange)).frame(width: 8, height: 8)
                        Text(row.0.name).frame(width: 170, alignment: .leading).lineLimit(1)
                        Text(row.1.kind.title).font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                        Text(row.1.kind.usesNetwork ? row.1.url : (row.1.metric ?? row.1.id)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(row.1.effectiveInterval > 0 ? "every \(Formatters.duration(row.1.effectiveInterval))" : "once").font(.caption).foregroundStyle(.secondary)
                        Text(status.label).font(.caption.weight(.medium)).help(status.detail ?? status.label)
                    }
                }
                Text("Refresh intervals have a floor per source type (REST 15 s, local HTTP and files 2 s, metrics 1 s). Hidden widgets and a sleeping Mac make no requests.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Card(title: "Secrets (stored in your Keychain)") {
                Text("Reference a secret from a data source as {{secret:NAME}}. A secret is only ever sent to the hosts you list for it, and never appears in exported widgets.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.secretNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "key.fill")
                        Text(name).font(.body.monospaced())
                        Text(model.secretHosts(name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { model.deleteSecret(name) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete secret \(name)")
                    }
                }
                HStack {
                    TextField("NAME", text: $secretName).frame(width: 170)
                    SecureField("Value", text: $secretValue).frame(width: 200)
                    TextField("Allowed hosts, comma separated", text: $secretHosts)
                    Button("Save") {
                        let hosts = secretHosts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                        model.saveSecret(name: secretName.trimmingCharacters(in: .whitespaces), value: secretValue, hosts: hosts)
                        secretName = ""; secretValue = ""; secretHosts = ""
                    }
                    .disabled(secretName.trimmingCharacters(in: .whitespaces).isEmpty || secretValue.isEmpty || secretHosts.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
            }

            Card(title: "Files") {
                Text("JSON and CSV files you choose here can be bound to a widget in the Builder. Widgets never see file paths.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.files) { file in
                    HStack {
                        Image(systemName: "doc")
                        Text(file.name)
                        Text(file.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) { model.removeFile(file.id) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Forget file \(file.name)")
                    }
                }
                Button("Choose File…") { _ = model.chooseFile() }
            }

            Card(title: "Try a Request") {
                Text("Fetches once with only the host you type allowed, exactly as a widget would.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Kind", selection: $probe.kind) {
                        Text("REST").tag(DataSourceKind.rest)
                        Text("Local HTTP").tag(DataSourceKind.localHTTP)
                    }
                    .labelsHidden().frame(width: 120)
                    TextField("https://api.example.com/data", text: $probe.url).textFieldStyle(.roundedBorder)
                    TextField("JSON path (optional)", text: Binding(get: { probe.transform ?? "" }, set: { probe.transform = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                    Button(probing ? "Fetching…" : "Fetch") { runProbe() }.disabled(probing)
                }
                if !probeResult.isEmpty {
                    ScrollView { Text(probeResult).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .frame(maxHeight: 180)
                }
            }
        }
    }

    private func runProbe() {
        guard let host = URL(string: DataSourceEngine.stripSecrets(probe.url))?.host else { probeResult = "Enter a full URL."; return }
        probing = true
        var config = probe
        config.retry = .none
        Task {
            let result = await model.dataEngine.fetch(config, context: FetchContext(permissions: PermissionManifest(network: [host]), widgetID: "probe"))
            probing = false
            let head = "\(result.status.label)\(result.status.detail.map { ": \($0)" } ?? "") · \(Int(result.duration * 1000)) ms"
            probeResult = head + "\n" + String((result.value?.prettyJSONString ?? "").prefix(4000))
        }
    }
}

// MARK: Automations

struct AutomationsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Page(title: "Automations", subtitle: "When something happens, change your desktop") {
            Menu("New Automation") {
                Button("Blank") { model.saveRule(AutomationRule(name: "New Automation", trigger: .manual, actions: [])) }
                Button("Low battery alert") {
                    let battery = model.widgets.first { $0.definition.name.contains("Battery") }?.id ?? ""
                    model.saveRule(AutomationRule(name: "Low battery", trigger: .batteryBelow(percent: 20),
                                                  actions: [.showWidget(id: battery), .setWidgetState(widgetID: battery, key: "highlight", value: true),
                                                            .notify(title: "Battery low", body: "Below 20%. Plug in soon.")], cooldown: 600))
                }
                Button("Refresh everything when the network returns") {
                    model.saveRule(AutomationRule(name: "Network refresh", trigger: .networkChange, conditions: [Condition("network.connected", .equals, true)],
                                                  actions: [.refreshData(widgetID: "")], cooldown: 30))
                }
            }
            .fixedSize()
        } content: {
            if model.rules.isEmpty {
                ContentUnavailableView("No Automations", systemImage: "bolt", description: Text("Create one from the menu above."))
            }
            ForEach(model.rules) { rule in RuleEditor(rule: rule) }
            Card(title: "History") {
                if model.automationHistory.isEmpty { Text("No runs yet").foregroundStyle(.secondary) }
                ForEach(model.automationHistory.suffix(12).reversed()) { record in
                    HStack {
                        Text(record.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(record.ruleName).font(.callout.weight(.medium))
                        Text(AppModel.describe(record.outcome)).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct RuleEditor: View {
    @EnvironmentObject private var model: AppModel
    let rule: AutomationRule

    var body: some View {
        Card {
            HStack {
                Toggle("", isOn: Binding(get: { rule.enabled }, set: { on in update { $0.enabled = on } })).labelsHidden().toggleStyle(.switch)
                    .accessibilityLabel("Enabled")
                TextField("Name", text: Binding(get: { rule.name }, set: { name in update { $0.name = name } })).textFieldStyle(.plain).font(.headline)
                Spacer()
                Text("Ran \(rule.runCount)×").font(.caption).foregroundStyle(.secondary)
                Button("Run Now") { model.runRule(rule.id) }
                Button("Stop") { model.cancelRule(rule.id) }
                Button(role: .destructive) { model.deleteRule(rule.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete automation")
            }
            // Trigger
            HStack {
                Text("When").frame(width: 50, alignment: .leading).foregroundStyle(.secondary)
                Picker("Trigger", selection: Binding(get: { rule.trigger.kind }, set: { kind in update { $0.trigger = AutomationTrigger.make(kind: kind) } })) {
                    ForEach(AutomationTrigger.kinds, id: \.self) { Text(AutomationTrigger.make(kind: $0).kindTitle).tag($0) }
                }
                .labelsHidden().frame(width: 220)
                triggerFields
                Spacer()
            }
            // Conditions
            ForEach(Array(rule.conditions.enumerated()), id: \.offset) { index, condition in
                HStack {
                    Text("If").frame(width: 50, alignment: .leading).foregroundStyle(.secondary)
                    ConditionFields(condition: Binding(get: { condition }, set: { new in update { $0.conditions[index] = new } }))
                    Button { update { $0.conditions.remove(at: index) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        .accessibilityLabel("Remove condition")
                }
            }
            // Actions
            ForEach(Array(rule.actions.enumerated()), id: \.offset) { index, action in
                HStack {
                    Text(index == 0 ? "Then" : "").frame(width: 50, alignment: .leading).foregroundStyle(.secondary)
                    Picker("Action", selection: Binding(get: { action.kind }, set: { kind in update { $0.actions[index] = AutomationAction.make(kind: kind) } })) {
                        ForEach(AutomationAction.kinds, id: \.self) { Text(AutomationAction.make(kind: $0).kindTitle).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                    ActionFields(action: Binding(get: { action }, set: { new in update { $0.actions[index] = new } }))
                    Spacer()
                    Button { update { $0.actions.remove(at: index) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        .accessibilityLabel("Remove action")
                }
            }
            HStack {
                Button("Add Action") { update { $0.actions.append(.notify(title: "WidgetForge", body: rule.name)) } }
                Button("Add Condition") { update { $0.conditions.append(Condition("battery.level", .lessThan, 0.5)) } }
                Spacer()
                Text("Cooldown").font(.caption)
                TextField("s", value: Binding(get: { rule.cooldown }, set: { v in update { $0.cooldown = max(0, v) } }), format: .number).frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Text("seconds").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var triggerFields: some View {
        switch rule.trigger {
        case .timer(let seconds):
            TextField("seconds", value: Binding(get: { seconds }, set: { v in update { $0.trigger = .timer(seconds: max(10, v)) } }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 80)
            Text("seconds (minimum 10)").font(.caption).foregroundStyle(.secondary)
        case .appLaunch(let id):
            TextField("Bundle ID (blank = any app)", text: Binding(get: { id }, set: { v in update { $0.trigger = .appLaunch(bundleID: v) } })).textFieldStyle(.roundedBorder).frame(width: 260)
        case .appActivate(let id):
            TextField("Bundle ID (blank = any app)", text: Binding(get: { id }, set: { v in update { $0.trigger = .appActivate(bundleID: v) } })).textFieldStyle(.roundedBorder).frame(width: 260)
        case .batteryBelow(let percent):
            Slider(value: Binding(get: { percent }, set: { v in update { $0.trigger = .batteryBelow(percent: v.rounded()) } }), in: 5...95).frame(width: 160)
            Text("\(Int(percent))%").monospacedDigit()
        case .widgetInteraction(let name):
            TextField("Trigger name", text: Binding(get: { name }, set: { v in update { $0.trigger = .widgetInteraction(name: v) } })).textFieldStyle(.roundedBorder).frame(width: 200)
        case .dataCondition(let widgetID, let condition):
            WidgetPicker(selection: Binding(get: { widgetID }, set: { v in update { $0.trigger = .dataCondition(widgetID: v, condition: condition) } }), allowsAny: true)
            ConditionFields(condition: Binding(get: { condition }, set: { v in update { $0.trigger = .dataCondition(widgetID: widgetID, condition: v) } }))
        case .networkChange, .manual:
            EmptyView()
        }
    }

    private func update(_ body: (inout AutomationRule) -> Void) {
        var copy = rule
        body(&copy)
        model.saveRule(copy)
    }
}

extension AutomationTrigger {
    var kindTitle: String {
        switch self {
        case .timer: return "Timer"
        case .appLaunch: return "App launches"
        case .appActivate: return "App becomes active"
        case .networkChange: return "Network changes"
        case .batteryBelow: return "Battery falls below"
        case .widgetInteraction: return "Widget interaction"
        case .dataCondition: return "Data condition becomes true"
        case .manual: return "Manual"
        }
    }
}

extension AutomationAction {
    var kindTitle: String {
        switch self {
        case .showWidget: return "Show widget"
        case .hideWidget: return "Hide widget"
        case .switchProfile: return "Switch profile"
        case .refreshData: return "Update data"
        case .notify: return "Show notification"
        case .openURL: return "Open URL"
        case .launchApp: return "Launch application"
        case .runShortcut: return "Run Shortcut"
        case .setWidgetState: return "Set widget state"
        case .wait: return "Wait"
        }
    }
}

struct WidgetPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: String
    var allowsAny = false

    var body: some View {
        Picker("Widget", selection: $selection) {
            Text(allowsAny ? "Any widget" : "Choose…").tag("")
            ForEach(model.widgets) { Text($0.name).tag($0.id) }
        }
        .labelsHidden().frame(width: 180)
    }
}

struct ConditionFields: View {
    @Binding var condition: Condition

    var body: some View {
        TextField("path, e.g. battery.level", text: $condition.path).textFieldStyle(.roundedBorder).frame(width: 180)
        Picker("Operator", selection: $condition.op) {
            ForEach(Condition.Operator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden().frame(width: 90)
        TextField("value", text: Binding(get: { condition.value.displayString }, set: { text in
            if let number = Double(text) { condition.value = .number(number) }
            else if text == "true" || text == "false" { condition.value = .bool(text == "true") }
            else { condition.value = .string(text) }
        }))
        .textFieldStyle(.roundedBorder).frame(width: 110)
    }
}

struct ActionFields: View {
    @EnvironmentObject private var model: AppModel
    @Binding var action: AutomationAction

    var body: some View {
        switch action {
        case .showWidget(let id): WidgetPicker(selection: Binding(get: { id }, set: { action = .showWidget(id: $0) }))
        case .hideWidget(let id): WidgetPicker(selection: Binding(get: { id }, set: { action = .hideWidget(id: $0) }))
        case .refreshData(let id): WidgetPicker(selection: Binding(get: { id }, set: { action = .refreshData(widgetID: $0) }), allowsAny: true)
        case .switchProfile(let id):
            Picker("Profile", selection: Binding(get: { id }, set: { action = .switchProfile(id: $0) })) {
                Text("All Widgets").tag("")
                ForEach(model.profiles) { Text($0.name).tag($0.id) }
            }
            .labelsHidden().frame(width: 180)
        case .notify(let title, let body):
            TextField("Title", text: Binding(get: { title }, set: { action = .notify(title: $0, body: body) })).textFieldStyle(.roundedBorder).frame(width: 150)
            TextField("Message", text: Binding(get: { body }, set: { action = .notify(title: title, body: $0) })).textFieldStyle(.roundedBorder)
        case .openURL(let url):
            TextField("https://", text: Binding(get: { url }, set: { action = .openURL($0) })).textFieldStyle(.roundedBorder)
        case .launchApp(let id):
            TextField("Bundle ID", text: Binding(get: { id }, set: { action = .launchApp(bundleID: $0) })).textFieldStyle(.roundedBorder)
        case .runShortcut(let name):
            TextField("Shortcut name", text: Binding(get: { name }, set: { action = .runShortcut(name: $0) })).textFieldStyle(.roundedBorder)
        case .setWidgetState(let id, let key, let value):
            WidgetPicker(selection: Binding(get: { id }, set: { action = .setWidgetState(widgetID: $0, key: key, value: value) }))
            TextField("key", text: Binding(get: { key }, set: { action = .setWidgetState(widgetID: id, key: $0, value: value) })).textFieldStyle(.roundedBorder).frame(width: 100)
            TextField("value", text: Binding(get: { value.displayString }, set: { text in
                let parsed: JSONValue = Double(text).map { JSONValue.number($0) } ?? (text == "true" ? JSONValue.bool(true) : (text == "false" ? JSONValue.bool(false) : JSONValue.string(text)))
                action = .setWidgetState(widgetID: id, key: key, value: parsed)
            })).textFieldStyle(.roundedBorder).frame(width: 100)
        case .wait(let seconds):
            TextField("seconds", value: Binding(get: { seconds }, set: { action = .wait(seconds: max(0, $0)) }), format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
            Text("seconds").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Marketplace (local library)

struct MarketplaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var dropTargeted = false

    var body: some View {
        let items = FuzzyMatcher.filter(model.library, query: query) { "\($0.name) \($0.summary)" }
        Page(title: "Marketplace", subtitle: "Your local widget library. Import, export and share widget files.") {
            HStack {
                TextField("Search library", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                Button { model.importWidget() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            }
        } content: {
            Label("WidgetForge has no online store and contacts no server. Widgets are shared as .wfwidget files, validated on import, and never include your secrets, files or notes. Imported scripts stay off until you trust them.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(height: 64)
                .overlay(Label("Drop a .wfwidget file here to import it", systemImage: "tray.and.arrow.down").foregroundStyle(.secondary))
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.importWidget(from: url)
                    return true
                } isTargeted: { dropTargeted = $0 }
            if items.isEmpty {
                ContentUnavailableView("Library Empty", systemImage: "shippingbox", description: Text("Save a widget from the Builder or My Widgets, or import one."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(items) { definition in
                    TemplateCard(definition: definition) {
                        Button("Add") { model.addWidget(definition, origin: .builder) }.buttonStyle(.borderedProminent)
                        Menu("More") {
                            Button("Edit in Builder") { model.builderDocument = definition; model.builderWidgetID = nil; model.section = .builder }
                            Button("Export…") { model.exportWidget(definition) }
                            Button("Remove", role: .destructive) { model.removeFromLibrary(definition.id) }
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: Diagnostics

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var level = LogEntry.Level.info
    @State private var category: LogEntry.Category?
    @State private var stats = DataEngineStats()
    @State private var usage: (memoryBytes: Double?, cpuSeconds: Double?, uptime: Double) = (nil, nil, 0)
    @State private var timings: [String: TimingStats] = [:]
    @State private var windows: [[String: String]] = []
    private let ticker = Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Page(title: "Diagnostics", subtitle: "Measured at runtime on this Mac") {
            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnostics.exportText(), forType: .string)
                }
                Button("Clear") { model.diagnostics.clear() }
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Process") {
                    LabeledContent("Memory footprint", value: usage.memoryBytes.map { Formatters.bytes($0) } ?? "–")
                    LabeledContent("CPU time since launch", value: usage.cpuSeconds.map { String(format: "%.2f s", $0) } ?? "–")
                    LabeledContent("Average CPU since launch", value: usage.cpuSeconds.map { String(format: "%.2f%%", usage.uptime > 0 ? $0 / usage.uptime * 100 : 0) } ?? "–")
                    LabeledContent("Uptime", value: Formatters.duration(usage.uptime))
                    LabeledContent("Metric sampling", value: model.metricsHub.isSampling ? "every \(Int(model.metricsHub.interval)) s for \(model.metricsHub.consumerCount) consumer(s)" : "stopped")
                }
                Card(title: "Network") {
                    LabeledContent("Requests", value: "\(stats.requests)")
                    LabeledContent("Failures", value: "\(stats.failures)")
                    LabeledContent("Retries", value: "\(stats.retries)")
                    LabeledContent("Cache hits", value: "\(stats.cacheHits)")
                    LabeledContent("Received", value: Formatters.bytes(Double(stats.bytesReceived)))
                }
                Card(title: "Timings") {
                    timingRow("Widget update latency", timings["widget.updateLatency"])
                    timingRow("Script run (update + render)", timings["script.run"])
                    LabeledContent("Script watchdog", value: ScriptRuntime.watchdogAvailable ? "Available" : "Unavailable (scripts disabled)")
                }
            }
            Card(title: "Overlay Windows") {
                if windows.isEmpty { Text("No widget windows").foregroundStyle(.secondary) }
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    Text("\(model.widgets.first { $0.id == window["widget"] }?.name ?? "?") · level \(window["level"] ?? "") · \(window["screen"] ?? "") · visible \(window["visible"] ?? "") · click-through \(window["ignoresMouse"] ?? "")")
                        .font(.caption.monospaced())
                }
            }
            Card(title: "Log") {
                HStack {
                    Picker("Level", selection: $level) { ForEach(LogEntry.Level.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.frame(width: 180)
                    Picker("Category", selection: $category) {
                        Text("All").tag(LogEntry.Category?.none)
                        ForEach(LogEntry.Category.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(LogEntry.Category?.some($0)) }
                    }
                    .frame(width: 220)
                }
                let entries = model.diagnostics.snapshot(minimumLevel: level, category: category).suffix(150).reversed()
                if entries.isEmpty { Text("No entries").foregroundStyle(.secondary) }
                ForEach(Array(entries)) { LogRow(entry: $0) }
            }
        }
        .onAppear { refresh() }
        .onReceive(ticker) { _ in refresh() }
    }

    private func timingRow(_ title: String, _ timing: TimingStats?) -> some View {
        LabeledContent(title, value: timing.map { $0.count == 0 ? "no samples" : String(format: "avg %.2f ms · p95 %.2f ms · max %.2f ms (n=%d)", $0.average * 1000, $0.p95 * 1000, $0.max * 1000, $0.count) } ?? "no samples")
    }

    private func refresh() {
        usage = model.resourceUsage()
        timings = model.diagnostics.allTimings()
        windows = model.overlay?.report() ?? []
        Task { stats = await model.dataEngine.stats }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = SystemActions.launchAtLoginEnabled
    @State private var aiKey = ""

    var body: some View {
        Page(title: "Settings") { EmptyView() } content: {
            Card(title: "General") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { on in
                    do { try SystemActions.setLaunchAtLogin(on); launchAtLogin = SystemActions.launchAtLoginEnabled }
                    catch { model.alertMessage = "Could not change the login item: \(error.localizedDescription)" }
                }))
                Toggle("Show widgets when WidgetForge starts", isOn: $model.settings.showWidgetsOnLaunch)
                Toggle("Command Center shortcut (⌃⌥Space)", isOn: $model.settings.hotKeyEnabled)
            }
            Card(title: "Layout") {
                Toggle("Snap to grid", isOn: $model.settings.snapToGrid)
                HStack {
                    Text("Grid size")
                    Slider(value: $model.settings.gridSize, in: 4...40, step: 4).frame(width: 200)
                    Text("\(Int(model.settings.gridSize)) pt").monospacedDigit()
                }
                Toggle("Show alignment guides while dragging (hold ⌘ to bypass)", isOn: $model.settings.showAlignmentGuides)
            }
            Card(title: "Performance") {
                HStack {
                    Text("Sample system metrics every")
                    Slider(value: $model.settings.metricsInterval, in: 1...10, step: 1).frame(width: 200)
                    Text("\(Int(model.settings.metricsInterval)) s").monospacedDigit()
                }
                Text("Metrics are sampled only while a widget or the dashboard is showing them, and never while the Mac or its display sleeps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "AI Builder (optional)") {
                Toggle("Enable AI-assisted widget creation", isOn: $model.settings.ai.enabled)
                Text("Off by default. When on, your prompt is sent to the endpoint below and nowhere else. Generated widgets are declarative only, validated, previewed and approved by you before they are saved.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("OpenAI-compatible endpoint", text: $model.settings.ai.endpoint).textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.settings.ai.model).textFieldStyle(.roundedBorder)
                HStack {
                    SecureField(model.secretNames.contains(model.settings.ai.secretName) ? "API key saved in Keychain. Type to replace." : "API key", text: $aiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Key") {
                        let host = URL(string: model.settings.ai.endpoint)?.host ?? ""
                        model.saveSecret(name: model.settings.ai.secretName, value: aiKey, hosts: [host])
                        aiKey = ""
                    }
                    .disabled(aiKey.isEmpty || URL(string: model.settings.ai.endpoint)?.host == nil)
                }
            }
            Card(title: "About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Data location", value: (model.db as? SQLiteDocumentStore)?.url.path ?? "In memory")
                LabeledContent("WidgetKit shared container", value: SharedContainer.directory()?.path ?? "Unavailable")
            }
        }
    }
}

// MARK: AI Builder

struct AIBuilderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var working = false
    @State private var error: String?
    @State private var result: GeneratedWidget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Widget Builder").font(.title2.weight(.semibold))
            if !model.settings.ai.enabled {
                Label("The AI builder is off. Turn it on and add an endpoint in Settings. Everything else in WidgetForge works without it.", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
                Button("Open Settings") { dismiss(); model.section = .settings }
            } else {
                Text("Describe the widget you want. The request goes to \(URL(string: model.settings.ai.endpoint)?.host ?? "your endpoint") using model \(model.settings.ai.model).")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $prompt).font(.body).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                HStack {
                    Menu("Examples") {
                        ForEach(AIWidgetGenerator.promptTemplates, id: \.title) { template in
                            Button(template.title) { prompt = template.prompt }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button("Generate") { generate() }.disabled(working || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                if let result {
                    Divider()
                    HStack(alignment: .top, spacing: 14) {
                        WidgetThumbnail(definition: result.definition, maxWidth: 240, maxHeight: 170)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.definition.name).font(.headline)
                            Text("Passed schema validation. Preview uses no live data.").font(.caption).foregroundStyle(.secondary)
                            PermissionList(manifest: result.requestedPermissions)
                            ForEach(result.report.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if let result {
                    Button("Review & Add…") { dismiss(); model.addWidget(result.definition, origin: .ai) }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func generate() {
        working = true
        error = nil
        result = nil
        let generator = AIWidgetGenerator(configuration: model.settings.ai, transport: URLSessionTransport())
        let secrets = model.secrets
        let text = prompt
        Task {
            do { result = try await generator.generate(prompt: text, secrets: secrets) }
            catch let failure { error = failure.localizedDescription }
            working = false
        }
    }
}
