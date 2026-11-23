import Foundation

/// Every component a declarative widget can contain. Unknown types are rejected by `SchemaValidator`.
enum NodeType: String, Codable, CaseIterable, Sendable {
    // Layout
    case canvas, column, row, stack, spacer, divider
    // Content
    case text, richText, button, image, icon, clock, date, progress, gauge, slider, toggle, input
    case chart, table, list, calendar, weather, apiViewer, metric, web, script
    // Stateful productivity components
    case todo, pomodoro, habits, countdown, clipboard, media

    var isContainer: Bool { [.canvas, .column, .row, .stack].contains(self) }

    var displayName: String {
        switch self {
        case .richText: return "Rich Text"
        case .apiViewer: return "API Response"
        case .metric: return "System Metric"
        case .web: return "Web Content"
        case .script: return "Custom Script"
        case .todo: return "To-do List"
        case .progress: return "Progress Bar"
        case .input: return "Input Field"
        case .media: return "Media Controls"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var symbol: String {
        switch self {
        case .canvas: return "rectangle.dashed"
        case .column: return "rectangle.split.1x2"
        case .row: return "rectangle.split.2x1"
        case .stack: return "square.stack"
        case .spacer: return "arrow.left.and.right"
        case .divider: return "minus"
        case .text: return "textformat"
        case .richText: return "text.alignleft"
        case .button: return "button.programmable"
        case .image: return "photo"
        case .icon: return "star"
        case .clock: return "clock"
        case .date: return "calendar.day.timeline.left"
        case .progress: return "chart.bar.fill"
        case .gauge: return "gauge.medium"
        case .slider: return "slider.horizontal.3"
        case .toggle: return "switch.2"
        case .input: return "character.cursor.ibeam"
        case .chart: return "chart.xyaxis.line"
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .apiViewer: return "curlybraces"
        case .metric: return "cpu"
        case .web: return "globe"
        case .script: return "chevron.left.forwardslash.chevron.right"
        case .todo: return "checklist"
        case .pomodoro: return "timer"
        case .habits: return "flame"
        case .countdown: return "hourglass"
        case .clipboard: return "doc.on.clipboard"
        case .media: return "playpause"
        }
    }

    /// Components offered in the visual builder palette, in display order.
    static let palette: [NodeType] = [
        .text, .richText, .button, .image, .icon, .clock, .date, .progress, .gauge, .slider, .toggle, .input,
        .chart, .table, .list, .calendar, .weather, .apiViewer, .metric, .web, .script,
        .todo, .pomodoro, .habits, .countdown, .clipboard, .media, .divider,
    ]
}

struct NodeFrame: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var rect: Rect { Rect(x: x, y: y, width: width, height: height) }
    init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    init(_ r: Rect) { x = r.x; y = r.y; width = r.width; height = r.height }
}

/// Responsive behaviour of a canvas child when its widget is resized.
struct NodeConstraints: Codable, Hashable, Sendable {
    var pinLeft = true
    var pinTop = true
    var pinRight = false
    var pinBottom = false
}

/// One element of the declarative widget tree.
struct WidgetNode: Hashable, Identifiable, Sendable {
    var id: String
    var type: NodeType
    var props: [String: JSONValue]
    var children: [WidgetNode]
    /// Position inside a `canvas` parent. Ignored by flow containers.
    var frame: NodeFrame?
    var constraints: NodeConstraints?
    var groupID: String?

    init(_ type: NodeType, id: String = WidgetNode.newID(), props: [String: JSONValue] = [:],
         frame: NodeFrame? = nil, children: [WidgetNode] = []) {
        self.id = id; self.type = type; self.props = props; self.children = children; self.frame = frame
    }

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    private static let structuralKeys: Set<String> = ["id", "type", "props", "children", "frame", "constraints", "groupID"]

    /// Lenient construction from JSON. Besides the canonical `{type, props:{…}}` form this accepts the SDK
    /// shorthand `{type: "text", value: "Hi"}` where props sit beside `type`.
    init(json: JSONValue) throws {
        guard let object = json.objectValue else { throw SchemaError("A node must be an object") }
        guard let typeName = object["type"]?.stringValue else { throw SchemaError("A node is missing its \"type\"") }
        guard let type = NodeType(rawValue: typeName) else { throw SchemaError("Unknown component type \"\(typeName)\"") }
        self.type = type
        id = object["id"]?.stringValue ?? WidgetNode.newID()
        var props = object["props"]?.objectValue ?? [:]
        for (key, value) in object where !WidgetNode.structuralKeys.contains(key) { props[key] = value }
        self.props = props
        children = try (object["children"]?.arrayValue ?? []).map(WidgetNode.init(json:))
        frame = try object["frame"].flatMap { $0.isNull ? nil : try $0.decode(NodeFrame.self) }
        if let c = object["constraints"]?.objectValue {
            constraints = NodeConstraints(pinLeft: c["pinLeft"]?.boolValue ?? true, pinTop: c["pinTop"]?.boolValue ?? true,
                                          pinRight: c["pinRight"]?.boolValue ?? false, pinBottom: c["pinBottom"]?.boolValue ?? false)
        }
        groupID = object["groupID"]?.stringValue
    }

