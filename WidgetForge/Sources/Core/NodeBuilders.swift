import Foundation

/// Convenience constructors for building widget trees in Swift (used by the built-in templates and the
/// visual builder's "new component" defaults). They only assemble data; see docs/SDK.md for the prop reference.
extension WidgetNode {
    static func column(spacing: Double = 6, alignment: String = "leading", _ children: [WidgetNode]) -> WidgetNode {
        WidgetNode(.column, props: ["spacing": .number(spacing), "alignment": .string(alignment)], children: children)
    }

    static func row(spacing: Double = 8, alignment: String = "center", _ children: [WidgetNode]) -> WidgetNode {
        WidgetNode(.row, props: ["spacing": .number(spacing), "alignment": .string(alignment)], children: children)
    }

    static func text(_ value: String, size: Double = 13, weight: String = "regular", color: String = "primary",
                     design: String = "default", lineLimit: Int? = nil) -> WidgetNode {
        var props: [String: JSONValue] = ["value": .string(value), "fontSize": .number(size), "fontWeight": .string(weight),
                                          "color": .string(color), "fontDesign": .string(design)]
        if let lineLimit { props["lineLimit"] = .number(Double(lineLimit)) }
        return WidgetNode(.text, props: props)
    }

    static func title(_ value: String, symbol: String? = nil) -> WidgetNode {
        var children: [WidgetNode] = []
        if let symbol { children.append(.icon(symbol, size: 13, color: "secondary")) }
        children.append(.text(value, size: 12, weight: "semibold", color: "secondary"))
        children.append(.spacer)
        return .row(spacing: 6, children)
    }

    static func icon(_ symbol: String, size: Double = 16, color: String = "accent") -> WidgetNode {
        WidgetNode(.icon, props: ["symbol": .string(symbol), "size": .number(size), "color": .string(color)])
    }

    static var spacer: WidgetNode { WidgetNode(.spacer) }
    static var divider: WidgetNode { WidgetNode(.divider) }

    static func progress(_ value: String, label: String? = nil, valueLabel: String? = nil, tint: String? = nil) -> WidgetNode {
        var props: [String: JSONValue] = ["value": .string(value)]
        if let label { props["label"] = .string(label) }
        if let valueLabel { props["valueLabel"] = .string(valueLabel) }
        if let tint { props["tint"] = .string(tint) }
        return WidgetNode(.progress, props: props)
    }

    static func gauge(_ value: String, label: String, valueLabel: String, tint: String? = nil) -> WidgetNode {
        var props: [String: JSONValue] = ["value": .string(value), "label": .string(label), "valueLabel": .string(valueLabel)]
        if let tint { props["tint"] = .string(tint) }
        return WidgetNode(.gauge, props: props)
    }

    static func chart(_ kind: String, values: String, color: String = "accent", height: Double? = nil,
                      threshold: Double? = nil, extra: [String: JSONValue] = [:]) -> WidgetNode {
        var props: [String: JSONValue] = ["chartKind": .string(kind), "values": .string(values), "color": .string(color)]
        if let height { props["height"] = .number(height) }
        if let threshold { props["threshold"] = .number(threshold) }
        for (k, v) in extra { props[k] = v }
        return WidgetNode(.chart, props: props)
    }

    static func button(_ title: String, symbol: String? = nil, action: WidgetAction, style: String = "bordered") -> WidgetNode {
        var props: [String: JSONValue] = ["title": .string(title), "action": action.json, "style": .string(style)]
        if let symbol { props["symbol"] = .string(symbol) }
        return WidgetNode(.button, props: props)
    }

    static func labeled(_ label: String, _ value: String) -> WidgetNode {
        .row([.text(label, size: 12, color: "secondary", lineLimit: 1), .spacer, .text(value, size: 12, weight: "medium", design: "rounded", lineLimit: 1)])
    }

    /// A hint that is only visible while a data source reports a problem.
    static func statusNote(source: String) -> WidgetNode {
        WidgetNode(.text, props: [
            "value": .string("{{sources.\(source).detail}}"), "fontSize": 10, "color": "orange", "lineLimit": 2,
            "visibleWhen": ["path": .string("sources.\(source).healthy"), "op": "==", "value": false],
        ])
    }

    func with(_ key: String, _ value: JSONValue) -> WidgetNode {
        var copy = self
        copy.props[key] = value
        return copy
    }

