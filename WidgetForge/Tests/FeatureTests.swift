import XCTest
@testable import WidgetForgeKit

final class ThemeAndTidyTests: XCTestCase {
    func testThemesAreDistinctAndKeepWidgetsValid() throws {
        XCTAssertEqual(Set(WidgetTheme.all.map(\.id)).count, WidgetTheme.all.count)
        XCTAssertGreaterThanOrEqual(WidgetTheme.all.count, 5)
        let store = WidgetStore(db: InMemoryDocumentStore())
        let widget = store.create(from: TemplateLibrary.cpuMonitor)
        let before = store.widget(widget.id)!
        for theme in WidgetTheme.all {
            store.applyTheme(theme, to: [widget.id])
            let themed = store.widget(widget.id)!
            XCTAssertEqual(themed.definition.style, theme.style)
            XCTAssertEqual(themed.appearance, theme.appearance)
            XCTAssertEqual(WidgetTheme.matching(themed)?.id, theme.id)
            // A theme changes looks only.
            XCTAssertEqual(themed.definition.root, before.definition.root)
            XCTAssertEqual(themed.definition.dataSources, before.definition.dataSources)
            XCTAssertEqual(themed.granted, before.granted)
            XCTAssertEqual(themed.placement, before.placement)
            XCTAssertTrue(SchemaValidator.validate(definition: try JSONValue.encode(themed.definition)).isValid, theme.name)
        }
        XCTAssertEqual(WidgetTheme.named("midnight")?.name, "Midnight")
        XCTAssertEqual(WidgetTheme.named("PAPER")?.id, "paper")
        XCTAssertNil(WidgetTheme.named("nope"))
    }

    func testTilingNeverOverlapsAndStaysOnScreen() {
        let bounds = Rect(x: 100, y: 50, width: 1200, height: 700)
        let sizes = [WidgetSize(220, 110), WidgetSize(280, 210), WidgetSize(260, 200), WidgetSize(360, 250), WidgetSize(240, 150), WidgetSize(300, 220), WidgetSize(220, 90)]
        for mode in TileMode.allCases {
            let rects = LayoutEngine.tile(sizes, in: bounds, mode: mode)
            XCTAssertEqual(rects.count, sizes.count)
            for (i, a) in rects.enumerated() {
                XCTAssertEqual(a.width, sizes[i].width); XCTAssertEqual(a.height, sizes[i].height)
                XCTAssertTrue(a.minX >= bounds.minX && a.maxX <= bounds.maxX && a.minY >= bounds.minY && a.maxY <= bounds.maxY, "\(mode) item \(i) off screen")
                for b in rects[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(mode): \(a) overlaps \(b)") }
            }
        }
        let left = LayoutEngine.tile(sizes, in: bounds, mode: .left)
        XCTAssertEqual(left[0].x, 124); XCTAssertEqual(left[0].y, 74)
        XCTAssertEqual(left[1].y, 74 + 110 + 16, "second item stacks below the first")
        XCTAssertGreaterThan(left[3].x, left[0].x, "a full column wraps to the next one")
        let right = LayoutEngine.tile(sizes, in: bounds, mode: .right)
        XCTAssertEqual(right[0].maxX, bounds.maxX - 24)
        let bottom = LayoutEngine.tile(sizes, in: bounds, mode: .bottom)
        XCTAssertEqual(bottom[0].maxY, bounds.maxY - 24)
        XCTAssertTrue(LayoutEngine.tile([], in: bounds, mode: .top).isEmpty)
    }

    func testStoreTidyRespectsLocksHiddenAndDisplays() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        store.snapToGrid = false
        let main = display("main", main: true), external = display("ext", x: 1440, width: 1920, height: 1080)
        let a = store.create(from: simpleDefinition("A"), placement: Placement(x: 600, y: 600, width: 200, height: 100, displayID: "main"))
        let b = store.create(from: simpleDefinition("B"), placement: Placement(x: 610, y: 610, width: 200, height: 100, displayID: "main"))
        let locked = store.create(from: simpleDefinition("Locked"), placement: Placement(x: 900, y: 500, width: 200, height: 100, displayID: "main"))
        let onExternal = store.create(from: simpleDefinition("Ext"), placement: Placement(x: 800, y: 800, width: 200, height: 100, displayID: "ext"))
        store.update(locked.id) { $0.locked = true }
        store.tidy(.left, displays: [main, external])
        XCTAssertEqual(store.widget(a.id)?.placement, Placement(x: 24, y: 24, width: 200, height: 100, displayID: "main"))
        XCTAssertEqual(store.widget(b.id)?.placement.y, 24 + 100 + 16)
        XCTAssertEqual(store.widget(locked.id)?.placement.x, 900, "locked widgets stay put")
        XCTAssertEqual(store.widget(onExternal.id)?.placement, Placement(x: 24, y: 24, width: 200, height: 100, displayID: "ext"), "each display is tidied separately")
    }
}

