import Foundation

/// Builds the JSON context that `{{placeholders}}` resolve against. Shared by the live runtime and the
/// WidgetKit extension so both render identically.
enum WidgetContextBuilder {
    static func context(state: [String: JSONValue], settings: [String: JSONValue], data: [String: JSONValue],
                        statuses: [String: JSONValue]) -> JSONValue {
        var root = data
        root["state"] = .object(state)
        root["settings"] = .object(settings)
        root["sources"] = .object(statuses)
        return .object(root)
    }

    /// Data sources a definition needs, including the implicit ones behind `metric` components.
    static func effectiveSources(for definition: WidgetDefinition) -> [DataSourceConfig] {
        var sources = definition.dataSources
        var ids = Set(sources.map(\.id))
        for node in definition.root.flattened where node.type == .metric {
            let name = node.string("metric") ?? "cpu"
            if ids.insert(name).inserted { sources.append(.metric(name)) }
        }
        return sources
    }
}

/// What the app publishes for the WidgetKit extension: everything needed to draw a widget without the app
/// running. It contains definitions, user state and the last data values, never secrets.
struct SnapshotWidget: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var definition: WidgetDefinition
    var state: [String: JSONValue]
    var allowsSystemMetrics: Bool
    /// Last values of non-metric data sources (metrics are sampled by the extension itself at timeline time).
    var data: [String: JSONValue]
    var statuses: [String: JSONValue]
    var scriptNode: WidgetNode?
}

struct SharedSnapshot: Codable, Sendable {
    var widgets: [SnapshotWidget] = []
    var updatedAt = Date()
}

/// A state change requested from a WidgetKit App Intent, waiting to be applied by the app.
struct PendingStateChange: Codable, Sendable {
    var widgetID: String
    var key: String
    var value: JSONValue
    var date = Date()
}

/// File-based hand-off between the app and its widget extension through the shared App Group container.
enum SharedContainer {
    static let changeNotification = "com.widgetforge.app.widgetStateChanged"
    static let widgetKind = "com.widgetforge.app.widget"

    /// The group identifier is read from Info.plist (`WFAppGroup`) because on macOS it embeds the signing team.
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "WFAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "com.widgetforge.shared"
    }

    static func directory() -> URL? {
        #if canImport(Darwin)
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
        #else
        return nil
        #endif
    }

    static func readSnapshot(in directory: URL? = SharedContainer.directory()) -> SharedSnapshot? {
        guard let url = directory?.appendingPathComponent("snapshot.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }

    @discardableResult
    static func writeSnapshot(_ snapshot: SharedSnapshot, in directory: URL? = SharedContainer.directory()) -> Bool {
        guard let url = directory?.appendingPathComponent("snapshot.json"), let data = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func appendPending(_ change: PendingStateChange, in directory: URL? = SharedContainer.directory()) {
        guard let url = directory?.appendingPathComponent("pending.json") else { return }
        var all = (try? JSONDecoder().decode([PendingStateChange].self, from: Data(contentsOf: url))) ?? []
        all.append(change)
        if let data = try? JSONEncoder().encode(Array(all.suffix(200))) { try? data.write(to: url, options: .atomic) }
    }

    /// Returns and clears the queued changes.
    static func drainPending(in directory: URL? = SharedContainer.directory()) -> [PendingStateChange] {
        guard let url = directory?.appendingPathComponent("pending.json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([PendingStateChange].self, from: data) else { return [] }
        try? FileManager.default.removeItem(at: url)
        return all
    }

    /// Apply an intent's state change to the snapshot so the widget redraws correctly even if the app is not running.
    static func apply(_ change: PendingStateChange, in directory: URL? = SharedContainer.directory()) {
        guard var snapshot = readSnapshot(in: directory), let index = snapshot.widgets.firstIndex(where: { $0.id == change.widgetID }) else { return }
        snapshot.widgets[index].state[change.key] = change.value
        snapshot.updatedAt = Date()
        writeSnapshot(snapshot, in: directory)
    }

    /// The new value for a state-changing action, or nil if the action does not change state.
    static func stateChange(for action: WidgetAction, current: [String: JSONValue]) -> (key: String, value: JSONValue)? {
        switch action {
        case .setState(let key, let value): return (key, value)
        case .toggleState(let key): return (key, .bool(!(current[key]?.boolValue ?? false)))
        case .incrementState(let key, let by): return (key, .number((current[key]?.doubleValue ?? 0) + by))
        default: return nil
        }
    }
}