    /// Default node for a component dropped onto the builder canvas.
    static func paletteDefault(_ type: NodeType) -> WidgetNode {
        var node: WidgetNode
        var size = WidgetSize(140, 28)
        switch type {
        case .text: node = .text("Text", size: 15, weight: "medium")
        case .richText: node = WidgetNode(.richText, props: ["value": "**Bold**, *italic* and [links](https://apple.com)"]); size = WidgetSize(200, 44)
        case .button: node = .button("Button", action: .refresh); size = WidgetSize(100, 30)
        case .image: node = WidgetNode(.image, props: ["symbol": "photo", "contentMode": "fit"]); size = WidgetSize(96, 96)
        case .icon: node = .icon("star.fill", size: 28); size = WidgetSize(40, 40)
        case .clock: node = WidgetNode(.clock, props: ["format": "HH:mm", "fontSize": 34, "fontWeight": "semibold", "fontDesign": "rounded"]); size = WidgetSize(140, 48)
        case .date: node = WidgetNode(.date, props: ["format": "EEEE, MMM d", "fontSize": 13, "color": "secondary"]); size = WidgetSize(180, 22)
        case .progress: node = .progress("0.5", label: "Progress"); size = WidgetSize(200, 34)
        case .gauge: node = .gauge("0.5", label: "Gauge", valueLabel: "50%"); size = WidgetSize(96, 96)
        case .slider: node = WidgetNode(.slider, props: ["bind": "slider", "min": 0, "max": 100, "label": "Value"]); size = WidgetSize(200, 36)
        case .toggle: node = WidgetNode(.toggle, props: ["bind": "enabled", "label": "Enabled"]); size = WidgetSize(160, 28)
        case .input: node = WidgetNode(.input, props: ["bind": "text", "placeholder": "Type here…"]); size = WidgetSize(200, 28)
        case .chart: node = WidgetNode.chart("line", values: "").with("values", [3, 5, 4, 7, 6, 9, 8]); size = WidgetSize(220, 110)
        case .table:
            node = WidgetNode(.table, props: ["items": "{{state.rows}}", "columns": [["title": "Name", "path": "name"], ["title": "Value", "path": "value"]]])
            size = WidgetSize(240, 120)
        case .list: node = WidgetNode(.list, props: ["items": "{{state.items}}", "titlePath": "title", "subtitlePath": "subtitle"]); size = WidgetSize(220, 120)
        case .calendar: node = WidgetNode(.calendar); size = WidgetSize(220, 190)
        case .weather:
            node = WidgetNode(.weather, props: ["temperature": "{{weather.current.temperature_2m}}", "code": "{{weather.current.weather_code}}", "location": "{{settings.location}}"])
            size = WidgetSize(200, 90)
        case .apiViewer: node = WidgetNode(.apiViewer, props: ["value": "{{api}}"]); size = WidgetSize(260, 140)
        case .metric: node = WidgetNode(.metric, props: ["metric": "cpu"]); size = WidgetSize(200, 54)
        case .web: node = WidgetNode(.web, props: ["url": "https://example.com"]); size = WidgetSize(280, 180)
        case .script: node = WidgetNode(.script); size = WidgetSize(240, 120)
        case .todo: node = WidgetNode(.todo, props: ["bind": "items", "placeholder": "New task"]); size = WidgetSize(240, 180)
        case .pomodoro: node = WidgetNode(.pomodoro, props: ["bind": "pomodoro", "workMinutes": 25, "breakMinutes": 5]); size = WidgetSize(200, 130)
        case .habits: node = WidgetNode(.habits, props: ["bind": "habits", "habits": ["Read", "Exercise", "Meditate"]]); size = WidgetSize(260, 130)
        case .countdown: node = WidgetNode(.countdown, props: ["target": "{{settings.target}}", "label": "Countdown"]); size = WidgetSize(200, 70)
        case .clipboard: node = WidgetNode(.clipboard, props: ["bind": "clips", "limit": 5]); size = WidgetSize(240, 160)
        case .media: node = WidgetNode(.media); size = WidgetSize(180, 44)
        case .divider: node = .divider; size = WidgetSize(160, 8)
        case .spacer: node = .spacer; size = WidgetSize(40, 20)
        case .canvas, .column, .row, .stack: node = WidgetNode(type); size = WidgetSize(200, 120)
        }
        node.frame = NodeFrame(x: 16, y: 16, width: size.width, height: size.height)
        node.constraints = NodeConstraints()
        return node
    }
}

extension DataSourceConfig {
    static func metric(_ name: String, interval: Double = 2) -> DataSourceConfig {
        DataSourceConfig(id: name, name: name.capitalized, kind: .systemMetric, interval: interval, metric: name)
    }
}