final class BackupTests: XCTestCase {
    func makeArchive() -> BackupArchive {
        let store = WidgetStore(db: InMemoryDocumentStore())
        let notes = store.create(from: TemplateLibrary.notes)
        store.setState(notes.id, key: "text", value: "remember the milk")
        let script = store.create(from: TemplateLibrary.customScript, scriptTrusted: true)
        var stocks = TemplateLibrary.stocks
        stocks.dataSources[0].headers["Authorization"] = "Bearer LIVE-TOKEN"
        let online = store.create(from: stocks)
        let layout = store.saveLayout(named: "Desk")
        let profile = Profile(name: "Work", widgetIDs: [notes.id, "ghost"], placements: ["ghost": notes.placement])
        let rule = AutomationRule(name: "High CPU", trigger: .metricSustained(condition: Condition("cpu.usage", .greaterThan, 0.9), seconds: 30), actions: [.notify(title: "Hot", body: "")])
        _ = (script, online)
        return BackupArchive(widgets: store.widgets, layouts: [layout], profiles: [profile], activeProfileID: profile.id, rules: [rule],
                             library: [TemplateLibrary.weather], settings: ["gridSize": 16])
    }

    func testRoundTripKeepsContentAndDropsWhatMustNotTravel() throws {
        let archive = makeArchive()
        let data = try BackupCodec.encode(archive)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("LIVE-TOKEN"), "credentials never reach a backup file")
        XCTAssertTrue(text.contains("remember the milk"), "your own state is kept")

        let restored = try BackupCodec.decode(data)
        XCTAssertEqual(restored.widgets.map(\.name), archive.widgets.map(\.name))
        XCTAssertEqual(restored.widgets.map(\.id), archive.widgets.map(\.id))
        XCTAssertEqual(restored.widgets[0].state["text"], "remember the milk")
        XCTAssertEqual(restored.widgets[0].placement, archive.widgets[0].placement)
        XCTAssertEqual(restored.layouts.map(\.name), ["Desk"])
        XCTAssertEqual(restored.rules, archive.rules)
        XCTAssertEqual(restored.library.map(\.name), ["Weather"])
        XCTAssertEqual(restored.settings?["gridSize"], 16)
        XCTAssertEqual(restored.activeProfileID, archive.activeProfileID)
        XCTAssertEqual(restored.profiles[0].widgetIDs, [archive.widgets[0].id], "references to missing widgets are dropped")
        XCTAssertTrue(restored.profiles[0].placements.isEmpty)

