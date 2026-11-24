import SwiftUI
import AppKit

/// How the inspector edits one prop.
struct PropSpec: Identifiable {
    enum Kind {
        case text, multiline, number(ClosedRange<Double>, step: Double), color, bool, choice([String]), action, json, symbol
    }
    let key: String
    let label: String
    let kind: Kind
    var id: String { key }

    static let typography: [PropSpec] = [
        PropSpec(key: "fontSize", label: "Size", kind: .number(6...120, step: 1)),
        PropSpec(key: "fontWeight", label: "Weight", kind: .choice(["light", "regular", "medium", "semibold", "bold", "heavy"])),
        PropSpec(key: "fontDesign", label: "Design", kind: .choice(["default", "rounded", "monospaced", "serif"])),
        PropSpec(key: "color", label: "Colour", kind: .color),
        PropSpec(key: "alignment", label: "Align", kind: .choice(["leading", "center", "trailing"])),
    ]

    static let decoration: [PropSpec] = [
        PropSpec(key: "background", label: "Fill", kind: .color),
        PropSpec(key: "cornerRadius", label: "Radius", kind: .number(0...60, step: 1)),
        PropSpec(key: "padding", label: "Padding", kind: .number(0...40, step: 1)),
        PropSpec(key: "borderColor", label: "Border", kind: .color),
        PropSpec(key: "borderWidth", label: "Border width", kind: .number(0...10, step: 0.5)),
        PropSpec(key: "shadowRadius", label: "Shadow", kind: .number(0...30, step: 1)),
        PropSpec(key: "opacity", label: "Opacity", kind: .number(0...1, step: 0.05)),
        PropSpec(key: "animation", label: "Animation", kind: .choice(["none", "fade", "pulse", "bounce"])),
    ]

