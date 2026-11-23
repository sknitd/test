import XCTest
@testable import WidgetForgeKit

final class WidgetLifecycleTests: XCTestCase {
    func makeStore(_ db: DocumentStore = InMemoryDocumentStore()) -> WidgetStore {
        let store = WidgetStore(db: db)
        store.load()
        return store
    }

    func testCreateUpdateDelete() {
        let store = makeStore()
        let widget = store.create(from: simpleDefinition("Clock"))
        XCTAssertEqual(store.widgets.count, 1)
        XCTAssertEqual(widget.placement.width, 200)
        XCTAssertTrue(store.update(widget.id) { $0.opacity = 0.5; $0.pinned = true })
        XCTAssertEqual(store.widget(widget.id)?.opacity, 0.5)
        XCTAssertEqual(store.widget(widget.id)?.layer, .floating)
        XCTAssertFalse(store.update("missing") { $0.opacity = 0 })
        store.delete(widget.id)
        XCTAssertTrue(store.widgets.isEmpty)
        XCTAssertEqual(store.trash.map(\.id), [widget.id])
    }

    func testRestoreFromTrash() {
        let store = makeStore()
        let widget = store.create(from: simpleDefinition())
        store.setState(widget.id, key: "text", value: "keep me")
        store.delete(widget.id)
        let restored = store.restore(widget.id)
        XCTAssertEqual(restored?.state["text"], "keep me")
        XCTAssertEqual(store.widgets.count, 1)
        XCTAssertTrue(store.trash.isEmpty)
        XCTAssertNil(store.restore("unknown"))
    }

    func testDuplicate() {
        let store = makeStore()
        let widget = store.create(from: simpleDefinition("Notes"))
        store.setState(widget.id, key: "text", value: "abc")
        store.update(widget.id) { $0.locked = true }
        let copy = store.duplicate(widget.id)!
        XCTAssertNotEqual(copy.id, widget.id)
        XCTAssertNotEqual(copy.definition.id, store.widget(widget.id)!.definition.id)
        XCTAssertEqual(copy.name, "Notes Copy")
        XCTAssertEqual(copy.state["text"], "abc")
        XCTAssertEqual(copy.placement.x, widget.placement.x + 24)
        XCTAssertFalse(copy.locked)
        XCTAssertEqual(store.widgets.count, 2)
    }

    func testPersistenceAcrossReload() {
        let db = InMemoryDocumentStore()
        let first = makeStore(db)
        let a = first.create(from: simpleDefinition("A"))
        let b = first.create(from: simpleDefinition("B"))
        first.snapToGrid = false
        first.move(a.id, to: Placement(x: 333, y: 77, width: 200, height: 100, displayID: "d1"))
        first.setState(a.id, key: "text", value: "persisted")
        first.delete(b.id)
        first.saveLayout(named: "Desk")

        let second = makeStore(db)
        XCTAssertEqual(second.widgets.count, 1)
        XCTAssertEqual(second.widget(a.id)?.placement, Placement(x: 333, y: 77, width: 200, height: 100, displayID: "d1"))
        XCTAssertEqual(second.widget(a.id)?.state["text"], "persisted")
        XCTAssertEqual(second.trash.map(\.id), [b.id])
        XCTAssertEqual(second.layouts.map(\.name), ["Desk"])
    }

    func testCorruptRecordIsSkippedNotFatal() throws {
        let db = InMemoryDocumentStore()
        let first = makeStore(db)
        first.create(from: simpleDefinition("Good"))
        try db.put(Collections.widgets, id: "broken", data: Data("{not json".utf8))
        let second = WidgetStore(db: db)
        var errors: [String] = []
        second.onError = { errors.append($0) }
        second.load()
        XCTAssertEqual(second.widgets.map(\.name), ["Good"])
        XCTAssertEqual(errors.count, 1)
    }

    #if canImport(SQLite3)
    func testSQLiteStorePersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var id = ""
        do {
            let store = makeStore(try SQLiteDocumentStore(url: url))
            let w = store.create(from: TemplateLibrary.notes)
            store.setState(w.id, key: "text", value: "saved to sqlite ✓")
            id = w.id
        }
        let db = try SQLiteDocumentStore(url: url)
        let reopened = makeStore(db)
        XCTAssertEqual(reopened.widget(id)?.state["text"], "saved to sqlite ✓")
        try db.put("c", id: "1", data: Data([1, 2, 3]))
        try db.put("c", id: "1", data: Data([9]))
        XCTAssertEqual(try db.get("c", id: "1"), Data([9]))
        XCTAssertEqual(try db.all("c").count, 1)
        try db.delete("c", id: "1")
        XCTAssertNil(try db.get("c", id: "1"))
    }
    #endif
}

