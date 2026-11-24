import WidgetKit
import SwiftUI
import AppIntents

// The native WidgetKit backend.
//
// These are real macOS desktop / Notification Centre widgets, so they follow WidgetKit's rules: the system
// decides when the timeline is reloaded, views are archived snapshots rather than running code, and the only
// interactivity is App Intent buttons and toggles. Nothing here runs JavaScript or polls in the background;
// scripted and real-time widgets belong to the overlay backend in the main app.

@main
struct WidgetForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidgetForgeWidget()
    }
}

struct WidgetForgeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedContainer.widgetKind, intent: SelectWidgetIntent.self, provider: WidgetForgeProvider()) { entry in
            WidgetForgeEntryView(entry: entry)
        }
        .configurationDisplayName("WidgetForge")
        .description("Show one of your WidgetForge widgets. Edit the widget to choose which.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: Configuration

struct WidgetEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Widget"
    static var defaultQuery = WidgetEntityQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetEntityQuery: EntityQuery {
    private func all() -> [WidgetEntity] {
        (SharedContainer.readSnapshot()?.widgets ?? []).map { WidgetEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [WidgetEntity] { all() }
    func defaultResult() async -> WidgetEntity? { all().first }
}

struct SelectWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Widget"
    static var description = IntentDescription("Pick which WidgetForge widget to show.")

    @Parameter(title: "Widget")
    var widget: WidgetEntity?
}

// MARK: Interactivity

/// Changes one value in a widget's state (tick a to-do, start a timer, flip a toggle). The change is applied to
/// the shared snapshot immediately and queued for the app, which owns the real store.
struct ApplyStateIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Widget"
    static var isDiscoverable = false

    @Parameter(title: "Widget ID") var widgetID: String
    @Parameter(title: "Key") var key: String
    @Parameter(title: "Value") var valueJSON: String

    init() {}

    init(widgetID: String, key: String, value: JSONValue) {
        self.widgetID = widgetID
        self.key = key
        self.valueJSON = value.compactJSONString
    }

    func perform() async throws -> some IntentResult {
        let value = (try? JSONValue.parse(valueJSON)) ?? .null
        let change = PendingStateChange(widgetID: widgetID, key: key, value: value)
        SharedContainer.apply(change)
        SharedContainer.appendPending(change)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(SharedContainer.changeNotification), object: nil, userInfo: nil, deliverImmediately: true)
        return .result()
    }
}

/// Asks WidgetKit for a fresh timeline (it reloads after any intent completes).
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult { .result() }
}

// MARK: Timeline

struct WidgetForgeEntry: TimelineEntry {
    let date: Date
    let widget: SnapshotWidget?
    let metrics: [String: JSONValue]
    let sampledAt: Date?
    var message: String?
}

struct WidgetForgeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetForgeEntry {
        WidgetForgeEntry(date: Date(), widget: nil, metrics: [:], sampledAt: nil, message: "WidgetForge")
    }

    func snapshot(for configuration: SelectWidgetIntent, in context: Context) async -> WidgetForgeEntry {
        await entries(for: configuration, sampleMetrics: !context.isPreview).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectWidgetIntent, in context: Context) async -> Timeline<WidgetForgeEntry> {
        let entries = await entries(for: configuration, sampleMetrics: true)
        let usesMetrics = !(entries.first?.metrics.isEmpty ?? true)
        // WidgetKit treats this as a request, not a promise; it budgets reloads per widget per day.
        let next = Date().addingTimeInterval(usesMetrics ? 5 * 60 : 15 * 60)
        return Timeline(entries: entries, policy: .after(next))
    }

    private func entries(for configuration: SelectWidgetIntent, sampleMetrics: Bool) async -> [WidgetForgeEntry] {
        guard let snapshot = SharedContainer.readSnapshot() else {
            return [WidgetForgeEntry(date: Date(), widget: nil, metrics: [:], sampledAt: nil, message: "Open WidgetForge once to set up widgets.")]
        }
        guard let widget = snapshot.widgets.first(where: { $0.id == configuration.widget?.id }) ?? snapshot.widgets.first else {
            return [WidgetForgeEntry(date: Date(), widget: nil, metrics: [:], sampledAt: nil, message: "No widgets yet. Add one in WidgetForge.")]
        }
        var metrics: [String: JSONValue] = [:]
        var sampledAt: Date?
        let metricSources = WidgetContextBuilder.effectiveSources(for: widget.definition).filter { $0.kind == .systemMetric }
        if sampleMetrics, widget.allowsSystemMetrics, !metricSources.isEmpty {
            // Rates need two readings; take them a moment apart. These are real values as of this reload.
            let collector = SystemMetricsCollector()
            collector.sample()
            try? await Task.sleep(nanoseconds: 400_000_000)
            let sample = collector.sample()
            for source in metricSources { metrics[source.id] = sample[source.metric ?? source.id] }
            sampledAt = Date()
        }
        let now = Date()
        let timeDriven = widget.definition.root.flattened.contains { [.clock, .date, .countdown, .pomodoro, .calendar].contains($0.type) }
        guard timeDriven else { return [WidgetForgeEntry(date: now, widget: widget, metrics: metrics, sampledAt: sampledAt)] }
        // Clocks advance through pre-computed entries, one per minute, aligned to the minute boundary.
        let calendar = Calendar.current
        let firstMinute = calendar.date(bySetting: .second, value: 0, of: now).flatMap { calendar.date(byAdding: .minute, value: 1, to: $0) } ?? now.addingTimeInterval(60)
        var entries = [WidgetForgeEntry(date: now, widget: widget, metrics: metrics, sampledAt: sampledAt)]
        for minute in 0..<30 {
            entries.append(WidgetForgeEntry(date: firstMinute.addingTimeInterval(Double(minute) * 60), widget: widget, metrics: metrics, sampledAt: sampledAt))
        }
        return entries
    }
}

// MARK: View

struct WidgetForgeEntryView: View {
    let entry: WidgetForgeEntry

    var body: some View {
        Group {
            if let widget = entry.widget {
                GeometryReader { proxy in
                    let definition = widget.definition
                    let scale = min(proxy.size.width / CGFloat(definition.size.width), proxy.size.height / CGFloat(definition.size.height), 1.3)
                    WidgetContentView(definition: definition, env: environment(for: widget), drawsBackground: false)
                        .frame(width: CGFloat(definition.size.width), height: CGFloat(definition.size.height))
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let sampledAt = entry.sampledAt {
                        Text("as of \(sampledAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill").font(.title2).foregroundStyle(.tint)
                    Text(entry.message ?? "WidgetForge").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func environment(for widget: SnapshotWidget) -> RenderEnvironment {
        var data = widget.data
        for (key, value) in entry.metrics { data[key] = value }
        var env = RenderEnvironment()
        env.context = WidgetContextBuilder.context(state: widget.state, settings: widget.definition.settings, data: data, statuses: widget.statuses)
        env.isWidgetKit = true
        env.entryDate = entry.date
        env.scriptNode = widget.scriptNode
        let state = widget.state
        let id = widget.id
        env.intentButton = { action, label in
            if let change = SharedContainer.stateChange(for: action, current: state) {
                return AnyView(Button(intent: ApplyStateIntent(widgetID: id, key: change.key, value: change.value)) { label }.buttonStyle(.plain))
            }
            switch action {
            case .refresh: return AnyView(Button(intent: RefreshWidgetIntent()) { label }.buttonStyle(.plain))
            case .openURL(let text):
                if let url = URL(string: text), url.scheme == "https" { return AnyView(Link(destination: url) { label }) }
                return label
            default: return label
            }
        }
        return env
    }
}
