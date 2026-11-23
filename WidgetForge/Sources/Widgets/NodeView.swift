import SwiftUI

/// Renders one node of a declarative widget tree, recursively.
struct NodeView: View {
    let node: WidgetNode
    let env: RenderEnvironment

    var body: some View {
        if env.isVisible(node) {
            content.modifier(NodeDecoration(node: node, tint: env.tint))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.type {
        case .column: ColumnNode(node: node, env: env)
        case .row: RowNode(node: node, env: env)
        case .stack: StackNode(node: node, env: env)
        case .canvas: CanvasNode(node: node, env: env)
        case .spacer: SpacerNode(node: node)
        case .divider: Divider()
        case .text: TextNode(node: node, env: env)
        case .richText: RichTextNode(node: node, env: env)
        case .button: ButtonNode(node: node, env: env)
        case .image: ImageNode(node: node, env: env)
        case .icon: IconNode(node: node, env: env)
        case .clock: ClockNode(node: node, env: env)
        case .date: DateNode(node: node, env: env)
        case .progress: ProgressNode(node: node, env: env)
        case .gauge: GaugeNode(node: node, env: env)
        case .slider: SliderNode(node: node, env: env)
        case .toggle: ToggleNode(node: node, env: env)
        case .input: InputNode(node: node, env: env)
        case .chart: ChartNode(node: node, env: env)
        case .table: TableNode(node: node, env: env)
        case .list: ListNode(node: node, env: env)
        case .calendar: CalendarNode(node: node, env: env)
        case .weather: WeatherNode(node: node, env: env)
        case .apiViewer: APIViewerNode(node: node, env: env)
        case .metric: MetricNode(node: node, env: env)
        case .web: WebNode(node: node, env: env)
        case .script: ScriptNode(env: env)
        case .todo: TodoNode(node: node, env: env)
        case .pomodoro: PomodoroNode(node: node, env: env)
        case .habits: HabitsNode(node: node, env: env)
        case .countdown: CountdownNode(node: node, env: env)
        case .clipboard: ClipboardNode(node: node, env: env)
        case .media: MediaNode(env: env)
        }
    }
}

// MARK: Containers

struct ColumnNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        VStack(alignment: Theme.alignment(node.string("alignment")), spacing: CGFloat(node.number("spacing") ?? 6)) {
            ForEach(node.children) { NodeView(node: $0, env: env) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: columnAlignment)
    }

    private var columnAlignment: Alignment {
        switch node.string("alignment") {
        case "center": return .center
        case "trailing": return .topTrailing
        default: return .topLeading
        }
    }
}

struct RowNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        HStack(alignment: Theme.verticalAlignment(node.string("alignment")), spacing: CGFloat(node.number("spacing") ?? 8)) {
            ForEach(node.children) { NodeView(node: $0, env: env) }
        }
    }
}

struct StackNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        ZStack {
            ForEach(node.children) { NodeView(node: $0, env: env) }
        }
    }
}

/// Absolute layout used by widgets made in the visual builder. Children are positioned by their frames,
/// adjusted by their constraints when the widget is larger or smaller than it was designed.
struct CanvasNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        GeometryReader { proxy in
            let actual = WidgetSize(Double(proxy.size.width), Double(proxy.size.height))
            ZStack(alignment: .topLeading) {
                ForEach(node.children) { child in
                    let frame = CanvasNode.frame(for: child, design: env.designSize, actual: actual)
                    NodeView(node: child, env: env)
                        .frame(width: CGFloat(frame.width), height: CGFloat(frame.height), alignment: .topLeading)
                        .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    static func frame(for child: WidgetNode, design: WidgetSize, actual: WidgetSize) -> Rect {
        let base = child.frame?.rect ?? Rect(x: 0, y: 0, width: 120, height: 28)
        return LayoutEngine.applyConstraints(base, child.constraints ?? NodeConstraints(), oldSize: design, newSize: actual)
    }
}

struct SpacerNode: View {
    let node: WidgetNode
    var body: some View {
        if let length = node.number("length") {
            Spacer().frame(width: CGFloat(length), height: CGFloat(length))
        } else {
            Spacer(minLength: 0)
        }
    }
}

// MARK: Text

struct TextNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let text = Text(env.text(node, "value"))
            .font(Theme.font(node))
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint))
            .multilineTextAlignment(Theme.textAlignment(node.string("alignment")))
            .lineLimit(node.number("lineLimit").map { Int($0) })
            .minimumScaleFactor(0.7)
        if node.string("alignment") != nil {
            text.frame(maxWidth: .infinity, alignment: Theme.frameAlignment(node.string("alignment")))
        } else {
            text
        }
    }
}

