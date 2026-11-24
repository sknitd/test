import SwiftUI
import AppKit

struct CommandItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let run: () -> Void
}

/// The floating, keyboard-first command palette (⌃⌥Space, or ⌘K inside the app).
@MainActor
final class CommandCenterController {
    static let shared = CommandCenterController()
    private var panel: CommandPanel?

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let model = AppModel.shared
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: CommandCenterView(items: CommandCenterController.items(model), close: { [weak self] in self?.close() }))
        if let screen = NSScreen.main {
            let size = NSSize(width: 620, height: 420)
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12, width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> CommandPanel {
        let panel = CommandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onResignKey = { [weak self] in self?.close() }
        return panel
    }

    /// Everything the palette can do, built fresh each time it opens.
    static func items(_ model: AppModel) -> [CommandItem] {
        var items: [CommandItem] = []
        func add(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ run: @escaping () -> Void) {
            items.append(CommandItem(id: id, title: title, subtitle: subtitle, symbol: symbol, run: run))
        }
        func open(_ section: AppSection) {
            model.section = section
            AppDelegate.showMainWindow()
        }
        add("toggle.widgets", model.widgetsVisible ? "Hide All Widgets" : "Show All Widgets", "Desktop", "eye") { model.setWidgetsVisible(!model.widgetsVisible) }
        add("toggle.edit", model.isEditMode ? "Finish Arranging Widgets" : "Arrange Widgets (Edit Mode)", "Desktop", "hand.draw") { model.setEditMode(!model.isEditMode) }
        add("toggle.click", model.isClickThroughEnabled ? "Disable Click-Through" : "Enable Click-Through", "Desktop", "cursorarrow.rays") { model.setClickThrough(!model.isClickThroughEnabled) }
        add("toggle.pause", model.updatesPaused ? "Resume Updates" : "Pause Updates", "Performance", "pause.circle") { model.setUpdatesPaused(!model.updatesPaused) }
        add("new.widget", "Create Widget in Builder", "Builder", "plus.square") { model.newBuilderDocument(); AppDelegate.showMainWindow() }
        for widget in model.widgets {
            add("widget.toggle.\(widget.id)", "\(widget.hidden ? "Show" : "Hide") \(widget.name)", "Widget", widget.definition.symbol) {
                model.updateWidget(widget.id) { $0.hidden.toggle() }
            }
            add("widget.edit.\(widget.id)", "Edit \(widget.name)", "Open in Builder", "hammer") { model.openInBuilder(widget.id) }
        }
        add("profile.none", "Switch to All Widgets", "Profile", "person.crop.rectangle.stack") { model.activateProfile(nil) }
        for profile in model.profiles {
            add("profile.\(profile.id)", "Switch to \(profile.name)", "Profile", profile.symbol) { model.activateProfile(profile.id) }
        }
        for rule in model.rules {
            add("rule.\(rule.id)", "Run “\(rule.name)”", "Automation", "bolt") { model.runRule(rule.id) }
        }
        for template in TemplateLibrary.all {
            add("template.\(template.name)", "Add \(template.name)", "Template · \(template.category)", template.symbol) { model.addWidget(template) }
        }
        for section in AppSection.allCases {
            add("section.\(section.rawValue)", "Open \(section.title)", section == .diagnostics ? "Logs and measurements" : "Go to", section.symbol) { open(section) }
        }
        return items
    }
}

final class CommandPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

struct CommandCenterView: View {
    let items: [CommandItem]
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var results: [CommandItem] {
        Array(FuzzyMatcher.filter(items, query: query) { "\($0.title) \($0.subtitle)" }.prefix(60))
    }

    var body: some View {
        let results = self.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Search widgets, templates, profiles and commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { run(results) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(0, results.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .accessibilityLabel("Command search")
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == highlighted)
                                .id(item.id)
                                .onTapGesture { highlighted = index; run(results) }
                        }
                        if results.isEmpty { Text("No matches").foregroundStyle(.secondary).padding(30) }
                    }
                    .padding(6)
                }
                .onChange(of: highlighted) { _, value in
                    if results.indices.contains(value) { proxy.scrollTo(results[value].id) }
                }
            }
            Divider()
            Text("↑↓ to move   ↩ to run   esc to close").font(.caption).foregroundStyle(.secondary).padding(6)
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { searchFocused = true }
        .onExitCommand(perform: close)
    }

    private func row(_ item: CommandItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).frame(width: 22).foregroundStyle(selected ? Color.white : Color.accentColor)
            Text(item.title).lineLimit(1)
            Spacer()
            Text(item.subtitle).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func run(_ results: [CommandItem]) {
        guard results.indices.contains(highlighted) else { return }
        let item = results[highlighted]
        close()
        item.run()
    }
}