    /// Content props for each component type, in inspector order.
    static func content(for type: NodeType) -> [PropSpec] {
        switch type {
        case .text: return [PropSpec(key: "value", label: "Text", kind: .multiline), PropSpec(key: "lineLimit", label: "Max lines", kind: .number(0...20, step: 1))]
        case .richText: return [PropSpec(key: "value", label: "Markdown", kind: .multiline)]
        case .button:
            return [PropSpec(key: "title", label: "Title", kind: .text), PropSpec(key: "symbol", label: "Symbol", kind: .symbol),
                    PropSpec(key: "style", label: "Style", kind: .choice(["bordered", "prominent", "plain"])), PropSpec(key: "action", label: "Action", kind: .action)]
        case .image:
            return [PropSpec(key: "symbol", label: "Symbol", kind: .symbol), PropSpec(key: "url", label: "Image URL (https)", kind: .text),
                    PropSpec(key: "contentMode", label: "Scaling", kind: .choice(["fit", "fill"]))]
        case .icon: return [PropSpec(key: "symbol", label: "Symbol", kind: .symbol), PropSpec(key: "size", label: "Size", kind: .number(6...120, step: 1))]
        case .clock: return [PropSpec(key: "format", label: "Format", kind: .choice(["HH:mm", "HH:mm:ss", "h:mm a", "h:mm:ss a"])), PropSpec(key: "timezone", label: "Time zone", kind: .text)]
        case .date: return [PropSpec(key: "format", label: "Format", kind: .choice(["EEEE, MMM d", "EEEE, MMMM d", "MMM d, yyyy", "yyyy-MM-dd", "EEE d"])), PropSpec(key: "timezone", label: "Time zone", kind: .text)]
        case .progress:
            return [PropSpec(key: "value", label: "Value (0–1)", kind: .text), PropSpec(key: "max", label: "Maximum", kind: .text), PropSpec(key: "label", label: "Label", kind: .text),
                    PropSpec(key: "valueLabel", label: "Value label", kind: .text), PropSpec(key: "tint", label: "Tint", kind: .color)]
        case .gauge:
            return [PropSpec(key: "value", label: "Value", kind: .text), PropSpec(key: "min", label: "Minimum", kind: .text), PropSpec(key: "max", label: "Maximum", kind: .text),
                    PropSpec(key: "label", label: "Label", kind: .text), PropSpec(key: "valueLabel", label: "Value label", kind: .text),
                    PropSpec(key: "gaugeStyle", label: "Style", kind: .choice(["ring", "linear"])), PropSpec(key: "tint", label: "Tint", kind: .color)]
        case .slider:
            return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "label", label: "Label", kind: .text), PropSpec(key: "min", label: "Minimum", kind: .number(-10000...10000, step: 1)),
                    PropSpec(key: "max", label: "Maximum", kind: .number(-10000...10000, step: 1)), PropSpec(key: "step", label: "Step", kind: .number(0...1000, step: 0.5)),
                    PropSpec(key: "onChange", label: "On change", kind: .action)]
        case .toggle: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "label", label: "Label", kind: .text), PropSpec(key: "onChange", label: "On change", kind: .action)]
        case .input: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "placeholder", label: "Placeholder", kind: .text), PropSpec(key: "multiline", label: "Multi-line", kind: .bool)]
        case .chart:
            return [PropSpec(key: "chartKind", label: "Type", kind: .choice(["line", "bar", "area", "pie", "donut", "sparkline"])), PropSpec(key: "values", label: "Data", kind: .json),
                    PropSpec(key: "title", label: "Title", kind: .text), PropSpec(key: "color", label: "Colour", kind: .color), PropSpec(key: "showAxes", label: "Show axes", kind: .bool),
                    PropSpec(key: "yMin", label: "Y minimum", kind: .text), PropSpec(key: "yMax", label: "Y maximum", kind: .text), PropSpec(key: "threshold", label: "Threshold", kind: .text),
                    PropSpec(key: "xPath", label: "Label field", kind: .text), PropSpec(key: "yPath", label: "Value field", kind: .text)]
        case .table: return [PropSpec(key: "items", label: "Rows", kind: .json), PropSpec(key: "columns", label: "Columns", kind: .json), PropSpec(key: "limit", label: "Max rows", kind: .number(1...50, step: 1))]
        case .list:
            return [PropSpec(key: "items", label: "Items", kind: .json), PropSpec(key: "titlePath", label: "Title field", kind: .text), PropSpec(key: "subtitlePath", label: "Subtitle field", kind: .text),
                    PropSpec(key: "trailingPath", label: "Trailing field", kind: .text), PropSpec(key: "urlPath", label: "Link field", kind: .text),
                    PropSpec(key: "symbol", label: "Row symbol", kind: .symbol), PropSpec(key: "limit", label: "Max rows", kind: .number(1...50, step: 1)), PropSpec(key: "emptyText", label: "Empty text", kind: .text)]
        case .calendar: return [PropSpec(key: "showEvents", label: "Uses calendar events", kind: .bool)]
        case .weather:
            return [PropSpec(key: "temperature", label: "Temperature", kind: .text), PropSpec(key: "code", label: "WMO code", kind: .text), PropSpec(key: "high", label: "High", kind: .text),
                    PropSpec(key: "low", label: "Low", kind: .text), PropSpec(key: "location", label: "Location", kind: .text), PropSpec(key: "unit", label: "Unit", kind: .text)]
        case .apiViewer: return [PropSpec(key: "value", label: "Value", kind: .text), PropSpec(key: "source", label: "Source id", kind: .text)]
        case .metric: return [PropSpec(key: "metric", label: "Metric", kind: .choice(["cpu", "memory", "storage", "network", "battery", "system"]))]
        case .web: return [PropSpec(key: "url", label: "URL", kind: .text)]
        case .todo: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "placeholder", label: "Placeholder", kind: .text)]
        case .pomodoro: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "workMinutes", label: "Focus minutes", kind: .text), PropSpec(key: "breakMinutes", label: "Break minutes", kind: .text)]
        case .habits: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "habits", label: "Habits", kind: .json)]
        case .countdown: return [PropSpec(key: "target", label: "Target date", kind: .text), PropSpec(key: "label", label: "Label", kind: .text)]
        case .clipboard: return [PropSpec(key: "bind", label: "State key", kind: .text), PropSpec(key: "limit", label: "Max items", kind: .number(1...20, step: 1))]
        case .column, .row: return [PropSpec(key: "spacing", label: "Spacing", kind: .number(0...60, step: 1)), PropSpec(key: "alignment", label: "Alignment", kind: .choice(["leading", "center", "trailing", "top", "bottom"]))]
        case .spacer: return [PropSpec(key: "length", label: "Length", kind: .number(0...400, step: 1))]
        case .canvas, .stack, .divider, .script, .media: return []
        }
    }

    static func hasTypography(_ type: NodeType) -> Bool { [.text, .richText, .button, .clock, .date, .input, .countdown, .apiViewer].contains(type) }
}

