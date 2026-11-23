import Foundation

enum AutomationTrigger: Codable, Hashable, Sendable {
    case timer(seconds: Double)
    case appLaunch(bundleID: String)
    case appActivate(bundleID: String)
    case networkChange
    case batteryBelow(percent: Double)
    case widgetInteraction(name: String)
    case dataCondition(widgetID: String, condition: Condition)
    case manual

    var title: String {
        switch self {
        case .timer(let s): return "Every \(Formatters.duration(s))"
        case .appLaunch(let id): return "When \(id.isEmpty ? "an app" : id) launches"
        case .appActivate(let id): return "When \(id.isEmpty ? "an app" : id) becomes active"
        case .networkChange: return "When the network changes"
        case .batteryBelow(let p): return "When battery falls below \(Int(p))%"
        case .widgetInteraction(let name): return "When a widget sends \"\(name)\""
        case .dataCondition(_, let c): return "When \(c.summary)"
        case .manual: return "Manually"
        }
    }

    var kind: String {
        switch self {
        case .timer: return "timer"
        case .appLaunch: return "appLaunch"
        case .appActivate: return "appActivate"
        case .networkChange: return "networkChange"
        case .batteryBelow: return "batteryBelow"
        case .widgetInteraction: return "widgetInteraction"
        case .dataCondition: return "dataCondition"
        case .manual: return "manual"
        }
    }

    static let kinds = ["manual", "timer", "appLaunch", "appActivate", "networkChange", "batteryBelow", "widgetInteraction", "dataCondition"]

    static func make(kind: String) -> AutomationTrigger {
        switch kind {
        case "timer": return .timer(seconds: 300)
        case "appLaunch": return .appLaunch(bundleID: "")
        case "appActivate": return .appActivate(bundleID: "")
        case "networkChange": return .networkChange
        case "batteryBelow": return .batteryBelow(percent: 20)
        case "widgetInteraction": return .widgetInteraction(name: "pressed")
        case "dataCondition": return .dataCondition(widgetID: "", condition: Condition("value", .greaterThan, 0))
        default: return .manual
        }
    }
}

enum AutomationAction: Codable, Hashable, Sendable {
    case showWidget(id: String)
    case hideWidget(id: String)
    case switchProfile(id: String)
    case refreshData(widgetID: String)
    case notify(title: String, body: String)
    case openURL(String)
    case launchApp(bundleID: String)
    case runShortcut(name: String)
    case setWidgetState(widgetID: String, key: String, value: JSONValue)
    case wait(seconds: Double)

    var title: String {
        switch self {
        case .showWidget: return "Show widget"
        case .hideWidget: return "Hide widget"
        case .switchProfile: return "Switch profile"
        case .refreshData: return "Update data"
        case .notify(let title, _): return "Notify \"\(title)\""
        case .openURL(let url): return "Open \(url)"
        case .launchApp(let id): return "Launch \(id)"
        case .runShortcut(let name): return "Run shortcut \"\(name)\""
        case .setWidgetState(_, let key, let value): return "Set \(key) = \(value.displayString)"
        case .wait(let s): return "Wait \(Formatters.duration(s))"
        }
    }

    var kind: String {
        switch self {
        case .showWidget: return "showWidget"
        case .hideWidget: return "hideWidget"
        case .switchProfile: return "switchProfile"
        case .refreshData: return "refreshData"
        case .notify: return "notify"
        case .openURL: return "openURL"
        case .launchApp: return "launchApp"
        case .runShortcut: return "runShortcut"
        case .setWidgetState: return "setWidgetState"
        case .wait: return "wait"
        }
    }

    static let kinds = ["showWidget", "hideWidget", "switchProfile", "refreshData", "notify", "openURL", "launchApp", "runShortcut", "setWidgetState", "wait"]

    static func make(kind: String) -> AutomationAction {
        switch kind {
        case "hideWidget": return .hideWidget(id: "")
        case "switchProfile": return .switchProfile(id: "")
        case "refreshData": return .refreshData(widgetID: "")
        case "notify": return .notify(title: "WidgetForge", body: "")
        case "openURL": return .openURL("https://")
        case "launchApp": return .launchApp(bundleID: "")
        case "runShortcut": return .runShortcut(name: "")
        case "setWidgetState": return .setWidgetState(widgetID: "", key: "highlight", value: true)
        case "wait": return .wait(seconds: 5)
        default: return .showWidget(id: "")
        }
    }
}

struct AutomationRule: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var enabled = true
    var trigger: AutomationTrigger
    /// All conditions must hold (evaluated against the event context: `battery.level`, `app.bundleID`, …).
    var conditions: [Condition] = []
    var actions: [AutomationAction]
    /// Minimum seconds between two runs of this rule.
    var cooldown: Double = 60
    var lastRun: Date?
    var runCount = 0
}

