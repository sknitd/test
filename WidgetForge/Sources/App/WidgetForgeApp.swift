import SwiftUI
import AppKit

@main
struct WidgetForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("WidgetForge", id: "main") {
            MainWindow()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Widget") { model.newBuilderDocument() }.keyboardShortcut("n", modifiers: .command)
                Button("Import Widget…") { model.importWidget() }.keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Widgets") {
                Button(model.widgetsVisible ? "Hide All Widgets" : "Show All Widgets") { model.setWidgetsVisible(!model.widgetsVisible) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button(model.isEditMode ? "Finish Arranging" : "Arrange Widgets") { model.setEditMode(!model.isEditMode) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button(model.isClickThroughEnabled ? "Disable Click-Through" : "Enable Click-Through") { model.setClickThrough(!model.isClickThroughEnabled) }
                Button(model.updatesPaused ? "Resume Updates" : "Pause Updates") { model.setUpdatesPaused(!model.updatesPaused) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Snap All to Grid") { model.snapAllToGrid() }
                Button("Command Center") { CommandCenterController.shared.toggle() }.keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra("WidgetForge", systemImage: "square.grid.2x2.fill") {
            MenuBarContent().environmentObject(model)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.widgetsVisible ? "Hide Widgets" : "Show Widgets") { model.setWidgetsVisible(!model.widgetsVisible) }
        Toggle("Edit Mode", isOn: Binding(get: { model.isEditMode }, set: { model.setEditMode($0) }))
        Toggle("Click-Through", isOn: Binding(get: { model.isClickThroughEnabled }, set: { model.setClickThrough($0) }))
        Toggle("Pause Updates", isOn: Binding(get: { model.updatesPaused }, set: { model.setUpdatesPaused($0) }))
        Divider()
        Menu("Profile") {
            Button { model.activateProfile(nil) } label: { Label("All Widgets", systemImage: model.activeProfileID == nil ? "checkmark" : "") }
            ForEach(model.profiles) { profile in
                Button { model.activateProfile(profile.id) } label: {
                    Label(profile.name, systemImage: model.activeProfileID == profile.id ? "checkmark" : "")
                }
            }
        }
        Divider()
        Button("Open Dashboard") { show(.dashboard) }
        Button("Command Center") { CommandCenterController.shared.toggle() }
        Divider()
        Button("Quit WidgetForge") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show(_ section: AppSection) {
        model.section = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.start()
        NotificationCenter.default.addObserver(forName: .widgetForgeOpenInBuilder, object: nil, queue: .main) { note in
            guard let id = note.object as? String else { return }
            MainActor.assumeIsolated {
                AppModel.shared.setEditMode(false)
                AppModel.shared.openInBuilder(id)
            }
        }
        NotificationCenter.default.addObserver(forName: .widgetForgeShowMainWindow, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.showMainWindow() }
        }
        if CommandLine.arguments.contains("--self-test") { SelfTest.run(model: model) }
    }

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    /// Closing the main window leaves the widgets (and the menu bar item) running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.shutdown() }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension == WidgetPackage.fileExtension || url.pathExtension == "json" {
            AppModel.shared.importWidget(from: url)
        }
        AppDelegate.showMainWindow()
    }
}

/// `WidgetForge --self-test` launches the real app, lets it run briefly, prints measured facts as JSON and exits.
/// It exists so that an automated build can prove the overlay, metrics and runtimes work, with real numbers.
@MainActor
enum SelfTest {
    static func run(model: AppModel) {
        Task { @MainActor in
            let idleSeconds = 10.0
            try? await Task.sleep(nanoseconds: 4_000_000_000)                 // settle after launch
            let cpuBefore = ProcessMetrics.cpuTime() ?? 0
            let started = Date()
            try? await Task.sleep(nanoseconds: UInt64(idleSeconds * 1_000_000_000))
            let elapsed = Date().timeIntervalSince(started)
            let cpuUsed = (ProcessMetrics.cpuTime() ?? 0) - cpuBefore
            let stats = await model.dataEngine.stats

            // Exercise move/resize through the same store path the edit overlay uses.
            var moveOK = false
            if let first = model.widgets.first {
                var target = first.placement
                target.x += 64; target.y += 32; target.width += 40
                model.store.snapToGrid = false
                model.store.resize(first.id, to: target)
                model.store.snapToGrid = model.settings.snapToGrid
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let panel = model.overlay.panels[first.id], let rect = LayoutEngine.globalRect(for: target, in: ScreenGeometry.displays()) {
                    moveOK = abs(panel.frame.width - CGFloat(rect.width)) < 1 && abs(panel.frame.minX - ScreenGeometry.nsRect(from: rect).minX) < 1
                }
            }
            model.setEditMode(true)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let editLevels = model.overlay.panels.values.map { $0.level.rawValue }
            model.setEditMode(false)

            var timings: [String: JSONValue] = [:]
            for (name, timing) in model.diagnostics.allTimings() {
                timings[name] = ["count": .number(Double(timing.count)), "averageMs": .number(timing.average * 1000), "p95Ms": .number(timing.p95 * 1000), "maxMs": .number(timing.max * 1000)]
            }
            let metrics = model.metricsHub.collector.sample()
            let report: JSONValue = [
                "widgets": .array(model.widgets.map { .string($0.name) }),
                "runtimes": .number(Double(model.runningRuntimeCount)),
                "panels": .array(model.overlay.report().map { entry in .object(entry.mapValues { .string($0) }) }),
                "desktopLevel": .number(Double(OverlayLayering.desktopLevel.rawValue)),
                "editModeLevels": .array(editLevels.map { .number(Double($0)) }),
                "moveResizeApplied": .bool(moveOK),
                "displays": .array(ScreenGeometry.displays().map { .string("\($0.name) \(Int($0.frame.width))x\(Int($0.frame.height)) @\($0.scale)x") }),
                "idleWindowSeconds": .number(elapsed),
                "idleCPUPercent": .number(elapsed > 0 ? cpuUsed / elapsed * 100 : 0),
                "memoryFootprintMB": .number((ProcessMetrics.memoryFootprint() ?? 0) / 1_048_576),
                "metricsSampleCount": .number(Double(model.metricsHub.collector.sampleCount)),
                "cpuUsage": metrics["cpu"]?["usage"] ?? .null,
                "memoryUsage": metrics["memory"]?["usage"] ?? .null,
                "batteryPresent": metrics["battery"]?["present"] ?? .null,
                "network": ["requests": .number(Double(stats.requests)), "failures": .number(Double(stats.failures))],
                "timings": .object(timings),
                "scriptWatchdogAvailable": .bool(ScriptRuntime.watchdogAvailable),
                "storageNote": .string(model.storageNote ?? ""),
                "sharedContainer": .string(SharedContainer.directory()?.path ?? "unavailable"),
                "errors": .array(model.diagnostics.snapshot(minimumLevel: .error).map { .string($0.message) }),
            ]
            print("WIDGETFORGE_SELFTEST_BEGIN")
            print(report.prettyJSONString)
            print("WIDGETFORGE_SELFTEST_END")
            fflush(stdout)
            if let index = CommandLine.arguments.firstIndex(of: "--hold"), CommandLine.arguments.count > index + 1,
               let seconds = Double(CommandLine.arguments[index + 1]) {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))      // keep windows up for a screenshot
            }
            NSApp.terminate(nil)
        }
    }
}