struct RichTextNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let source = env.text(node, "value")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        Text(attributed)
            .font(Theme.font(node))
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint))
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(env.tint)
    }
}

struct IconNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        Image(systemName: env.text(node, "symbol", default: "questionmark.square.dashed"))
            .font(.system(size: CGFloat(node.number("size") ?? 16), weight: Theme.weight(node.string("fontWeight"))))
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint, fallback: env.tint))
            .symbolRenderingMode(.hierarchical)
    }
}

struct ImageNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let fill = node.string("contentMode") == "fill"
        if let text = node.string("url"), !text.isEmpty {
            let resolved = env.text(node, "url")
            if let url = URL(string: resolved), let host = url.host, url.scheme == "https",
               PermissionChecker.hostAllowed(host, allowlist: env.imageHosts), !env.isWidgetKit {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                    case .failure: placeholder("exclamationmark.triangle", "Image unavailable")
                    default: ProgressView().controlSize(.small)
                    }
                }
                .clipped()
            } else {
                placeholder("lock", "Image host not allowed")
            }
        } else {
            Image(systemName: env.text(node, "symbol", default: "photo"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.color(node.string("color"), tint: env.tint, fallback: .secondary))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Time

struct ClockNode: View {
    let node: WidgetNode
    let env: RenderEnvironment

    var body: some View {
        let format = env.text(node, "format", default: "HH:mm")
        let zone = TimeZone(identifier: env.text(node, "timezone")) ?? .current
        if let entry = env.entryDate {
            label(entry, format: format, zone: zone)
        } else if format.contains("s") {
            TimelineView(.periodic(from: Date(), by: 1)) { label($0.date, format: format, zone: zone) }
        } else {
            TimelineView(.everyMinute) { label($0.date, format: format, zone: zone) }
        }
    }

    private func label(_ date: Date, format: String, zone: TimeZone) -> some View {
        Text(ClockNode.string(date, format: format, zone: zone))
            .font(Theme.font(node, defaultSize: 28))
            .monospacedDigit()
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    static func string(_ date: Date, format: String, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format.isEmpty ? "HH:mm" : format
        formatter.timeZone = zone
        return formatter.string(from: date)
    }
}

struct DateNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let format = env.text(node, "format", default: "EEEE, MMM d")
        let zone = TimeZone(identifier: env.text(node, "timezone")) ?? .current
        if let entry = env.entryDate {
            label(entry, format: format, zone: zone)
        } else {
            TimelineView(.everyMinute) { label($0.date, format: format, zone: zone) }
        }
    }

    private func label(_ date: Date, format: String, zone: TimeZone) -> some View {
        Text(ClockNode.string(date, format: format, zone: zone))
            .font(Theme.font(node))
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint))
            .lineLimit(1)
    }
}