struct ConsoleLine: Identifiable {
    let id = UUID()
    let date = Date()
    let isError: Bool
    let text: String
}

/// Editing state for one widget document: selection, undo history and every canvas operation.
@MainActor
final class BuilderModel: ObservableObject {
    @Published private(set) var document: WidgetDefinition
    @Published var selection: Set<String> = []
    @Published private(set) var guides: [AlignmentGuide] = []
    @Published var showGrid = true
    @Published var snapToGrid = true
    @Published var zoom = 1.0
    @Published var isPreviewing = false
    @Published var runScriptInPreview = false
    @Published private(set) var console: [ConsoleLine] = []
    @Published private(set) var validation = ValidationReport()
    @Published private(set) var isDirty = false

    private var undoStack: [WidgetDefinition] = []
    private var redoStack: [WidgetDefinition] = []
    private var dragOrigin: [String: Rect]?
    let gridSize = 8.0
    static let pasteboardType = NSPasteboard.PasteboardType("com.widgetforge.nodes")

    init(document: WidgetDefinition) {
        self.document = BuilderModel.canvasForm(of: document)
        revalidate()
    }

    /// The builder edits absolute-layout canvases. A flow-layout widget (most templates) is wrapped in a canvas
    /// with its original layout as a single full-size, edge-pinned child, so it can be extended freely.
    static func canvasForm(of definition: WidgetDefinition) -> WidgetDefinition {
        guard definition.root.type != .canvas else { return definition }
        var wrapped = definition
        var child = definition.root
        let inner = WidgetSize(max(20, definition.size.width - definition.style.padding * 2), max(20, definition.size.height - definition.style.padding * 2))
        child.frame = NodeFrame(x: 0, y: 0, width: inner.width, height: inner.height)
        child.constraints = NodeConstraints(pinLeft: true, pinTop: true, pinRight: true, pinBottom: true)
        wrapped.root = WidgetNode(.canvas, children: [child])
        return wrapped
    }