/// Something that happened in the system. `depth` counts how many automations led to this event and is
/// what stops A → B → A loops.
struct AutomationEvent: Sendable {
    enum Kind: Hashable, Sendable {
        case timerTick
        case appLaunched(String)
        case appActivated(String)
        case networkChanged
        case battery(percent: Double, onBattery: Bool)
        case widgetInteraction(widgetID: String, name: String)
        case dataUpdated(widgetID: String)
        case manual(ruleID: String)
    }
    var kind: Kind
    /// Extra values that conditions can test.
    var context: JSONValue = .object([:])
    var depth = 0
    var date = Date()
}

/// Side effects are performed by the host app; tests substitute a recorder.
protocol AutomationActionPerformer: AnyObject {
    /// Performs one action. Returns follow-up events the action caused (e.g. a widget becoming visible).
    func perform(_ action: AutomationAction, rule: AutomationRule) async throws -> [AutomationEvent]
}

struct AutomationRunRecord: Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case completed, cancelled, failed(String)
        case skipped(String)
    }
    var id = UUID()
    var ruleID: String
    var ruleName: String
    var date: Date
    var outcome: Outcome
    var actionsRun: Int
}

/// Evaluates triggers and runs workflows.
///
/// Safety properties:
/// - **Edge triggering**: threshold triggers (battery, data conditions) fire when the condition *becomes*
///   true, not on every sample while it stays true.
/// - **Cooldown**: a rule cannot run again within its cooldown window.
/// - **Deduplication**: a rule that is already running is not started a second time.
/// - **Loop guard**: events caused by automations carry a depth; beyond `maxDepth` they are dropped, and a
///   rule never re-enters itself through its own follow-up events.
actor AutomationEngine {
    private(set) var rules: [AutomationRule]
    private weak var performer: AutomationActionPerformer?
    private let sleeper: @Sendable (Double) async throws -> Void
    private let now: @Sendable () -> Date
    private let persist: @Sendable ([AutomationRule]) -> Void
    private let log: @Sendable (AutomationRunRecord) -> Void

    private var running: [String: Task<Void, Never>] = [:]
    private var edgeState: [String: Bool] = [:]          // rule id -> was the threshold condition true last time
    private var lastTimerFire: [String: Date] = [:]
    private(set) var history: [AutomationRunRecord] = []
    private(set) var isPaused = false

    static let maxDepth = 3
    static let historyLimit = 200

    init(rules: [AutomationRule] = [], performer: AutomationActionPerformer?,
         sleeper: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) },
         now: @escaping @Sendable () -> Date = { Date() },
         persist: @escaping @Sendable ([AutomationRule]) -> Void = { _ in },
         log: @escaping @Sendable (AutomationRunRecord) -> Void = { _ in }) {
        self.rules = rules; self.performer = performer; self.sleeper = sleeper; self.now = now
        self.persist = persist; self.log = log
    }

    func setPerformer(_ performer: AutomationActionPerformer?) { self.performer = performer }
    func setPaused(_ paused: Bool) { isPaused = paused }

    // MARK: Rule management

    func setRules(_ newRules: [AutomationRule]) {
        rules = newRules
        let ids = Set(newRules.map(\.id))
        edgeState = edgeState.filter { ids.contains($0.key) }
        for (id, task) in running where !ids.contains(id) { task.cancel() }
        persist(rules)
    }

    func upsert(_ rule: AutomationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
        edgeState[rule.id] = nil
        if !rule.enabled { running[rule.id]?.cancel() }
        persist(rules)
    }

    func remove(_ id: String) {
        rules.removeAll { $0.id == id }
        running[id]?.cancel()
        edgeState[id] = nil
        persist(rules)
    }

    /// Smallest timer interval among enabled rules; the host uses it to schedule `timerTick` events.
    var shortestTimerInterval: Double? {
        rules.compactMap { rule -> Double? in
            if rule.enabled, case .timer(let s) = rule.trigger { return max(10, s) }
            return nil
        }.min()
    }

    // MARK: Event handling

    /// Feed an event in. Returns the ids of the rules that were started.
    @discardableResult
    func handle(_ event: AutomationEvent, origin: String? = nil) -> [String] {
        guard !isPaused || isManual(event) else { return [] }
        guard event.depth <= AutomationEngine.maxDepth else {
            record(AutomationRunRecord(ruleID: origin ?? "", ruleName: "Loop guard", date: now(),
                                       outcome: .skipped("event chain deeper than \(AutomationEngine.maxDepth)"), actionsRun: 0))
            return []
        }
        var started: [String] = []
        for rule in rules where rule.enabled {
            guard matches(rule, event) else { continue }
            if rule.id == origin {
                record(AutomationRunRecord(ruleID: rule.id, ruleName: rule.name, date: now(), outcome: .skipped("would re-trigger itself"), actionsRun: 0))
                continue
            }
            guard rule.conditions.allSatisfy({ $0.evaluate(in: event.context) }) else { continue }
            if running[rule.id] != nil {
                record(AutomationRunRecord(ruleID: rule.id, ruleName: rule.name, date: now(), outcome: .skipped("already running"), actionsRun: 0))
                continue
            }
            if !isManual(event), let last = rule.lastRun, now().timeIntervalSince(last) < rule.cooldown {
                record(AutomationRunRecord(ruleID: rule.id, ruleName: rule.name, date: now(), outcome: .skipped("cooling down"), actionsRun: 0))
                continue
            }
            start(rule, depth: event.depth)
            started.append(rule.id)
        }
        return started
    }

    private func isManual(_ event: AutomationEvent) -> Bool {
        if case .manual = event.kind { return true }
        return false
    }

    /// Does this event satisfy the rule's trigger? Threshold triggers update their edge state here.
    private func matches(_ rule: AutomationRule, _ event: AutomationEvent) -> Bool {
        switch (rule.trigger, event.kind) {
        case (_, .manual(let id)):
            return id == rule.id
        case (.timer(let seconds), .timerTick):
            let interval = max(10, seconds)
            let last = lastTimerFire[rule.id] ?? rule.lastRun
            guard let last else { lastTimerFire[rule.id] = event.date; return false }   // first tick arms the timer
            guard event.date.timeIntervalSince(last) >= interval else { return false }
            lastTimerFire[rule.id] = event.date
            return true
        case (.appLaunch(let wanted), .appLaunched(let id)), (.appActivate(let wanted), .appActivated(let id)):
            return wanted.isEmpty || wanted.caseInsensitiveCompare(id) == .orderedSame
        case (.networkChange, .networkChanged):
            return true
        case (.batteryBelow(let threshold), .battery(let percent, let onBattery)):
            return risingEdge(rule.id, isTrue: onBattery && percent < threshold)
        case (.widgetInteraction(let wanted), .widgetInteraction(_, let name)):
            return wanted == name
        case (.dataCondition(let wantedWidget, let condition), .dataUpdated(let widgetID)):
            guard wantedWidget.isEmpty || wantedWidget == widgetID else { return false }
            return risingEdge(rule.id, isTrue: condition.evaluate(in: event.context))
        default:
            return false
        }
    }

    private func risingEdge(_ ruleID: String, isTrue: Bool) -> Bool {
        let was = edgeState[ruleID] ?? false
        edgeState[ruleID] = isTrue
        return isTrue && !was
    }

    private func start(_ rule: AutomationRule, depth: Int) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].lastRun = now()
            rules[index].runCount += 1
            persist(rules)
        }
        running[rule.id] = Task { [weak self] in
            await self?.execute(rule, depth: depth)
        }
    }

    private func execute(_ rule: AutomationRule, depth: Int) async {
        var done = 0
        var outcome = AutomationRunRecord.Outcome.completed
        var followUps: [AutomationEvent] = []
        for action in rule.actions {
            if Task.isCancelled { outcome = .cancelled; break }
            do {
                if case .wait(let seconds) = action {
                    try await sleeper(min(max(0, seconds), 3600))
                } else if let performer {
                    followUps += try await performer.perform(action, rule: rule)
                } else {
                    throw DataSourceError.unsupported("No action performer")
                }
                done += 1
            } catch is CancellationError {
                outcome = .cancelled
                break
            } catch {
                outcome = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
                break
            }
        }
        running[rule.id] = nil
        record(AutomationRunRecord(ruleID: rule.id, ruleName: rule.name, date: now(), outcome: outcome, actionsRun: done))
        guard outcome == .completed else { return }
        for var event in followUps {
            event.depth = depth + 1
            handle(event, origin: rule.id)
        }
    }

    private func record(_ entry: AutomationRunRecord) {
        history.append(entry)
        if history.count > AutomationEngine.historyLimit { history.removeFirst(history.count - AutomationEngine.historyLimit) }
        log(entry)
    }

    // MARK: Control

    @discardableResult
    func runManually(_ ruleID: String) -> Bool {
        !handle(AutomationEvent(kind: .manual(ruleID: ruleID), date: now())).isEmpty
    }

    func cancel(_ ruleID: String) { running[ruleID]?.cancel() }
    func cancelAll() { running.values.forEach { $0.cancel() } }
    func isRunning(_ ruleID: String) -> Bool { running[ruleID] != nil }

    /// Waits until no workflow is running (used by tests and by app termination).
    func waitUntilIdle() async {
        while let task = running.values.first { await task.value }
    }
}
