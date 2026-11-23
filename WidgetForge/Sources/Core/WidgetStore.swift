import Foundation

/// The source of truth for widgets on the desktop: lifecycle, layout operations and persistence.
/// Not thread-safe by itself; the app confines it to the main actor.
final class WidgetStore {
    private(set) var widgets: [WidgetInstance] = []
    private(set) var trash: [WidgetInstance] = []
    private(set) var layouts: [SavedLayout] = []

    let db: DocumentStore
    var gridSize: Double = 8
    var snapToGrid = true
    /// Called after every mutation with the ids that changed (empty = structural change).
    var onChange: ((Set<String>) -> Void)?
    var onError: ((String) -> Void)?
    static let trashLimit = 30

    init(db: DocumentStore) {
        self.db = db
    }

    // MARK: Persistence

    func load() {
        let report: (String, Error) -> Void = { [weak self] id, error in
            self?.onError?("Skipped unreadable record \(id): \(error.localizedDescription)")
        }
        widgets = ((try? db.loadAll(WidgetInstance.self, from: Collections.widgets, onError: report)) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
        trash = ((try? db.loadAll(WidgetInstance.self, from: Collections.trash, onError: report)) ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
        layouts = ((try? db.loadAll(SavedLayout.self, from: Collections.layouts, onError: report)) ?? [])
            .sorted { $0.savedAt < $1.savedAt }
    }

    private func persist(_ widget: WidgetInstance) {
        do { try db.save(widget, in: Collections.widgets, id: widget.id) }
        catch { onError?("Could not save \(widget.name): \(error.localizedDescription)") }
    }

    func widget(_ id: String) -> WidgetInstance? { widgets.first { $0.id == id } }

    // MARK: Lifecycle

    @discardableResult
    func create(from definition: WidgetDefinition, placement: Placement? = nil, granted: PermissionManifest? = nil,
                origin: WidgetOrigin = .template, scriptTrusted: Bool = false, now: Date = Date()) -> WidgetInstance {
        var def = definition
        def.id = UUID().uuidString
        let place = placement ?? Placement(x: 40 + Double(widgets.count % 8) * 28, y: 40 + Double(widgets.count % 8) * 28,
                                           width: def.size.width, height: def.size.height, displayID: nil)
        let instance = WidgetInstance(definition: def, placement: place, granted: granted ?? def.permissions,
                                      origin: origin, scriptTrusted: scriptTrusted, now: now)
        widgets.append(instance)
        persist(instance)
        onChange?([])
        return instance
    }

    /// Mutate one widget and persist it. Returns false if the id is unknown.
    @discardableResult
    func update(_ id: String, now: Date = Date(), _ body: (inout WidgetInstance) -> Void) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return false }
        let before = widgets[index]
        body(&widgets[index])
        guard widgets[index] != before else { return true }
        widgets[index].updatedAt = now
        persist(widgets[index])
        onChange?([id])
        return true
    }

    func setState(_ id: String, key: String, value: JSONValue) {
        update(id) { $0.state[key] = value }
    }