    // MARK: Prop helpers

    func string(_ key: String) -> String? { props[key]?.stringValue }
    func number(_ key: String) -> Double? { props[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { props[key]?.boolValue }

    // MARK: Tree operations

    /// All nodes in depth-first order, including self.
    var flattened: [WidgetNode] { [self] + children.flatMap(\.flattened) }

    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }

    func find(_ id: String) -> WidgetNode? {
        if self.id == id { return self }
        for child in children { if let hit = child.find(id) { return hit } }
        return nil
    }

    /// Mutate the node with the given id anywhere in the tree. Returns true if found.
    @discardableResult
    mutating func update(_ id: String, _ body: (inout WidgetNode) -> Void) -> Bool {
        if self.id == id { body(&self); return true }
        for i in children.indices {
            if children[i].update(id, body) { return true }
        }
        return false
    }

    @discardableResult
    mutating func remove(_ ids: Set<String>) -> [WidgetNode] {
        var removed = children.filter { ids.contains($0.id) }
        children.removeAll { ids.contains($0.id) }
        for i in children.indices { removed += children[i].remove(ids) }
        return removed
    }

    /// A deep copy with fresh ids (used by copy/paste and duplicate).
    func withFreshIDs() -> WidgetNode {
        var copy = self
        copy.id = WidgetNode.newID()
        copy.children = children.map { $0.withFreshIDs() }
        return copy
    }
}

extension WidgetNode: Codable {
    init(from decoder: Decoder) throws {
        try self.init(json: JSONValue(from: decoder))
    }

    private enum CodingKeys: String, CodingKey { case id, type, props, children, frame, constraints, groupID }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        if !props.isEmpty { try c.encode(props, forKey: .props) }
        if !children.isEmpty { try c.encode(children, forKey: .children) }
        try c.encodeIfPresent(frame, forKey: .frame)
        try c.encodeIfPresent(constraints, forKey: .constraints)
        try c.encodeIfPresent(groupID, forKey: .groupID)
    }
}

struct SchemaError: Error, LocalizedError, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// What happens when the user interacts with a button, list row or other control.
/// Actions are data, never code: the host interprets them and checks permissions first.
enum WidgetAction: Hashable, Sendable {
    case setState(key: String, value: JSONValue)
    case toggleState(key: String)
    case incrementState(key: String, by: Double)
    case openURL(String)
    case runShortcut(String)
    case launchApp(String)
    case refresh
    case trigger(String)              // fires the "widget interaction" automation trigger with this name
    case script(String)               // calls a named action handler in the widget's own script
    case media(String)                // playpause | next | previous
    case copy(String)                 // copies a template-resolved string to the clipboard

    init?(json: JSONValue?) {
        guard let o = json?.objectValue, let type = o["type"]?.stringValue else { return nil }
        let key = o["key"]?.stringValue ?? ""
        switch type {
        case "setState": self = .setState(key: key, value: o["value"] ?? .null)
        case "toggleState": self = .toggleState(key: key)
        case "incrementState": self = .incrementState(key: key, by: o["by"]?.doubleValue ?? 1)
        case "openURL": self = .openURL(o["url"]?.stringValue ?? "")
        case "runShortcut": self = .runShortcut(o["name"]?.stringValue ?? "")
        case "launchApp": self = .launchApp(o["bundleID"]?.stringValue ?? "")
        case "refresh": self = .refresh
        case "trigger": self = .trigger(o["name"]?.stringValue ?? "")
        case "script": self = .script(o["name"]?.stringValue ?? "")
        case "media": self = .media(o["command"]?.stringValue ?? "playpause")
        case "copy": self = .copy(o["text"]?.stringValue ?? "")
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .setState(let key, let value): return ["type": "setState", "key": .string(key), "value": value]
        case .toggleState(let key): return ["type": "toggleState", "key": .string(key)]
        case .incrementState(let key, let by): return ["type": "incrementState", "key": .string(key), "by": .number(by)]
        case .openURL(let url): return ["type": "openURL", "url": .string(url)]
        case .runShortcut(let name): return ["type": "runShortcut", "name": .string(name)]
        case .launchApp(let id): return ["type": "launchApp", "bundleID": .string(id)]
        case .refresh: return ["type": "refresh"]
        case .trigger(let name): return ["type": "trigger", "name": .string(name)]
        case .script(let name): return ["type": "script", "name": .string(name)]
        case .media(let command): return ["type": "media", "command": .string(command)]
        case .copy(let text): return ["type": "copy", "text": .string(text)]
        }
    }

    static let typeNames = ["setState", "toggleState", "incrementState", "openURL", "runShortcut", "launchApp",
                            "refresh", "trigger", "script", "media", "copy"]
}
