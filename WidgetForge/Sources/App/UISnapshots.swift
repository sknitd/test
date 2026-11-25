import SwiftUI
import AppKit

/// `WidgetForge --ui-snapshots` renders the real UI to PNG files and exercises Edit-mode dragging with
/// synthesized mouse events, then exits. It lets an automated build produce pictures of every template,
/// every main-window section, the builder and the Command Center for a person (or a reviewer) to inspect.
/// Nothing here is used in normal operation.
@MainActor
enum UISnapshots {
    static func run(model: AppModel) {
        Task { @MainActor in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetForgeSnapshots", isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var report: [String: JSONValue] = [:]

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            report["drag"] = await dragCheck(model: model)

            // One live instance of every template. Calendar access is withheld so no system prompt appears.
            var created: [(name: String, id: String)] = []
            for (index, template) in TemplateLibrary.all.enumerated() {
                var granted = template.permissions
                granted.calendar = false
                let placement = Placement(x: 20 + Double(index % 3) * 330, y: 20 + Double(index % 2) * 60,
                                          width: template.size.width, height: template.size.height, displayID: nil)
                let widget = model.store.create(from: template, placement: placement, granted: granted, origin: .template, scriptTrusted: true)
                created.append((template.name, widget.id))
            }
            // Give the stateful templates something to show, through the same state path the UI uses.
            func set(_ name: String, _ key: String, _ value: JSONValue) {
                if let id = created.first(where: { $0.name == name })?.id { model.runtime(for: id)?.setState(key, value) }
            }
            set("Notes", "text", "Ship WidgetForge\nCall the dentist")
            set("To-do List", "items", [["title": "Write tests", "done": true], ["title": "Review build", "done": false]])
            set("Habit Tracker", "habits", ["Read": [.string(HabitsNode.dayKey(Date()))]])
            set("Clipboard Utility", "clips", ["https://example.com", "A saved snippet"])
            try? await Task.sleep(nanoseconds: 9_000_000_000)        // several metric samples, script runs, requests

            var statuses: [String: JSONValue] = [:]
            for item in created {
                guard let panel = model.overlay.panels[item.id], let view = panel.contentView else { continue }
                capture(view, to: directory.appendingPathComponent("widget-\(slug(item.name)).png"))
                if let runtime = model.runtime(for: item.id) {
                    var entry: [String: JSONValue] = [:]
                    for (source, status) in runtime.sourceStatuses { entry[source] = .string(status.label + (status.detail.map { ": \($0)" } ?? "")) }
                    if let message = runtime.scriptMessage { entry["script"] = .string(message) }
                    if !entry.isEmpty { statuses[item.name] = .object(entry) }
                }
            }
            report["sources"] = .object(statuses)
            let scriptTiming = model.diagnostics.timing("script.run")
            report["scriptRun"] = ["count": .number(Double(scriptTiming.count)), "averageMs": .number(scriptTiming.average * 1000), "maxMs": .number(scriptTiming.max * 1000)]
            let stats = await model.dataEngine.stats
            report["network"] = ["requests": .number(Double(stats.requests)), "failures": .number(Double(stats.failures))]

            // Main window: every section, then the builder with a real document and a selected component.
            AppDelegate.showMainWindow()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            report["mainWindowFound"] = .bool(window != nil)
            window?.setFrame(NSRect(x: 0, y: 0, width: 1024, height: 660), display: true)
            for section in AppSection.allCases where section != .builder {
                model.section = section
                try? await Task.sleep(nanoseconds: 900_000_000)
                if let view = window?.contentView { capture(view, to: directory.appendingPathComponent("section-\(section.rawValue).png")) }
            }
            model.section = .builder
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let view = window?.contentView { capture(view, to: directory.appendingPathComponent("builder-empty.png")) }
            var document = WidgetDefinition(name: "Snapshot Widget", size: WidgetSize(320, 200), root: WidgetNode(.canvas),
                                            dataSources: [.metric("cpu")], permissions: PermissionManifest(systemMetrics: true))
            var title = WidgetNode.paletteDefault(.text)
            title.props["value"] = "CPU {{cpu.usage | percent}}"
            title.frame = NodeFrame(x: 12, y: 8, width: 180, height: 26)
            var gauge = WidgetNode.paletteDefault(.gauge)
            gauge.props["value"] = "{{cpu.usage}}"
            gauge.frame = NodeFrame(x: 12, y: 44, width: 96, height: 96)
            var chart = WidgetNode.paletteDefault(.chart)
            chart.props["values"] = "{{cpu.history}}"
            chart.props["chartKind"] = "area"
            chart.frame = NodeFrame(x: 120, y: 44, width: 160, height: 96)
            document.root.children = [title, gauge, chart]
            model.newBuilderDocument(from: document)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let view = window?.contentView { capture(view, to: directory.appendingPathComponent("builder-document.png")) }
            model.newBuilderDocument(from: TemplateLibrary.multiMetric)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let view = window?.contentView { capture(view, to: directory.appendingPathComponent("builder-template.png")) }

            CommandCenterController.shared.show()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let view = CommandCenterController.shared.panelContentView { capture(view, to: directory.appendingPathComponent("command-center.png")) }
            CommandCenterController.shared.close()

            report["errors"] = .array(model.diagnostics.snapshot(minimumLevel: .error).map { .string($0.message) })
            report["warnings"] = .array(model.diagnostics.snapshot(minimumLevel: .warning).filter { $0.level == .warning }.suffix(30).map { .string("[\($0.category.rawValue)] \($0.message)") })
            report["files"] = .number(Double((try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0))
            // Leave the user's desktop as it was found: the template instances exist only for the pictures.
            for item in created { model.store.delete(item.id) }
            model.emptyTrash()
            print("WIDGETFORGE_SNAPSHOTS_DIR=\(directory.path)")
            print("WIDGETFORGE_SNAPSHOTS_BEGIN")
            print(JSONValue.object(report).prettyJSONString)
            print("WIDGETFORGE_SNAPSHOTS_END")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// Drive the edit overlay exactly as the mouse would: press in the middle, drag, release; then press on
    /// the bottom-right handle and drag to resize. Returns what happened to the stored placement.
    private static func dragCheck(model: AppModel) async -> JSONValue {
        guard let widget = model.widgets.first(where: { !$0.hidden }) else { return ["skipped": "no visible widget"] }
        model.setEditMode(true)
        try? await Task.sleep(nanoseconds: 400_000_000)
        defer { model.setEditMode(false) }
        guard let panel = model.overlay.panels[widget.id], let container = panel.contentView as? WidgetContainerView else { return ["skipped": "no panel"] }
        let overlay = container.editOverlay
        let before = widget.placement

        func event(_ type: NSEvent.EventType, _ screen: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: screen), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        func gesture(from start: NSPoint, by delta: NSPoint) {
            guard let down = event(.leftMouseDown, start) else { return }
            overlay.mouseDown(with: down)
            for step in 1...8 {
                let point = NSPoint(x: start.x + delta.x * CGFloat(step) / 8, y: start.y + delta.y * CGFloat(step) / 8)
                if let drag = event(.leftMouseDragged, point) { overlay.mouseDragged(with: drag) }
            }
            if let up = event(.leftMouseUp, NSPoint(x: start.x + delta.x, y: start.y + delta.y)) { overlay.mouseUp(with: up) }
        }

        // Move: 160 pt right, 96 pt down (screen y decreases downward).
        gesture(from: NSPoint(x: panel.frame.midX, y: panel.frame.midY), by: NSPoint(x: 160, y: -96))
        let moved = model.store.widget(widget.id)?.placement ?? before
        // Resize from the bottom-right handle: 48 pt wider, 32 pt taller.
        gesture(from: NSPoint(x: panel.frame.maxX - 4, y: panel.frame.minY + 4), by: NSPoint(x: 48, y: -32))
        let resized = model.store.widget(widget.id)?.placement ?? moved
        try? await Task.sleep(nanoseconds: 200_000_000)
        let windowMatches = abs(panel.frame.width - CGFloat(resized.width)) < 1 && abs(panel.frame.height - CGFloat(resized.height)) < 1
        return [
            "widget": .string(widget.name),
            "movedBy": ["dx": .number(moved.x - before.x), "dy": .number(moved.y - before.y)],
            "resizedBy": ["dw": .number(resized.width - moved.width), "dh": .number(resized.height - moved.height)],
            "originKeptDuringResize": .bool(resized.x == moved.x && resized.y == moved.y),
            "windowMatchesStore": .bool(windowMatches),
        ]
    }

    private static func capture(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func slug(_ name: String) -> String {
        name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }
}