    /// Moves a widget to the trash, from which it can be restored.
    func delete(_ id: String, now: Date = Date()) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        var removed = widgets.remove(at: index)
        removed.updatedAt = now
        trash.insert(removed, at: 0)
        try? db.delete(Collections.widgets, id: id)
        try? db.save(removed, in: Collections.trash, id: id)
        while trash.count > WidgetStore.trashLimit {
            let old = trash.removeLast()
            try? db.delete(Collections.trash, id: old.id)
        }
        onChange?([])
    }

    @discardableResult
    func restore(_ id: String) -> WidgetInstance? {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return nil }
        var restored = trash.remove(at: index)
        restored.hidden = false
        restored.updatedAt = Date()
        widgets.append(restored)
        try? db.delete(Collections.trash, id: id)
        persist(restored)
        onChange?([])
        return restored
    }

    func emptyTrash() {
        trash.removeAll()
        try? db.deleteAll(Collections.trash)
        onChange?([])
    }

    @discardableResult
    func duplicate(_ id: String, now: Date = Date()) -> WidgetInstance? {
        guard let source = widget(id) else { return nil }
        var copy = source
        copy.id = UUID().uuidString
        copy.definition.id = UUID().uuidString
        copy.definition.name = source.definition.name + " Copy"
        copy.placement.x += 24
        copy.placement.y += 24
        copy.groupID = nil
        copy.locked = false
        copy.createdAt = now
        copy.updatedAt = now
        widgets.append(copy)
        persist(copy)
        onChange?([])
        return copy
    }

    // MARK: Layout

    func move(_ id: String, to placement: Placement) {
        guard let current = widget(id), !current.locked else { return }
        var target = placement
        if snapToGrid {
            let snapped = LayoutEngine.snap(placement.rect, grid: gridSize)
            target.x = snapped.x; target.y = snapped.y
        }
        let dx = target.x - current.placement.x, dy = target.y - current.placement.y
        update(id) { $0.placement = target }
        // Grouped widgets travel together (same display only).
        if let group = current.groupID, dx != 0 || dy != 0 {
            for other in widgets where other.groupID == group && other.id != id && !other.locked {
                update(other.id) { $0.placement.x += dx; $0.placement.y += dy }
            }
        }
    }

    func resize(_ id: String, to placement: Placement) {
        guard let current = widget(id), !current.locked else { return }
        var target = placement
        if snapToGrid {
            let snapped = LayoutEngine.snap(placement.rect, grid: gridSize, snapSize: true)
            target.x = snapped.x; target.y = snapped.y; target.width = snapped.width; target.height = snapped.height
        }
        target.width = max(80, target.width)
        target.height = max(48, target.height)
        update(id) { $0.placement = target }
    }

    func align(_ ids: [String], mode: AlignMode) {
        let targets = ids.compactMap(widget).filter { !$0.locked }
        let aligned = LayoutEngine.align(targets.map(\.placement.rect), mode: mode)
        for (widget, rect) in zip(targets, aligned) {
            update(widget.id) { $0.placement.x = rect.x; $0.placement.y = rect.y }
        }
    }

    func snapAll() {
        for widget in widgets where !widget.locked {
            let r = LayoutEngine.snap(widget.placement.rect, grid: gridSize)
            update(widget.id) { $0.placement.x = r.x; $0.placement.y = r.y }
        }
    }

    @discardableResult
    func group(_ ids: [String]) -> String? {
        guard ids.count > 1 else { return nil }
        let groupID = UUID().uuidString
        for id in ids { update(id) { $0.groupID = groupID } }
        return groupID
    }

    func ungroup(_ groupID: String) {
        for widget in widgets where widget.groupID == groupID { update(widget.id) { $0.groupID = nil } }
    }

    // MARK: Saved layouts

    @discardableResult
    func saveLayout(named name: String, now: Date = Date()) -> SavedLayout {
        var entries: [String: SavedLayout.Entry] = [:]
        for widget in widgets { entries[widget.id] = .init(placement: widget.placement, hidden: widget.hidden) }
        let layout = SavedLayout(name: name, entries: entries, savedAt: now)
        layouts.append(layout)
        try? db.save(layout, in: Collections.layouts, id: layout.id)
        onChange?([])
        return layout
    }

    /// Restores placements for widgets that still exist; widgets created after the layout was saved are untouched.
    func restoreLayout(_ id: String) {
        guard let layout = layouts.first(where: { $0.id == id }) else { return }
        for (widgetID, entry) in layout.entries {
            update(widgetID) { $0.placement = entry.placement; $0.hidden = entry.hidden }
        }
    }

    func deleteLayout(_ id: String) {
        layouts.removeAll { $0.id == id }
        try? db.delete(Collections.layouts, id: id)
        onChange?([])
    }
}