    var canvasSize: WidgetSize {
        WidgetSize(max(20, document.size.width - document.style.padding * 2), max(20, document.size.height - document.style.padding * 2))
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedNodes: [WidgetNode] { document.root.children.filter { selection.contains($0.id) } }
    /// The single node shown in the inspector (may be nested, when chosen from the layer outline).
    var inspected: WidgetNode? { selection.count == 1 ? document.root.find(selection.first!) : nil }

    // MARK: History

    /// Apply a change as one undo step.
    func mutate(_ body: (inout WidgetDefinition) -> Void) {
        var next = document
        body(&next)
        guard next != document else { return }
        undoStack.append(document)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        document = next
        isDirty = true
        revalidate()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        selection = selection.filter { document.root.find($0) != nil }
        revalidate()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        selection = selection.filter { document.root.find($0) != nil }
        revalidate()
    }

    func markSaved() { isDirty = false }

    private func revalidate() {
        var candidate = document
        candidate.permissions = candidate.permissions.union(PermissionChecker.required(for: candidate))
        validation = SchemaValidator.validate(definition: (try? JSONValue.encode(candidate)) ?? .null)
    }

    func log(_ text: String, isError: Bool = false) {
        console.append(ConsoleLine(isError: isError, text: text))
        if console.count > 300 { console.removeFirst(console.count - 300) }
    }

    func clearConsole() { console.removeAll() }

    // MARK: Components

    func add(_ type: NodeType, at point: CGPoint? = nil) {
        var node = WidgetNode.paletteDefault(type)
        if var frame = node.frame {
            if let point {
                frame.x = Double(point.x) - frame.width / 2
                frame.y = Double(point.y) - frame.height / 2
            } else {
                let offset = Double(document.root.children.count % 6) * 12
                frame.x = 16 + offset; frame.y = 16 + offset
            }
            if snapToGrid { frame = NodeFrame(LayoutEngine.snap(frame.rect, grid: gridSize)) }
            frame = NodeFrame(LayoutEngine.clamp(frame.rect, to: Rect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)))
            node.frame = frame
        }
        mutate { $0.root.children.append(node) }
        selection = [node.id]
        if type == .script, !document.hasScript {
            mutate { $0.script = TemplateLibrary.customScript.script }
            log("Added a starter script. Edit it in the Script tab.")
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate { _ = $0.root.remove(ids) }
        selection = []
    }

    func duplicateSelection() {
        let copies = selectedNodes.map { node -> WidgetNode in
            var copy = node.withFreshIDs()
            copy.groupID = nil
            if var frame = copy.frame { frame.x += 16; frame.y += 16; copy.frame = frame }
            return copy
        }
        guard !copies.isEmpty else { return }
        mutate { $0.root.children.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    func copySelection() {
        guard !selectedNodes.isEmpty, let data = try? JSONEncoder().encode(selectedNodes) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: BuilderModel.pasteboardType)
    }

    func paste() {
        guard let data = NSPasteboard.general.data(forType: BuilderModel.pasteboardType),
              let nodes = try? JSONDecoder().decode([WidgetNode].self, from: data) else { return }
        let copies = nodes.map { node -> WidgetNode in
            var copy = node.withFreshIDs()
            copy.groupID = nil
            if var frame = copy.frame { frame.x += 16; frame.y += 16; copy.frame = frame }
            return copy
        }
        mutate { $0.root.children.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    // MARK: Selection

    func select(_ id: String, extend: Bool) {
        var ids: Set<String> = [id]
        // Selecting one member of a group selects the whole group.
        if let group = document.root.children.first(where: { $0.id == id })?.groupID {
            ids.formUnion(document.root.children.filter { $0.groupID == group }.map(\.id))
        }
        if extend {
            if selection.isSuperset(of: ids) { selection.subtract(ids) } else { selection.formUnion(ids) }
        } else {
            selection = ids
        }
    }

    func selectAll() { selection = Set(document.root.children.map(\.id)) }

    func select(in rect: Rect) {
        selection = Set(document.root.children.filter { ($0.frame?.rect).map(rect.intersects) ?? false }.map(\.id))
    }

    // MARK: Move and resize

    /// Live drag of the current selection by a total translation; one undo step for the whole gesture.
    func drag(by translation: CGSize, bypassSnapping: Bool = false) {
        if dragOrigin == nil {
            var origin: [String: Rect] = [:]
            for node in selectedNodes { origin[node.id] = node.frame?.rect }
            dragOrigin = origin
            undoStack.append(document)
            redoStack.removeAll()
        }
        guard let origin = dragOrigin, let box = Rect.union(Array(origin.values)) else { return }
        var moved = box.offset(dx: Double(translation.width), dy: Double(translation.height))
        guides = []
        if !bypassSnapping {
            let others = document.root.children.filter { !selection.contains($0.id) }.compactMap { $0.frame?.rect }
            let snapped = LayoutEngine.guides(moving: moved, others: others, container: Rect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height), threshold: 5)
            moved = snapped.rect
            guides = snapped.guides
            if guides.isEmpty, snapToGrid { moved = LayoutEngine.snap(moved, grid: gridSize) }
        }
        let dx = moved.x - box.x, dy = moved.y - box.y
        for (id, rect) in origin {
            document.root.update(id) { $0.frame = NodeFrame(rect.offset(dx: dx, dy: dy)) }
        }
    }

    func resize(_ id: String, handle: ResizeHandle, by translation: CGSize) {
        if dragOrigin == nil {
            guard let rect = document.root.find(id)?.frame?.rect else { return }
            dragOrigin = [id: rect]
            undoStack.append(document)
            redoStack.removeAll()
        }
        guard let start = dragOrigin?[id] else { return }
        var rect = LayoutEngine.resize(start, handle: handle, dx: Double(translation.width), dy: Double(translation.height), minWidth: 12, minHeight: 8)
        if snapToGrid { rect = LayoutEngine.snap(rect, grid: gridSize, snapSize: true) }
        document.root.update(id) { $0.frame = NodeFrame(rect) }
    }

    func endDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        guides = []
        if undoStack.last == document { undoStack.removeLast() } else { isDirty = true }
        revalidate()
    }

    func nudge(dx: Double, dy: Double) {
        let ids = selection
        mutate { doc in
            for id in ids { doc.root.update(id) { if var f = $0.frame { f.x += dx; f.y += dy; $0.frame = f } } }
        }
    }

    func align(_ mode: AlignMode) {
        let nodes = selectedNodes.filter { $0.frame != nil }
        guard nodes.count > 1 else { return }
        let aligned = LayoutEngine.align(nodes.map { $0.frame!.rect }, mode: mode)
        mutate { doc in
            for (node, rect) in zip(nodes, aligned) { doc.root.update(node.id) { $0.frame = NodeFrame(rect) } }
        }
    }

    // MARK: Layers and groups

    enum LayerMove { case front, back, forward, backward }

    func reorder(_ move: LayerMove) {
        let ids = selection
        mutate { doc in
            var children = doc.root.children
            let picked = children.filter { ids.contains($0.id) }
            guard !picked.isEmpty else { return }
            switch move {
            case .front: children = children.filter { !ids.contains($0.id) } + picked
            case .back: children = picked + children.filter { !ids.contains($0.id) }
            case .forward:
                for index in children.indices.reversed() where ids.contains(children[index].id) && index + 1 < children.count && !ids.contains(children[index + 1].id) {
                    children.swapAt(index, index + 1)
                }
            case .backward:
                for index in children.indices where ids.contains(children[index].id) && index > 0 && !ids.contains(children[index - 1].id) {
                    children.swapAt(index, index - 1)
                }
            }
            doc.root.children = children
        }
    }

    func groupSelection() {
        guard selectedNodes.count > 1 else { return }
        let group = WidgetNode.newID()
        let ids = Set(selectedNodes.map(\.id))
        mutate { doc in for id in ids { doc.root.update(id) { $0.groupID = group } } }
    }

    func ungroupSelection() {
        let ids = Set(selectedNodes.map(\.id))
        mutate { doc in for id in ids { doc.root.update(id) { $0.groupID = nil } } }
    }

    // MARK: Properties

    func setProp(_ id: String, _ key: String, _ value: JSONValue?) {
        mutate { doc in
            doc.root.update(id) { node in
                if let value, !(value.stringValue == "" && !["value", "title", "label"].contains(key)) { node.props[key] = value } else { node.props[key] = nil }
            }
        }
    }

    func setFrame(_ id: String, _ frame: NodeFrame) {
        mutate { $0.root.update(id) { $0.frame = frame } }
    }

    func setConstraints(_ id: String, _ constraints: NodeConstraints) {
        mutate { $0.root.update(id) { $0.constraints = constraints } }
    }

    /// Change the widget size, moving children according to their constraints (responsive layout).
    func setSize(_ size: WidgetSize) {
        let old = canvasSize
        mutate { doc in
            doc.size = WidgetSize(min(2400, max(60, size.width)), min(2400, max(60, size.height)))
            let new = WidgetSize(max(20, doc.size.width - doc.style.padding * 2), max(20, doc.size.height - doc.style.padding * 2))
            for index in doc.root.children.indices {
                guard let frame = doc.root.children[index].frame else { continue }
                let rect = LayoutEngine.applyConstraints(frame.rect, doc.root.children[index].constraints ?? NodeConstraints(), oldSize: old, newSize: new)
                doc.root.children[index].frame = NodeFrame(rect)
                // Frames now describe the new design size, so constraints start fresh from here.
            }
        }
    }

    /// The definition to save or run: permissions are widened to whatever the content now needs.
    func exportDefinition() -> WidgetDefinition {
        var definition = document
        definition.permissions = definition.permissions.union(PermissionChecker.required(for: definition))
        return definition
    }
}
