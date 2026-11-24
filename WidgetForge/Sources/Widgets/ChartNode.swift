import SwiftUI
import Charts

struct ChartPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

/// Swift Charts rendering for line, bar, area, pie/donut and sparkline charts with live data binding.
struct ChartNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    @State private var hovered: ChartPoint?

    var body: some View {
        let points = ChartNode.points(from: env.value(node, "values"), node: node)
        let kind = node.string("chartKind") ?? "line"
        let color = Theme.color(node.string("color"), tint: env.tint, fallback: env.tint)
        VStack(alignment: .leading, spacing: 2) {
            let title = env.text(node, "title")
            if !title.isEmpty { Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
            if points.isEmpty {
                Text("Waiting for data").font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if kind == "pie" || kind == "donut" {
                pie(points, donut: kind == "donut")
            } else {
                cartesian(points, kind: kind, color: color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, idealHeight: node.number("height").map { CGFloat($0) }, maxHeight: node.number("height").map { CGFloat($0) } ?? .infinity)
        .accessibilityLabel(Text(ChartNode.accessibilitySummary(points, title: env.text(node, "title"))))
    }

    // MARK: Data

    /// Accepts `[1, 2, 3]`, `[{label, value}]` or any array of objects with `xPath`/`yPath` props.
    static func points(from value: JSONValue?, node: WidgetNode) -> [ChartPoint] {
        guard let array = value?.arrayValue else { return [] }
        let yPath = node.string("yPath") ?? "value"
        let xPath = node.string("xPath") ?? "label"
        let limited = array.suffix(Int(node.number("maxPoints") ?? 240))
        return limited.enumerated().compactMap { index, item in
            if case .number(let d) = item { return d.isFinite ? ChartPoint(id: index, label: "\(index + 1)", value: d) : nil }
            guard let y = item.path(yPath)?.doubleValue, y.isFinite else { return nil }
            return ChartPoint(id: index, label: item.path(xPath)?.displayString ?? "\(index + 1)", value: y)
        }
    }

    static func accessibilitySummary(_ points: [ChartPoint], title: String) -> String {
        guard let last = points.last else { return title.isEmpty ? "Chart, no data" : "\(title), no data" }
        let low = points.map(\.value).min() ?? 0, high = points.map(\.value).max() ?? 0
        return "\(title.isEmpty ? "Chart" : title): latest \(JSONValue.format(last.value)), range \(JSONValue.format(low)) to \(JSONValue.format(high))"
    }

    /// CSV text for the "Export Data" command.
    static func csv(_ points: [ChartPoint]) -> String {
        (["label,value"] + points.map { "\"\($0.label.replacingOccurrences(of: "\"", with: "\"\""))\",\($0.value)" }).joined(separator: "\n")
    }

    // MARK: Cartesian charts

    @ViewBuilder
    private func cartesian(_ points: [ChartPoint], kind: String, color: Color) -> some View {
        let sparkline = kind == "sparkline"
        let showAxes = node.bool("showAxes") ?? false
        let threshold = env.number(node, "threshold")
        let chart = Chart {
            ForEach(points) { point in
                switch kind {
                case "bar":
                    // A categorical x axis lets Swift Charts size the bars to fill the plot.
                    BarMark(x: .value("Index", String(point.id)), y: .value("Value", point.value))
                        .foregroundStyle(threshold.map { point.value >= $0 ? Color.red : color } ?? color)
                        .cornerRadius(2)
                case "area":
                    AreaMark(x: .value("Index", point.id), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Index", point.id), y: .value("Value", point.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                default:
                    LineMark(x: .value("Index", point.id), y: .value("Value", point.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: sparkline ? 1.25 : 1.75))
                }
            }
            if let threshold {
                RuleMark(y: .value("Threshold", threshold))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let hovered, !env.isWidgetKit, kind != "bar" {
                RuleMark(x: .value("Index", hovered.id))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("\(hovered.label): \(JSONValue.format(hovered.value))")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .chartLegend(.hidden)

        let scaled = applyDomain(chart, points: points)
        if env.isWidgetKit || !env.isInteractive {
            scaled
        } else {
            // Tooltips: overlay mode only. WidgetKit views cannot track the pointer.
            scaled.chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let originX = proxy.plotFrame.map { geometry[$0].origin.x } ?? 0
                                if let index: Int = proxy.value(atX: location.x - originX) {
                                    hovered = points.min { abs($0.id - index) < abs($1.id - index) }
                                }
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func applyDomain<C: View>(_ chart: C, points: [ChartPoint]) -> some View {
        let values = points.map(\.value) + [env.number(node, "threshold")].compactMap { $0 }
        let low = env.number(node, "yMin") ?? min(0, values.min() ?? 0)
        let high = env.number(node, "yMax") ?? (values.max() ?? 1)
        chart.chartYScale(domain: low...(high > low ? high : low + 1))
    }

    // MARK: Pie / donut

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red, .indigo, .mint]

    @ViewBuilder
    private func pie(_ points: [ChartPoint], donut: Bool) -> some View {
        let slices = points.filter { $0.value > 0 }
        HStack(spacing: 8) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(donut ? 0.6 : 0), angularInset: 1)
                    .foregroundStyle(ChartNode.palette[slice.id % ChartNode.palette.count])
                    .cornerRadius(2)
            }
            .chartLegend(.hidden)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 4) {
                        Circle().fill(ChartNode.palette[slice.id % ChartNode.palette.count]).frame(width: 6, height: 6)
                        Text(slice.label).font(.system(size: 10)).lineLimit(1)
                        Text(JSONValue.format(slice.value, maxFractionDigits: 1)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