final class LayoutTests: XCTestCase {
    func testSnap() {
        XCTAssertEqual(LayoutEngine.snap(13, grid: 8), 16)
        XCTAssertEqual(LayoutEngine.snap(11, grid: 8), 8)
        XCTAssertEqual(LayoutEngine.snap(11, grid: 0), 11)
        let r = LayoutEngine.snap(Rect(x: 13, y: 3, width: 101, height: 47), grid: 8, snapSize: true)
        XCTAssertEqual(r, Rect(x: 16, y: 0, width: 104, height: 48))
    }

    func testStoreMoveSnapsAndRespectsLock() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        let w = store.create(from: simpleDefinition())
        store.move(w.id, to: Placement(x: 101, y: 59, width: 200, height: 100, displayID: nil))
        XCTAssertEqual(store.widget(w.id)?.placement.x, 104)
        XCTAssertEqual(store.widget(w.id)?.placement.y, 56)
        store.update(w.id) { $0.locked = true }
        store.move(w.id, to: Placement(x: 400, y: 400, width: 200, height: 100, displayID: nil))
        XCTAssertEqual(store.widget(w.id)?.placement.x, 104)
    }

    func testResizeEnforcesMinimum() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        let w = store.create(from: simpleDefinition())
        store.resize(w.id, to: Placement(x: 0, y: 0, width: 10, height: 10, displayID: nil))
        XCTAssertEqual(store.widget(w.id)?.placement.width, 80)
        XCTAssertEqual(store.widget(w.id)?.placement.height, 48)
        XCTAssertEqual(LayoutEngine.resize(Rect(x: 10, y: 10, width: 100, height: 100), handle: .bottomRight, dx: 20, dy: -30),
                       Rect(x: 10, y: 10, width: 120, height: 70))
        XCTAssertEqual(LayoutEngine.resize(Rect(x: 10, y: 10, width: 100, height: 100), handle: .topLeft, dx: 500, dy: 500),
                       Rect(x: 70, y: 86, width: 40, height: 24))
    }

    func testGroupedWidgetsMoveTogether() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        store.snapToGrid = false
        let a = store.create(from: simpleDefinition(), placement: Placement(x: 0, y: 0, width: 100, height: 100, displayID: nil))
        let b = store.create(from: simpleDefinition(), placement: Placement(x: 200, y: 50, width: 100, height: 100, displayID: nil))
        let group = store.group([a.id, b.id])
        store.move(a.id, to: Placement(x: 30, y: 10, width: 100, height: 100, displayID: nil))
        XCTAssertEqual(store.widget(b.id)?.placement.x, 230)
        XCTAssertEqual(store.widget(b.id)?.placement.y, 60)
        store.ungroup(group!)
        store.move(a.id, to: Placement(x: 0, y: 0, width: 100, height: 100, displayID: nil))
        XCTAssertEqual(store.widget(b.id)?.placement.x, 230)
    }

    func testAlignAndDistribute() {
        let rects = [Rect(x: 10, y: 10, width: 50, height: 20), Rect(x: 100, y: 40, width: 30, height: 30), Rect(x: 300, y: 90, width: 20, height: 10)]
        XCTAssertEqual(LayoutEngine.align(rects, mode: .left).map(\.x), [10, 10, 10])
        XCTAssertEqual(LayoutEngine.align(rects, mode: .right).map(\.maxX), [320, 320, 320])
        XCTAssertEqual(LayoutEngine.align(rects, mode: .top).map(\.y), [10, 10, 10])
        XCTAssertEqual(LayoutEngine.align(rects, mode: .centerVertically).map(\.midY), [55, 55, 55])
        let distributed = LayoutEngine.align(rects, mode: .distributeHorizontally)
        XCTAssertEqual(distributed[0].x, 10)
        XCTAssertEqual(distributed[2].maxX, 320)
        XCTAssertEqual(distributed[1].minX - distributed[0].maxX, distributed[2].minX - distributed[1].maxX, accuracy: 0.001)
    }

    func testAlignmentGuides() {
        let other = Rect(x: 100, y: 100, width: 80, height: 40)
        let result = LayoutEngine.guides(moving: Rect(x: 103, y: 200, width: 50, height: 50), others: [other])
        XCTAssertEqual(result.rect.x, 100)
        XCTAssertEqual(result.guides, [AlignmentGuide(axis: .vertical, position: 100)])
        let none = LayoutEngine.guides(moving: Rect(x: 500, y: 500, width: 10, height: 10), others: [other])
        XCTAssertTrue(none.guides.isEmpty)
    }

    func testPlacementSurvivesDisplayDisconnect() {
        let main = display("main", main: true)
        let external = display("ext", x: 1440, width: 1920, height: 1080)
        let global = Rect(x: 1440 + 1500, y: 800, width: 200, height: 100)
        let placement = LayoutEngine.placement(forGlobal: global, in: [main, external])
        XCTAssertEqual(placement.displayID, "ext")
        XCTAssertEqual(placement.x, 1500)

        // External display unplugged: the widget is shown on the main display, clamped on-screen…
        let fallback = LayoutEngine.globalRect(for: placement, in: [main])!
        XCTAssertEqual(fallback.maxX, 1440)
        XCTAssertEqual(fallback.maxY, 900)
        // …and because the stored placement is untouched, it returns when the display is reconnected.
        XCTAssertEqual(LayoutEngine.globalRect(for: placement, in: [main, external]), global)
        XCTAssertNil(LayoutEngine.globalRect(for: placement, in: []))
    }

    func testFreeSlotAvoidsOverlap() {
        let bounds = Rect(x: 0, y: 0, width: 800, height: 600)
        let occupied = [Rect(x: 24, y: 24, width: 200, height: 100)]
        let slot = LayoutEngine.freeSlot(size: WidgetSize(200, 100), occupied: occupied, in: bounds)
        XCTAssertFalse(slot.intersects(occupied[0]))
        XCTAssertEqual(LayoutEngine.clamp(slot, to: bounds), slot)
    }

    func testResponsiveConstraints() {
        let old = WidgetSize(200, 100), new = WidgetSize(300, 160)
        let frame = Rect(x: 10, y: 10, width: 100, height: 20)
        XCTAssertEqual(LayoutEngine.applyConstraints(frame, NodeConstraints(), oldSize: old, newSize: new), frame)
        XCTAssertEqual(LayoutEngine.applyConstraints(frame, NodeConstraints(pinLeft: true, pinTop: true, pinRight: true, pinBottom: true), oldSize: old, newSize: new),
                       Rect(x: 10, y: 10, width: 200, height: 80))
        XCTAssertEqual(LayoutEngine.applyConstraints(frame, NodeConstraints(pinLeft: false, pinTop: false, pinRight: true, pinBottom: true), oldSize: old, newSize: new),
                       Rect(x: 110, y: 70, width: 100, height: 20))
    }

    func testSavedLayoutRestore() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        store.snapToGrid = false
        let w = store.create(from: simpleDefinition(), placement: Placement(x: 5, y: 5, width: 100, height: 100, displayID: nil))
        let layout = store.saveLayout(named: "Before")
        store.move(w.id, to: Placement(x: 500, y: 300, width: 100, height: 100, displayID: nil))
        store.update(w.id) { $0.hidden = true }
        store.restoreLayout(layout.id)
        XCTAssertEqual(store.widget(w.id)?.placement.x, 5)
        XCTAssertEqual(store.widget(w.id)?.hidden, false)
    }
}