        let script = restored.widgets[1]
        XCTAssertTrue(script.definition.hasScript)
        XCTAssertFalse(script.scriptTrusted, "scripts come back untrusted")
        XCTAssertFalse(script.scriptEnabled)
        XCTAssertTrue(script.granted.systemMetrics, "other grants survive")
    }

    func testRestoreCannotGrantMoreThanTheManifestAsks() throws {
        var archive = makeArchive()
        archive.widgets[0].granted = PermissionManifest(network: ["evil.example.org"], systemMetrics: true, clipboard: true, shortcuts: true)
        let restored = try BackupCodec.decode(try BackupCodec.encode(archive))
        XCTAssertTrue(restored.widgets[0].granted.isEmpty, "Notes requests nothing, so nothing can be restored for it")
    }

    func testRejectsForeignOversizedAndInvalidFiles() throws {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{}".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(try WidgetPackageCodec.export(TemplateLibrary.notes))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data(count: BackupCodec.maxBytes + 1))) { XCTAssertEqual($0 as? BackupError, .tooLarge) }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"format\":\"widgetforge.backup\",\"version\":9}".utf8))) { XCTAssertEqual($0 as? BackupError, .unsupportedVersion(9)) }
        var text = String(decoding: try BackupCodec.encode(makeArchive()), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"type\" : \"input\"", with: "\"type\" : \"shell\"")
        XCTAssertThrowsError(try BackupCodec.decode(Data(text.utf8))) {
            guard case .invalidWidget = $0 as? BackupError else { return XCTFail("expected invalidWidget, got \($0)") }
        }
    }

    func testStoreAndProfilesAreReplacedOnRestore() throws {
        let archive = try BackupCodec.decode(try BackupCodec.encode(makeArchive()))
        let db = InMemoryDocumentStore()
        let store = WidgetStore(db: db)
        let stale = store.create(from: simpleDefinition("Stale"))
        store.delete(store.create(from: simpleDefinition("Trashed")).id)
        let profiles = ProfileManager(db: db, store: store)
        profiles.upsert(Profile(name: "Old"))

        store.replaceAll(widgets: archive.widgets, layouts: archive.layouts)
        profiles.replaceAll(archive.profiles, activeID: archive.activeProfileID)
        XCTAssertNil(store.widget(stale.id))
        XCTAssertTrue(store.trash.isEmpty)
        XCTAssertEqual(store.widgets.count, 3)
        XCTAssertEqual(profiles.profiles.map(\.name), ["Work"])
        XCTAssertEqual(profiles.active?.name, "Work")
        XCTAssertEqual(store.widgets.filter { !$0.hidden }.map(\.name), ["Notes"], "the restored active profile is applied")

        // And it is really persisted: a fresh store over the same database sees the same thing.
        let reopened = WidgetStore(db: db)
        reopened.load()
        XCTAssertEqual(Set(reopened.widgets.map(\.id)), Set(archive.widgets.map(\.id)))
    }
}

final class SustainedTriggerTests: XCTestCase {
    func sample(_ cpu: Double, at seconds: Double) -> AutomationEvent {
        AutomationEvent(kind: .metricsSampled, context: ["cpu": ["usage": .number(cpu)]], date: Date(timeIntervalSince1970: 10_000 + seconds))
    }

    func testFiresOnlyAfterTheConditionHasHeldLongEnough() async {
        let rule = AutomationRule(name: "High CPU", trigger: .metricSustained(condition: Condition("cpu.usage", .greaterThan, 0.9), seconds: 30),
                                  actions: [.notify(title: "Hot", body: "")], cooldown: 0)
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer)
        func feed(_ cpu: Double, _ t: Double) async { await engine.handle(sample(cpu, at: t)); await engine.waitUntilIdle() }

