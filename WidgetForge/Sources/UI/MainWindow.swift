import SwiftUI
import AppKit

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding(get: { Optional(model.section) }, set: { if let s = $0 { model.section = s } })) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(10) }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(item: $model.pendingApproval) { approval in ApprovalSheet(approval: approval).environmentObject(model) }
        .alert("WidgetForge", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .dashboard: DashboardView()
        case .widgets: MyWidgetsView()
        case .builder: BuilderHost()
        case .templates: TemplatesView()
        case .dataSources: DataSourcesView()
        case .automations: AutomationsView()
        case .profiles: ProfilesView()
        case .marketplace: MarketplaceView()
        case .diagnostics: DiagnosticsView()
        case .settings: SettingsView()
        }
    }
}

struct SidebarStatus: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.profiles.first { $0.id == model.activeProfileID }?.name ?? "All Widgets", systemImage: "person.crop.rectangle.stack")
            Label(model.updatesPaused ? "Updates paused" : (model.widgetsVisible ? "\(model.widgets.filter { !$0.hidden }.count) widgets live" : "Widgets hidden"),
                  systemImage: model.updatesPaused ? "pause.circle" : "dot.radiowaves.left.and.right")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Shared pieces

/// Section scaffold: large title, optional toolbar content, scrolling body.
struct Page<Actions: View, Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.largeTitle.weight(.semibold))
                    if !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                actions()
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// A scaled, non-interactive rendering of a definition for galleries and lists. Uses no live data.
struct WidgetThumbnail: View {
    let definition: WidgetDefinition
    var maxWidth: CGFloat = 220
    var maxHeight: CGFloat = 140