final class ProfileTests: XCTestCase {
    func setup() -> (WidgetStore, ProfileManager, InMemoryDocumentStore, [WidgetInstance]) {
        let db = InMemoryDocumentStore()
        let store = WidgetStore(db: db)
        store.snapToGrid = false
        let widgets = ["Clock", "CPU", "Notes"].map { store.create(from: simpleDefinition($0)) }
        let manager = ProfileManager(db: db, store: store)
        return (store, manager, db, widgets)
    }

    func testSwitchingShowsOnlyMembers() {
        let (store, manager, _, w) = setup()
        let work = manager.upsert(Profile(name: "Work", widgetIDs: [w[0].id, w[2].id]))
        let dev = manager.upsert(Profile(name: "Development", widgetIDs: [w[1].id]))
        manager.activate(work.id)
        XCTAssertEqual(store.widgets.filter { !$0.hidden }.map(\.name), ["Clock", "Notes"])
        manager.activate(dev.id)
        XCTAssertEqual(store.widgets.filter { !$0.hidden }.map(\.name), ["CPU"])
        manager.activate(nil)
        XCTAssertTrue(store.widgets.allSatisfy { !$0.hidden })
    }

    func testPerProfileLayoutIsRestored() {
        let (store, manager, _, w) = setup()
        let work = manager.upsert(Profile(name: "Work", widgetIDs: [w[0].id]))
        let focus = manager.upsert(Profile(name: "Focus", widgetIDs: [w[0].id]))
        manager.activate(work.id)
        store.move(w[0].id, to: Placement(x: 700, y: 20, width: 200, height: 100, displayID: nil))
        manager.activate(focus.id)
        store.move(w[0].id, to: Placement(x: 50, y: 500, width: 200, height: 100, displayID: nil))
        manager.activate(work.id)
        XCTAssertEqual(store.widget(w[0].id)?.placement.x, 700)
        manager.activate(focus.id)
        XCTAssertEqual(store.widget(w[0].id)?.placement.y, 500)
    }

