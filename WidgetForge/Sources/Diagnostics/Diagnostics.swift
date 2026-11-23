import Foundation

struct LogEntry: Identifiable, Hashable, Sendable {
    enum Level: String, CaseIterable, Sendable { case debug, info, warning, error }
    enum Category: String, CaseIterable, Sendable { case app, widget, script, network, automation, layout, security, performance }

    var id = UUID()
    var date: Date
    var level: Level
    var category: Category
    var message: String
    var widgetID: String?
}

/// Rolling statistics for one measured quantity (script run time, widget update latency…).
struct TimingStats: Equatable, Sendable {
    private(set) var count = 0
    private(set) var total = 0.0
    private(set) var max = 0.0
    private(set) var last = 0.0
    private var recent: [Double] = []

    mutating func record(_ seconds: Double) {
        count += 1; total += seconds; last = seconds
        if seconds > max { max = seconds }
        recent.append(seconds)
        if recent.count > 200 { recent.removeFirst(recent.count - 200) }
    }

    var average: Double { count > 0 ? total / Double(count) : 0 }

    /// 95th percentile over the most recent 200 measurements.
    var p95: Double {
        guard !recent.isEmpty else { return 0 }
        let sorted = recent.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
    }
}

/// Thread-safe log and measurement sink. Everything shown in the Diagnostics section comes from here;
/// figures are measured at runtime, never estimated.
final class DiagnosticsCenter: @unchecked Sendable {
    static let capacity = 1000

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private var timings: [String: TimingStats] = [:]
    private var counters: [String: Int] = [:]
    /// Called (on the logging thread) whenever something changes; the UI coalesces these.
    var onChange: (@Sendable () -> Void)?

    init() {}

    func log(_ level: LogEntry.Level, _ category: LogEntry.Category, _ message: String, widgetID: String? = nil, date: Date = Date()) {
        lock.lock()
        entries.append(LogEntry(date: date, level: level, category: category, message: String(message.prefix(2000)), widgetID: widgetID))
        if entries.count > DiagnosticsCenter.capacity { entries.removeFirst(entries.count - DiagnosticsCenter.capacity) }
        lock.unlock()
        onChange?()
    }

    func recordTiming(_ name: String, seconds: Double) {
        lock.lock()
        timings[name, default: TimingStats()].record(seconds)
        lock.unlock()
    }

    func increment(_ name: String, by amount: Int = 1) {
        lock.lock()
        counters[name, default: 0] += amount
        lock.unlock()
    }

    @discardableResult
    func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { recordTiming(name, seconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9) }
        return try body()
    }

    func snapshot(widgetID: String? = nil, minimumLevel: LogEntry.Level = .debug, category: LogEntry.Category? = nil) -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        let order = LogEntry.Level.allCases
        let floor = order.firstIndex(of: minimumLevel) ?? 0
        return entries.filter { entry in
            (widgetID == nil || entry.widgetID == widgetID) && (category == nil || entry.category == category)
                && (order.firstIndex(of: entry.level) ?? 0) >= floor
        }
    }

    func timing(_ name: String) -> TimingStats { lock.lock(); defer { lock.unlock() }; return timings[name] ?? TimingStats() }
    func allTimings() -> [String: TimingStats] { lock.lock(); defer { lock.unlock() }; return timings }
    func counter(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counters[name] ?? 0 }
    func allCounters() -> [String: Int] { lock.lock(); defer { lock.unlock() }; return counters }

    func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
        onChange?()
    }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return snapshot().map { "\(formatter.string(from: $0.date)) [\($0.level.rawValue)] [\($0.category.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}

/// Subsequence fuzzy matching for the Command Center: every query character must appear in order.
/// Consecutive matches, word starts and early matches score higher.
enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        var score = 0, qi = 0, previousMatch = -2
        for (i, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var gain = 10
            if i == previousMatch + 1 { gain += 15 }
            if i == 0 || !(c[i - 1].isLetter || c[i - 1].isNumber) { gain += 20 }
            gain -= min(i, 9)
            score += gain
            previousMatch = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        if c.count == q.count { score += 30 }
        return score - min(c.count / 4, 10)
    }

    /// Items matching the query, best first. An empty query returns everything in the original order.
    static func filter<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in score(query: query, candidate: key(item)).map { (item, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}