        await feed(0.95, 0); await feed(0.97, 10); await feed(0.99, 20)
        XCTAssertTrue(performer.performed.isEmpty, "20 s is not long enough")
        await feed(0.5, 25)                              // a dip resets the clock
        await feed(0.95, 30); await feed(0.95, 50)
        XCTAssertTrue(performer.performed.isEmpty, "only 20 s since the dip")
        await feed(0.95, 60)
        XCTAssertEqual(performer.performed.count, 1, "held for 30 s")
        await feed(0.99, 70); await feed(0.99, 200)
        XCTAssertEqual(performer.performed.count, 1, "fires once per episode, not on every sample")
        await feed(0.2, 210)                             // recovery re-arms
        await feed(0.95, 220); await feed(0.95, 250)
        XCTAssertEqual(performer.performed.count, 2)
    }

    func testOtherEventsAndMissingMetricsDoNotTrigger() async {
        let rule = AutomationRule(name: "Low memory", trigger: .metricSustained(condition: Condition("memory.usage", .greaterThan, 0.8), seconds: 0),
                                  actions: [.notify(title: "Memory", body: "")], cooldown: 0)
        let performer = RecordingPerformer()
        let engine = AutomationEngine(rules: [rule], performer: performer)
        await engine.handle(sample(0.99, at: 0))                                   // no memory key in the sample
        await engine.handle(AutomationEvent(kind: .networkChanged))
        await engine.handle(AutomationEvent(kind: .dataUpdated(widgetID: "w"), context: ["memory": ["usage": 0.99]]))
        await engine.waitUntilIdle()
        XCTAssertTrue(performer.performed.isEmpty)
        await engine.handle(AutomationEvent(kind: .metricsSampled, context: ["memory": ["usage": 0.9]]))
        await engine.waitUntilIdle()
        XCTAssertEqual(performer.performed.count, 1, "zero seconds means as soon as it is true")
    }
}

final class DeepLinkTests: XCTestCase {
    func parse(_ text: String) -> DeepLinkCommand? { DeepLinkCommand.parse(URL(string: text)!) }

    func testCommands() {
        XCTAssertEqual(parse("widgetforge://show"), .showWidgets)
        XCTAssertEqual(parse("widgetforge://hide"), .hideWidgets)
        XCTAssertEqual(parse("WidgetForge://TOGGLE"), .toggleWidgets)
        XCTAssertEqual(parse("widgetforge:toggle"), .toggleWidgets)
        XCTAssertEqual(parse("widgetforge://edit"), .editMode(true))
        XCTAssertEqual(parse("widgetforge://edit?on=0"), .editMode(false))
        XCTAssertEqual(parse("widgetforge://pause"), .pauseUpdates(true))
        XCTAssertEqual(parse("widgetforge://resume"), .pauseUpdates(false))
        XCTAssertEqual(parse("widgetforge://profile?name=Deep%20Work"), .profile("Deep Work"))
        XCTAssertEqual(parse("widgetforge://profile"), .profile(nil))
        XCTAssertEqual(parse("widgetforge://theme?name=Midnight"), .theme("Midnight"))
        XCTAssertEqual(parse("widgetforge://tidy?edge=right"), .tidy(.right))
        XCTAssertEqual(parse("widgetforge://tidy"), .tidy(.left))
        XCTAssertEqual(parse("widgetforge://open?section=Diagnostics"), .open("diagnostics"))
        XCTAssertEqual(parse("widgetforge://command-center"), .commandCenter)
        XCTAssertEqual(parse("widgetforge://run?name=Low%20battery"), .runAutomation("Low battery"))
        XCTAssertEqual(parse("widgetforge://add?template=CPU%20Monitor"), .addTemplate("CPU Monitor"))
    }

    func testRejectsAnythingElse() {
        XCTAssertNil(parse("https://example.com/show"))
        XCTAssertNil(parse("widgetforge://delete-everything"))
        XCTAssertNil(parse("widgetforge://import?url=https://evil.example/w.wfwidget"))
        XCTAssertNil(parse("widgetforge://theme"))
        XCTAssertNil(parse("widgetforge://run"))
        XCTAssertNil(parse("widgetforge://tidy?edge=diagonal"))
        XCTAssertNil(parse("widgetforge://add?template=" + String(repeating: "a", count: 500)))
    }

    func testOnlyAddAndRunNeedConfirmation() {
        XCTAssertTrue(DeepLinkCommand.addTemplate("Notes").needsConfirmation)
        XCTAssertTrue(DeepLinkCommand.runAutomation("x").needsConfirmation)
        for harmless in [DeepLinkCommand.showWidgets, .hideWidgets, .toggleWidgets, .editMode(true), .pauseUpdates(true), .profile("Work"),
                         .theme("Neon"), .tidy(.top), .open("settings"), .commandCenter] {
            XCTAssertFalse(harmless.needsConfirmation)
        }
    }
}