    func testPersistenceAndRestoreAfterRelaunch() {
        let (store, manager, db, w) = setup()
        let work = manager.upsert(Profile(name: "Work", widgetIDs: [w[1].id]))
        manager.activate(work.id)

        let store2 = WidgetStore(db: db)
        store2.load()
        let manager2 = ProfileManager(db: db, store: store2)
        manager2.load()
        XCTAssertEqual(manager2.active?.name, "Work")
        XCTAssertEqual(manager2.state.manualID, work.id)
        manager2.apply()
        XCTAssertEqual(store2.widgets.filter { !$0.hidden }.map(\.name), ["CPU"])
        manager2.delete(work.id)
        XCTAssertNil(manager2.active)
        _ = store
    }

    func testRuleResolution() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!   // a Monday
        }
        let work = Profile(name: "Work", rules: [ProfileRule(kind: .time(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [2, 3, 4, 5, 6]))])
        let dev = Profile(name: "Dev", rules: [ProfileRule(kind: .activeApp(bundleIDs: ["com.apple.dt.Xcode"]))], priority: 5)
        let night = Profile(name: "Night", rules: [ProfileRule(kind: .time(startMinute: 22 * 60, endMinute: 6 * 60, weekdays: []))])
        let desk = Profile(name: "Desk", rules: [ProfileRule(kind: .display(id: ""))], priority: -1)
        let all = [work, dev, night, desk]
        func resolve(_ d: Date, app: String? = nil, displays: [DisplayInfo] = [display("main", main: true)]) -> String? {
            ProfileManager.resolve(profiles: all, manualID: "manual", context: ProfileContext(date: d, frontmostBundleID: app, displays: displays, calendar: calendar))
        }
        XCTAssertEqual(resolve(date(10)), work.id)
        XCTAssertEqual(resolve(date(8, 59)), "manual")
        XCTAssertEqual(resolve(date(17)), "manual")
        XCTAssertEqual(resolve(date(10), app: "com.apple.dt.xcode"), dev.id, "higher priority wins")
        XCTAssertEqual(resolve(date(23)), night.id)
        XCTAssertEqual(resolve(date(5, 30)), night.id)
        XCTAssertEqual(resolve(date(7), displays: [display("main", main: true), display("ext", x: 1440)]), desk.id)
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 10))!
        XCTAssertEqual(ProfileManager.resolve(profiles: [work], manualID: nil, context: ProfileContext(date: sunday, calendar: calendar)), nil)
    }

    func testAutomaticSwitchAndRestoration() {
        let (_, manager, _, w) = setup()
        let personal = manager.upsert(Profile(name: "Personal", widgetIDs: [w[0].id]))
        let dev = manager.upsert(Profile(name: "Development", widgetIDs: [w[1].id], rules: [ProfileRule(kind: .activeApp(bundleIDs: ["com.apple.dt.Xcode"]))]))
        manager.activate(personal.id)
        var switches: [String] = []
        manager.onSwitch = { profile, automatic in switches.append("\(profile?.name ?? "none"):\(automatic)") }

        XCTAssertTrue(manager.evaluate(ProfileContext(date: Date(), frontmostBundleID: "com.apple.dt.Xcode")))
        XCTAssertEqual(manager.active?.id, dev.id)
        XCTAssertFalse(manager.evaluate(ProfileContext(date: Date(), frontmostBundleID: "com.apple.dt.Xcode")), "no repeat switch")
        XCTAssertTrue(manager.evaluate(ProfileContext(date: Date(), frontmostBundleID: "com.apple.Safari")))
        XCTAssertEqual(manager.active?.id, personal.id, "returns to the manual profile")
        XCTAssertEqual(switches, ["Development:true", "Personal:true"])

        manager.setAutomaticSwitching(false)
        XCTAssertFalse(manager.evaluate(ProfileContext(date: Date(), frontmostBundleID: "com.apple.dt.Xcode")))
    }
}