struct CountdownNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let target = Formatters.date(from: .string(env.text(node, "target")))
        VStack(spacing: 2) {
            let title = env.text(node, "label")
            if !title.isEmpty { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
            if let target {
                if let entry = env.entryDate {
                    remaining(target, from: entry)
                } else {
                    TimelineView(.periodic(from: Date(), by: 1)) { remaining(target, from: $0.date) }
                }
            } else {
                Text("Set a target date").font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
    }

    private func remaining(_ target: Date, from now: Date) -> some View {
        let seconds = target.timeIntervalSince(now)
        return Text(seconds <= 0 ? "Reached" : CountdownNode.format(seconds))
            .font(.system(size: CGFloat(node.number("fontSize") ?? 26), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.color(node.string("color"), tint: env.tint))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    static func format(_ seconds: Double) -> String {
        var s = Int(seconds)
        let d = s / 86_400; s %= 86_400
        let h = s / 3_600; s %= 3_600
        let m = s / 60; s %= 60
        return d > 0 ? String(format: "%dd %02dh %02dm", d, h, m) : String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: Values

struct ProgressNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let maximum = env.number(node, "max") ?? 1
        let raw = env.number(node, "value")
        let fraction = min(1, max(0, (raw ?? 0) / (maximum == 0 ? 1 : maximum)))
        let label = env.text(node, "label")
        let valueLabel = env.text(node, "valueLabel")
        VStack(alignment: .leading, spacing: 3) {
            if !label.isEmpty || !valueLabel.isEmpty {
                HStack {
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(valueLabel).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                }
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.color(node.string("tint"), tint: env.tint, fallback: env.tint))
                .opacity(raw == nil ? 0.35 : 1)
        }
    }
}

struct GaugeNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let minimum = env.number(node, "min") ?? 0
        let maximum = max(minimum + 0.0001, env.number(node, "max") ?? 1)
        let raw = env.number(node, "value")
        let value = min(maximum, max(minimum, raw ?? minimum))
        let tint = Theme.color(node.string("tint"), tint: env.tint, fallback: env.tint)
        VStack(spacing: 2) {
            if node.string("gaugeStyle") == "linear" {
                Gauge(value: value, in: minimum...maximum) { Text(env.text(node, "label")) } currentValueLabel: { Text(valueText(raw)) }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tint)
            } else {
                Gauge(value: value, in: minimum...maximum) { EmptyView() } currentValueLabel: {
                    Text(valueText(raw)).font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                Text(env.text(node, "label")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func valueText(_ raw: Double?) -> String {
        let custom = env.text(node, "valueLabel")
        if !custom.isEmpty { return custom }
        return raw.map { JSONValue.format($0, maxFractionDigits: 1) } ?? "–"
    }
}

struct MetricNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let name = node.string("metric") ?? "cpu"
        let data = env.context[name]
        HStack(spacing: 8) {
            Image(systemName: MetricNode.symbol(name)).foregroundStyle(env.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(MetricNode.title(name)).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text(MetricNode.summary(name, data)).font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                }
                if let fraction = MetricNode.fraction(name, data) {
                    ProgressView(value: min(1, max(0, fraction))).tint(env.tint)
                }
            }
        }
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "memory": return "memorychip"
        case "storage": return "internaldrive"
        case "network": return "network"
        case "battery": return "battery.75percent"
        case "system": return "desktopcomputer"
        default: return "cpu"
        }
    }

    static func title(_ name: String) -> String {
        switch name {
        case "cpu": return "CPU"
        case "memory": return "Memory"
        case "storage": return "Storage"
        case "network": return "Network"
        case "battery": return "Battery"
        default: return "System"
        }
    }

    static func fraction(_ name: String, _ data: JSONValue?) -> Double? {
        switch name {
        case "cpu", "memory", "storage": return data?["usage"]?.doubleValue
        case "battery": return data?["present"]?.boolValue == true ? data?["level"]?.doubleValue : nil
        default: return nil
        }
    }

    static func summary(_ name: String, _ data: JSONValue?) -> String {
        guard let data else { return "No data" }
        func percent(_ key: String) -> String {
            guard let v = data[key], case .number(let d) = v else { return "–" }
            return "\(Int((d * 100).rounded()))%"
        }
        switch name {
        case "cpu", "memory", "storage": return percent("usage")
        case "battery": return data["present"]?.boolValue == true ? percent("level") : "No battery"
        case "network":
            guard let down = data["downBytesPerSec"]?.doubleValue, let up = data["upBytesPerSec"]?.doubleValue else { return "Measuring…" }
            return "↓ \(Formatters.bytes(down))/s  ↑ \(Formatters.bytes(up))/s"
        default: return data["uptimeSeconds"]?.doubleValue.map { "Up \(Formatters.duration($0))" } ?? "–"
        }
    }
}

struct WeatherNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let temperature = env.number(node, "temperature")
        let code = env.number(node, "code").map { Int($0) }
        let look = Theme.weatherSymbol(code: code ?? -1)
        let unit = env.text(node, "unit", default: "°")
        HStack(spacing: 12) {
            Image(systemName: look.symbol)
                .font(.system(size: 34))
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading, spacing: 1) {
                Text(temperature.map { "\(Int($0.rounded()))\(unit)" } ?? "–")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(temperature == nil ? "No data yet" : look.text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(env.text(node, "location")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let high = env.number(node, "high"), let low = env.number(node, "low") {
                    Text("H \(Int(high.rounded()))°  L \(Int(low.rounded()))°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct APIViewerNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let value = env.value(node, "value") ?? .null
        let source = node.string("source") ?? ""
        let state = env.context.path("sources.\(source).state")?.stringValue
        let detail = env.context.path("sources.\(source).detail")?.stringValue ?? ""
        VStack(alignment: .leading, spacing: 4) {
            if let state, state != "ok" {
                Text(detail.isEmpty ? (env.context.path("sources.\(source).label")?.stringValue ?? state) : detail)
                    .font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
            }
            ScrollView {
                Text(value.isNull ? "No response yet" : String(value.prettyJSONString.prefix(6000)))
                    .font(.system(size: CGFloat(node.number("fontSize") ?? 10.5), design: .monospaced))
                    .foregroundStyle(value.isNull ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

struct WebNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        if let make = env.webView, let url = URL(string: env.text(node, "url")), url.scheme == "https" || url.scheme == "http" {
            make(url)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "globe")
                Text(env.isWidgetKit ? "Web content is only available in overlay widgets" : "Web content unavailable")
                    .font(.caption2).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ScriptNode: View {
    let env: RenderEnvironment
    var body: some View {
        if let tree = env.scriptNode {
            NodeView(node: tree, env: env)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title3)
                Text(env.scriptMessage ?? (env.isWidgetKit ? "Scripted widgets run in the desktop overlay only" : "Script not running"))
                    .font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Collections

struct ListNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let items = Array((env.value(node, "items")?.arrayValue ?? []).prefix(Int(node.number("limit") ?? 8)))
        VStack(alignment: .leading, spacing: 5) {
            if items.isEmpty {
                Text(env.text(node, "emptyText", default: "Nothing to show")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ item: JSONValue, _ key: String) -> String? {
        guard let expression = node.string(key), !expression.isEmpty else { return nil }
        return TemplateRenderer.evaluate(expression, context: item, now: env.now).displayString
    }

    @ViewBuilder
    private func row(_ item: JSONValue) -> some View {
        let title = field(item, "titlePath") ?? item.displayString
        let content = HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol = node.string("symbol") { Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(env.tint) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let subtitle = field(item, "subtitlePath"), !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let trailing = field(item, "trailingPath") {
                Text(trailing).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        if let link = field(item, "urlPath"), !link.isEmpty {
            env.button(.openURL(link)) { content.contentShape(Rectangle()) }
        } else {
            content
        }
    }
}

struct TableNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let rows = Array((env.value(node, "items")?.arrayValue ?? []).prefix(Int(node.number("limit") ?? 12)))
        let columns = node.props["columns"]?.arrayValue ?? TableNode.inferColumns(rows)
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    Text(column["title"]?.stringValue ?? column["path"]?.stringValue ?? "")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(TemplateRenderer.evaluate(column["path"]?.stringValue ?? "", context: row, now: env.now).displayString)
                            .font(.system(size: 11)).lineLimit(1)
                    }
                }
            }
            if rows.isEmpty {
                Text("No rows").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func inferColumns(_ rows: [JSONValue]) -> [JSONValue] {
        guard let first = rows.first?.objectValue else { return [] }
        return first.keys.sorted().prefix(4).map { ["title": .string($0.capitalized), "path": .string($0)] }
    }
}

struct CalendarNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        if let entry = env.entryDate {
            MonthGrid(date: entry, tint: env.tint)
        } else {
            TimelineView(.everyMinute) { MonthGrid(date: $0.date, tint: env.tint) }
        }
    }
}

struct MonthGrid: View {
    let date: Date
    let tint: Color

    var body: some View {
        let calendar = Calendar.current
        let days = MonthGrid.cells(for: date, calendar: calendar)
        let today = calendar.component(.day, from: date)
        VStack(spacing: 4) {
            Text(MonthGrid.title(date)).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(Array(MonthGrid.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    Text(day.map { String($0) } ?? "")
                        .font(.system(size: 11, weight: day == today ? .bold : .regular, design: .rounded))
                        .foregroundStyle(day == today ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .background(Circle().fill(day == today ? tint : Color.clear).frame(width: 20, height: 20))
                }
            }
        }
    }

    static func title(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Day numbers for the month containing `date`, padded with nil so the 1st lands on the right weekday.
    static func cells(for date: Date, calendar: Calendar) -> [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { return [] }
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let padding = [Int?](repeating: nil, count: offset)
        let numbers: [Int?] = range.map { $0 }
        return padding + numbers
    }
}