    var body: some View {
        let scale = min(maxWidth / CGFloat(definition.size.width), maxHeight / CGFloat(definition.size.height), 1)
        var env = RenderEnvironment()
        env.isInteractive = false
        env.context = WidgetContextBuilder.context(state: definition.initialState, settings: definition.settings, data: [:], statuses: [:])
        env.scriptMessage = "Scripted widget"
        return WidgetContentView(definition: definition, env: env)
            .frame(width: CGFloat(definition.size.width), height: CGFloat(definition.size.height))
            .scaleEffect(scale)
            .frame(width: CGFloat(definition.size.width) * scale, height: CGFloat(definition.size.height) * scale)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct PermissionList: View {
    let manifest: PermissionManifest
    var body: some View {
        if manifest.isEmpty {
            Label("Needs no special permissions", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(manifest.descriptions, id: \.self) { line in
                    Label(line, systemImage: "shield.lefthalf.filled").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Dashboard

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var hub = AppModel.shared.metricsHub
    @State private var usage: (memoryBytes: Double?, cpuSeconds: Double?, uptime: Double) = (nil, nil, 0)
    @State private var cpuPercent: Double?
    @State private var lastCPU: (seconds: Double, at: Date)?
    private let ticker = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Page(title: "Dashboard", subtitle: "The programmable desktop") {
            HStack {
                Button { model.setEditMode(!model.isEditMode) } label: { Label(model.isEditMode ? "Done Arranging" : "Arrange", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                Button { model.newBuilderDocument() } label: { Label("New Widget", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
        } content: {
            if let note = model.storageNote {
                Label(note, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Current Profile") {
                    Picker("Profile", selection: Binding(get: { model.activeProfileID ?? "" }, set: { model.activateProfile($0.isEmpty ? nil : $0) })) {
                        Text("All Widgets").tag("")
                        ForEach(model.profiles) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    Toggle("Switch automatically", isOn: Binding(get: { model.automaticProfiles }, set: { model.setAutomaticProfiles($0) }))
                        .font(.callout)
                }
                Card(title: "WidgetForge Resource Usage") {
                    LabeledContent("CPU (last 3 s)", value: cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Measuring…")
                    LabeledContent("Memory", value: usage.memoryBytes.map { Formatters.bytes($0) } ?? "–")
                    LabeledContent("Running for", value: Formatters.duration(usage.uptime))
                    LabeledContent("Live widgets", value: "\(model.runningRuntimeCount)")
                }
                Card(title: "This Mac") {
                    LabeledContent("CPU", value: percent(hub.latest["cpu"]?["usage"]))
                    LabeledContent("Memory", value: percent(hub.latest["memory"]?["usage"]))
                    LabeledContent("Disk", value: percent(hub.latest["storage"]?["usage"]))
                    LabeledContent("Battery", value: hub.latest["battery"]?["present"]?.boolValue == true ? percent(hub.latest["battery"]?["level"]) : "No battery")
                }
            }
            Card(title: "Quick Actions") {
                HStack {
                    Button(model.widgetsVisible ? "Hide Widgets" : "Show Widgets") { model.setWidgetsVisible(!model.widgetsVisible) }
                    Button(model.updatesPaused ? "Resume Updates" : "Pause Updates") { model.setUpdatesPaused(!model.updatesPaused) }
                    Button(model.isClickThroughEnabled ? "Disable Click-Through" : "Enable Click-Through") { model.setClickThrough(!model.isClickThroughEnabled) }
                    Button("Browse Templates") { model.section = .templates }
                    Button("Command Center  ⌃⌥Space") { CommandCenterController.shared.toggle() }
                }
            }
            Card(title: "Active Widgets") {
                if model.widgets.isEmpty { Text("No widgets yet. Add one from Templates.").foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(model.widgets.filter { !$0.hidden }) { widget in
                            VStack(spacing: 6) {
                                WidgetThumbnail(definition: widget.definition, maxWidth: 170, maxHeight: 110)
                                Text(widget.name).font(.caption)
                            }
                            .onTapGesture(count: 2) { model.openInBuilder(widget.id) }
                            .help("Double-click to edit")
                        }
                    }
                }
            }
            Card(title: "Recent Events") {
                if model.recentEvents.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(model.recentEvents.suffix(8).reversed()) { entry in LogRow(entry: entry) }
            }
        }
        .onAppear { model.metricsHub.retain("dashboard"); refresh() }
        .onDisappear { model.metricsHub.release("dashboard") }
        .onReceive(ticker) { _ in refresh() }
    }

    private func percent(_ value: JSONValue?) -> String {
        guard let value, case .number(let d) = value else { return "–" }
        return "\(Int((d * 100).rounded()))%"
    }

    private func refresh() {
        usage = model.resourceUsage()
        if let seconds = usage.cpuSeconds {
            if let last = lastCPU {
                let dt = Date().timeIntervalSince(last.at)
                if dt > 0.5 { cpuPercent = (seconds - last.seconds) / dt * 100 }
            }
            lastCPU = (seconds, Date())
        }
    }
}

struct LogRow: View {
    let entry: LogEntry
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 14)
            Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(entry.category.rawValue).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Text(entry.message).font(.callout).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        switch entry.level {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        default: return "info.circle"
        }
    }

    private var color: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        default: return .secondary
        }
    }
}

// MARK: My Widgets

struct MyWidgetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<String>()
    @State private var layoutName = ""
    @State private var settingsTarget: WidgetInstance?

    var body: some View {
        Page(title: "My Widgets", subtitle: "\(model.widgets.count) on your desktop") {
            HStack {
                Menu {
                    ForEach(AlignMode.allCases, id: \.self) { mode in
                        Button { model.alignWidgets(Array(selection), mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                    }
                    Divider()
                    Button("Group Selection") { model.groupWidgets(Array(selection)) }
                    Button("Ungroup") { selectedWidgets.compactMap(\.groupID).forEach { model.ungroupWidgets($0) } }
                    Button("Snap All to Grid") { model.snapAllToGrid() }
                } label: { Label("Arrange", systemImage: "align.horizontal.left") }
                .disabled(selection.count < 2)
                .fixedSize()
                Button { model.setEditMode(!model.isEditMode) } label: { Label(model.isEditMode ? "Done" : "Edit on Desktop", systemImage: "hand.draw") }
            }
        } content: {
            if model.widgets.isEmpty {
                ContentUnavailableView("No Widgets", systemImage: "rectangle.3.group", description: Text("Add a widget from Templates or build your own."))
            }
            ForEach(model.widgets) { widget in
                row(widget)
            }
            Card(title: "Saved Layouts") {
                HStack {
                    TextField("Layout name", text: $layoutName).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    Button("Save Current Layout") {
                        model.saveLayout(named: layoutName.isEmpty ? "Layout \(model.layouts.count + 1)" : layoutName)
                        layoutName = ""
                    }
                }
                ForEach(model.layouts) { layout in
                    HStack {
                        Text(layout.name)
                        Text(layout.savedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore") { model.restoreLayout(layout.id) }
                        Button(role: .destructive) { model.deleteLayout(layout.id) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete layout \(layout.name)")
                    }
                }
            }
            if !model.trash.isEmpty {
                Card(title: "Recently Deleted") {
                    ForEach(model.trash) { widget in
                        HStack {
                            Label(widget.name, systemImage: widget.definition.symbol)
                            Spacer()
                            Button("Restore") { model.restoreWidget(widget.id) }
                        }
                    }
                    Button("Empty", role: .destructive) { model.emptyTrash() }
                }
            }
        }
        .sheet(item: $settingsTarget) { widget in WidgetSettingsSheet(widgetID: widget.id).environmentObject(model) }
    }

    private var selectedWidgets: [WidgetInstance] { model.widgets.filter { selection.contains($0.id) } }

    private func row(_ widget: WidgetInstance) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Toggle("", isOn: Binding(get: { selection.contains(widget.id) }, set: { on in
                    if on { selection.insert(widget.id) } else { selection.remove(widget.id) }
                }))
                .labelsHidden()
                .accessibilityLabel("Select \(widget.name)")
                WidgetThumbnail(definition: widget.definition, maxWidth: 150, maxHeight: 96)
                    .frame(width: 150, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(widget.name).font(.headline)
                        if widget.groupID != nil { Image(systemName: "link").help("Grouped") }
                        if widget.origin == .imported { Text("Imported").font(.caption2).padding(.horizontal, 5).background(Color.orange.opacity(0.2), in: Capsule()) }
                        if widget.definition.hasScript && !widget.scriptEnabled { Text("Script off").font(.caption2).padding(.horizontal, 5).background(Color.red.opacity(0.2), in: Capsule()) }
                    }
                    HStack(spacing: 14) {
                        Toggle("Visible", isOn: flag(widget, \.hidden, inverted: true))
                        Toggle("Locked", isOn: flag(widget, \.locked))
                        Toggle("Pinned on top", isOn: flag(widget, \.pinned))
                        Toggle("Click-through", isOn: flag(widget, \.clickThrough))
                    }
                    .toggleStyle(.checkbox)
                    HStack {
                        Text("Opacity").font(.caption)
                        Slider(value: Binding(get: { widget.opacity }, set: { value in model.updateWidget(widget.id) { $0.opacity = value } }), in: 0.2...1)
                            .frame(width: 140)
                        Picker("Appearance", selection: Binding(get: { widget.appearance }, set: { value in model.updateWidget(widget.id) { $0.appearance = value } })) {
                            ForEach(WidgetAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .frame(width: 190)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Edit…") { model.openInBuilder(widget.id) }
                    Button("Settings…") { settingsTarget = widget }
                    Menu("More") {
                        Button("Refresh Data") { model.refreshWidget(widget.id) }
                        Button("Duplicate") { model.duplicateWidget(widget.id) }
                        Button("Save to Library") { model.saveToLibrary(widget.definition) }
                        Button("Export…") { model.exportWidget(widget.definition) }
                        Divider()
                        Button("Delete", role: .destructive) { model.deleteWidget(widget.id) }
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func flag(_ widget: WidgetInstance, _ keyPath: WritableKeyPath<WidgetInstance, Bool>, inverted: Bool = false) -> Binding<Bool> {
        Binding(get: { widget[keyPath: keyPath] != inverted }, set: { value in
            model.updateWidget(widget.id) { $0[keyPath: keyPath] = value != inverted }
        })
    }
}

/// Per-widget configuration: its settings values and the permissions the user has granted (revocable here).
struct WidgetSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let widgetID: String
    @State private var values: [String: String] = [:]
    @State private var loaded = false

    var body: some View {
        let widget = model.widgets.first { $0.id == widgetID }
        VStack(alignment: .leading, spacing: 14) {
            Text("\(widget?.name ?? "Widget") Settings").font(.title2.weight(.semibold))
            if let widget {
                if let instructions = widget.definition.setupInstructions {
                    Label(instructions, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                if widget.definition.settings.isEmpty { Text("This widget has no settings.").foregroundStyle(.secondary) }
                Form {
                    ForEach(widget.definition.settings.keys.sorted(), id: \.self) { key in
                        TextField(key, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                    }
                }
                Divider()
                Text("Permissions").font(.headline)
                PermissionEditor(requested: widget.definition.permissions, granted: Binding(get: { widget.granted }, set: { granted in
                    model.updateWidget(widgetID) { $0.granted = granted }
                }))
                if widget.definition.hasScript {
                    Toggle("Trust and run this widget's script", isOn: Binding(get: { widget.scriptTrusted }, set: { value in
                        model.updateWidget(widgetID) { $0.scriptTrusted = value }
                    }))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            guard !loaded, let widget else { return }
            loaded = true
            for (key, value) in widget.definition.settings {
                values[key] = value.arrayValue.map { $0.map(\.displayString).joined(separator: ", ") } ?? value.displayString
            }
        }
    }

    private func save() {
        guard let widget = model.widgets.first(where: { $0.id == widgetID }) else { return }
        var definition = widget.definition
        for (key, text) in values {
            // Keep each setting's original JSON type.
            switch definition.settings[key] {
            case .number:
                if let number = Double(text) { definition.settings[key] = JSONValue.number(number) } else { definition.settings[key] = JSONValue.string(text) }
            case .bool: definition.settings[key] = JSONValue.bool(["true", "yes", "1"].contains(text.lowercased()))
            case .array:
                let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                definition.settings[key] = JSONValue.array(parts.map { JSONValue.string($0) })
            default: definition.settings[key] = JSONValue.string(text.trimmingCharacters(in: .whitespaces))
            }
        }
        model.updateDefinition(widgetID, definition)
    }
}

/// Switches for each requested capability. Only what the widget asked for can be granted.
struct PermissionEditor: View {
    let requested: PermissionManifest
    @Binding var granted: PermissionManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if requested.isEmpty { Text("This widget requests no permissions.").font(.callout).foregroundStyle(.secondary) }
            ForEach(requested.network, id: \.self) { host in
                Toggle("Connect to \(host)", isOn: list(\.network, host))
            }
            ForEach(requested.webContent, id: \.self) { host in
                Toggle("Show web pages from \(host)", isOn: list(\.webContent, host))
            }
            ForEach(requested.files, id: \.self) { file in
                Toggle("Read selected file (\(file))", isOn: list(\.files, file))
            }
            if requested.systemMetrics { Toggle("Read system metrics", isOn: $granted.systemMetrics) }
            if requested.clipboard { Toggle("Use the clipboard when you click its controls", isOn: $granted.clipboard) }
            if requested.calendar { Toggle("Read calendar events", isOn: $granted.calendar) }
            if requested.notifications { Toggle("Show notifications", isOn: $granted.notifications) }
            if requested.openURLs { Toggle("Open links", isOn: $granted.openURLs) }
            if requested.shortcuts { Toggle("Run Shortcuts", isOn: $granted.shortcuts) }
            if requested.launchApps { Toggle("Launch applications", isOn: $granted.launchApps) }
            if requested.mediaControl { Toggle("Control Music playback", isOn: $granted.mediaControl) }
            if requested.scripting { Toggle("Run JavaScript in the restricted runtime", isOn: $granted.scripting) }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func list(_ keyPath: WritableKeyPath<PermissionManifest, [String]>, _ item: String) -> Binding<Bool> {
        Binding(get: { granted[keyPath: keyPath].contains(item) }, set: { on in
            var items = granted[keyPath: keyPath].filter { $0 != item }
            if on { items.append(item) }
            granted[keyPath: keyPath] = items.sorted()
        })
    }
}

/// Shown before any imported or AI-generated widget is installed.
struct ApprovalSheet: View {
    @EnvironmentObject private var model: AppModel
    let approval: AppModel.PendingApproval
    @State private var granted = PermissionManifest.none
    @State private var trustScript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(approval.origin == .ai ? "Review Generated Widget" : "Review Imported Widget").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 16) {
                WidgetThumbnail(definition: approval.definition, maxWidth: 220, maxHeight: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text(approval.definition.name).font(.headline)
                    Text(approval.definition.summary).font(.callout).foregroundStyle(.secondary)
                    ForEach(approval.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Divider()
            Text("This widget asks for:").font(.headline)
            PermissionEditor(requested: approval.definition.permissions, granted: $granted)
            if approval.definition.hasScript {
                Toggle("Trust and run its JavaScript", isOn: $trustScript)
                Text("Scripts run inside WidgetForge's restricted runtime, not an OS sandbox. Only trust scripts you have read or whose author you trust. Left off, the widget is installed with its script disabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.pendingApproval = nil }.keyboardShortcut(.cancelAction)
                Button("Add Widget") { model.approve(approval, granted: granted, trustScript: trustScript && granted.scripting) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            // Pre-select everything except script execution, which is always an explicit choice.
            granted = approval.definition.permissions
            granted.scripting = false
        }
        .onChange(of: trustScript) { _, on in granted.scripting = on }
    }
}

// MARK: Templates

struct TemplatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var showAI = false

    var body: some View {
        let templates = FuzzyMatcher.filter(TemplateLibrary.all, query: query) { "\($0.name) \($0.category) \($0.summary)" }
        Page(title: "Templates", subtitle: "\(TemplateLibrary.all.count) ready-made widgets") {
            HStack {
                TextField("Search templates", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
                Button { showAI = true } label: { Label("AI Builder", systemImage: "sparkles") }
            }
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(templates) { template in
                    TemplateCard(definition: template) {
                        Button("Add") { model.addWidget(template) }.buttonStyle(.borderedProminent)
                        Button("Customize") { model.newBuilderDocument(from: template) }
                    }
                }
            }
            if templates.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .sheet(isPresented: $showAI) { AIBuilderSheet().environmentObject(model) }
    }
}

struct TemplateCard<Actions: View>: View {
    let definition: WidgetDefinition
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetThumbnail(definition: definition, maxWidth: 218, maxHeight: 130)
                .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
            HStack {
                Label(definition.name, systemImage: definition.symbol).font(.headline).lineLimit(1)
                Spacer()
                Text(definition.category).font(.caption2).foregroundStyle(.secondary)
            }
            Text(definition.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            if let setup = definition.setupInstructions {
                Label("Setup required", systemImage: "wrench.and.screwdriver").font(.caption2).foregroundStyle(.orange).help(setup)
            }
            PermissionList(manifest: definition.permissions)
            HStack { actions() }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: Profiles

struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newName = ""

    var body: some View {
        Page(title: "Profiles", subtitle: "Contextual desktops for work, development, personal time and focus") {
            Toggle("Automatic switching", isOn: Binding(get: { model.automaticProfiles }, set: { model.setAutomaticProfiles($0) })).toggleStyle(.switch)
        } content: {
            Label("Profiles switch by hand, by time of day, by frontmost app or by connected display. Per-Space profiles are not offered: macOS has no public API to identify Spaces.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("New profile name", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Button("Add Profile") {
                    model.saveProfile(Profile(name: newName.isEmpty ? "Profile \(model.profiles.count + 1)" : newName))
                    newName = ""
                }
                Spacer()
                Button("Show All Widgets") { model.activateProfile(nil) }.disabled(model.activeProfileID == nil)
            }
            ForEach(model.profiles) { profile in
                ProfileEditor(profile: profile)
            }
        }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile
    @State private var appID = ""

    var body: some View {
        let isActive = model.activeProfileID == profile.id
        Card {
            HStack {
                Image(systemName: profile.symbol)
                TextField("Name", text: Binding(get: { profile.name }, set: { name in update { $0.name = name } }))
                    .textFieldStyle(.plain).font(.headline)
                if isActive { Text("Active").font(.caption).padding(.horizontal, 6).background(Color.accentColor.opacity(0.2), in: Capsule()) }
                Spacer()
                Stepper("Priority \(profile.priority)", value: Binding(get: { profile.priority }, set: { p in update { $0.priority = p } }), in: -10...10)
                Button(isActive ? "Active" : "Activate") { model.activateProfile(profile.id) }.disabled(isActive)
                Button(role: .destructive) { model.deleteProfile(profile.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete profile \(profile.name)")
            }
            Text("Widgets").font(.subheadline.weight(.medium))
            FlowToggles(items: model.widgets.map { ($0.id, $0.name) }, selected: profile.widgetIDs) { id, on in
                update { if on { $0.widgetIDs.insert(id) } else { $0.widgetIDs.remove(id); $0.placements[id] = nil } }
            }
            Text("Activate automatically").font(.subheadline.weight(.medium))
            ForEach(profile.rules) { rule in
                HStack {
                    Image(systemName: "clock.arrow.2.circlepath")
                    Text(rule.summary).font(.callout)
                    Spacer()
                    Button { update { $0.rules.removeAll { $0.id == rule.id } } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).accessibilityLabel("Remove rule")
                }
            }
            HStack {
                Menu("Add Rule") {
                    Button("Weekdays 9:00–17:00") { addRule(.time(startMinute: 540, endMinute: 1020, weekdays: [2, 3, 4, 5, 6])) }
                    Button("Evenings 18:00–23:00") { addRule(.time(startMinute: 1080, endMinute: 1380, weekdays: [])) }
                    Button("Overnight 22:00–06:00") { addRule(.time(startMinute: 1320, endMinute: 360, weekdays: [])) }
                    Button("When an external display is connected") { addRule(.display(id: "")) }
                    ForEach(ScreenGeometry.displays(), id: \.id) { display in
                        Button("When “\(display.name)” is connected") { addRule(.display(id: display.id)) }
                    }
                }
                .fixedSize()
                TextField("App bundle ID, e.g. com.apple.dt.Xcode", text: $appID).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Button("Add App Rule") {
                    addRule(.activeApp(bundleIDs: [appID.trimmingCharacters(in: .whitespaces)]))
                    appID = ""
                }
                .disabled(appID.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Use Frontmost…") { appID = NSWorkspace.shared.runningApplications.first { $0.isActive == false && $0.activationPolicy == .regular }?.bundleIdentifier ?? "" }
                    .help("Fills in the bundle ID of a running app")
            }
        }
    }

    private func update(_ body: (inout Profile) -> Void) {
        var copy = profile
        body(&copy)
        model.saveProfile(copy)
    }

    private func addRule(_ kind: ProfileRule.Kind) { update { $0.rules.append(ProfileRule(kind: kind)) } }
}

/// A wrapping row of toggle chips.
struct FlowToggles: View {
    let items: [(id: String, title: String)]
    let selected: Set<String>
    let onToggle: (String, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.id) { item in
                Toggle(item.title, isOn: Binding(get: { selected.contains(item.id) }, set: { onToggle(item.id, $0) }))
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
            }
        }
    }
}
