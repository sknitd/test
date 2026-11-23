import Foundation

/// When a profile should activate by itself.
struct ProfileRule: Codable, Hashable, Identifiable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        /// Minutes since midnight; `end < start` wraps past midnight. Weekdays use Calendar numbering (1 = Sunday).
        case time(startMinute: Int, endMinute: Int, weekdays: Set<Int>)
        case activeApp(bundleIDs: [String])
        /// Matches when a display with this id (or, if empty, any external display) is connected.
        case display(id: String)
    }
    var id: String = UUID().uuidString
    var kind: Kind

    var summary: String {
        switch kind {
        case .time(let start, let end, let weekdays):
            let days = weekdays.count == 7 || weekdays.isEmpty ? "every day" : weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[($0 - 1 + 7) % 7] }.joined(separator: " ")
            return String(format: "%02d:%02d–%02d:%02d, ", start / 60, start % 60, end / 60, end % 60) + days
        case .activeApp(let ids): return "While " + (ids.isEmpty ? "(no apps chosen)" : ids.joined(separator: ", ")) + " is frontmost"
        case .display(let id): return id.isEmpty ? "When an external display is connected" : "When display \(id.prefix(8)) is connected"
        }
    }
}

/// A named set of widgets with their own arrangement: Work, Development, Personal, Focus…
struct Profile: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var symbol: String = "square.grid.2x2"
    /// Widgets that are visible in this profile.
    var widgetIDs: Set<String> = []
    /// Per-profile arrangement, captured when leaving the profile and re-applied when returning.
    var placements: [String: Placement] = [:]
    var rules: [ProfileRule] = []
    /// Higher wins when several profiles' rules match at once.
    var priority = 0
}

/// The facts automatic switching depends on, gathered by the app and injectable in tests.
struct ProfileContext: Sendable {
    var date: Date
    var frontmostBundleID: String?
    var displays: [DisplayInfo]
    var calendar = Calendar.current

    init(date: Date, frontmostBundleID: String? = nil, displays: [DisplayInfo] = [], calendar: Calendar = .current) {
        self.date = date; self.frontmostBundleID = frontmostBundleID; self.displays = displays; self.calendar = calendar
    }
}

struct ProfileState: Codable, Equatable, Sendable {
    var activeID: String?
    /// The profile the user chose by hand. Automatic switches return here when their rule stops matching.
    var manualID: String?
    var automaticSwitching = true
}

/// Profile bookkeeping and the pure rule evaluation behind automatic switching.
///
/// Per-Space profiles are deliberately absent: macOS has no public API for identifying Spaces, so the
/// supported contexts are time, frontmost app and connected displays.
final class ProfileManager {
    private(set) var profiles: [Profile] = []
    private(set) var state = ProfileState()
    private let db: DocumentStore
    private weak var store: WidgetStore?
    var onSwitch: ((Profile?, _ automatic: Bool) -> Void)?

    init(db: DocumentStore, store: WidgetStore) {
        self.db = db; self.store = store
    }

    var active: Profile? { profiles.first { $0.id == state.activeID } }

    func load() {
        profiles = ((try? db.loadAll(Profile.self, from: Collections.profiles)) ?? []).sorted { $0.name < $1.name }
        state = (try? db.load(ProfileState.self, from: Collections.settings, id: "profileState")) ?? ProfileState()
        if let id = state.activeID, !profiles.contains(where: { $0.id == id }) { state.activeID = nil }
    }

    private func saveState() { try? db.save(state, in: Collections.settings, id: "profileState") }

    @discardableResult
    func upsert(_ profile: Profile) -> Profile {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile } else { profiles.append(profile) }
        try? db.save(profile, in: Collections.profiles, id: profile.id)
        return profile
    }

    func delete(_ id: String) {
        profiles.removeAll { $0.id == id }
        try? db.delete(Collections.profiles, id: id)
        if state.activeID == id { state.activeID = nil }
        if state.manualID == id { state.manualID = nil }
        saveState()
    }

    func setAutomaticSwitching(_ enabled: Bool) {
        state.automaticSwitching = enabled
        saveState()
    }

    /// Record the current arrangement into the active profile so it can be restored later.
    func captureActiveLayout() {
        guard let store, let id = state.activeID, var profile = profiles.first(where: { $0.id == id }) else { return }
        for widget in store.widgets where profile.widgetIDs.contains(widget.id) {
            profile.placements[widget.id] = widget.placement
        }
        profile.widgetIDs = profile.widgetIDs.filter { wid in store.widgets.contains { $0.id == wid } }
        upsert(profile)
    }

    /// Activate a profile: its widgets are shown where it last had them, every other widget is hidden.
    /// Passing nil leaves profile mode ("All Widgets") and shows everything.
    func activate(_ id: String?, manual: Bool = true) {
        guard id != state.activeID || manual else { return }
        captureActiveLayout()
        state.activeID = id.flatMap { wanted in profiles.contains { $0.id == wanted } ? wanted : nil }
        if manual { state.manualID = state.activeID }
        saveState()
        apply()
        onSwitch?(active, !manual)
    }

    /// Re-apply the active profile to the store (also used after launch for automatic restoration).
    func apply() {
        guard let store else { return }
        guard let profile = active else {
            for widget in store.widgets where widget.hidden { store.update(widget.id) { $0.hidden = false } }
            return
        }
        for widget in store.widgets {
            let member = profile.widgetIDs.contains(widget.id)
            store.update(widget.id) {
                $0.hidden = !member
                if member, let placement = profile.placements[widget.id] { $0.placement = placement }
            }
        }
    }

    func setMembership(_ widgetID: String, in profileID: String, member: Bool) {
        guard var profile = profiles.first(where: { $0.id == profileID }) else { return }
        if member { profile.widgetIDs.insert(widgetID) } else { profile.widgetIDs.remove(widgetID); profile.placements[widgetID] = nil }
        upsert(profile)
        if profileID == state.activeID { store?.update(widgetID) { $0.hidden = !member } }
    }

    // MARK: Automatic switching

    /// Evaluate rules and switch if needed. Returns true when a switch happened.
    @discardableResult
    func evaluate(_ context: ProfileContext) -> Bool {
        guard state.automaticSwitching else { return false }
        let target = ProfileManager.resolve(profiles: profiles, manualID: state.manualID, context: context)
        guard target != state.activeID else { return false }
        activate(target, manual: false)
        return true
    }

    /// The profile that should be active: the highest-priority profile with a matching rule, otherwise the
    /// user's manual choice (this is what makes automatic profiles "restore" when their context ends).
    static func resolve(profiles: [Profile], manualID: String?, context: ProfileContext) -> String? {
        let matching = profiles.filter { profile in profile.rules.contains { matches($0, context) } }
        if let best = matching.max(by: { ($0.priority, $1.name) < ($1.priority, $0.name) }) { return best.id }
        return manualID
    }

    static func matches(_ rule: ProfileRule, _ context: ProfileContext) -> Bool {
        switch rule.kind {
        case .time(let start, let end, let weekdays):
            let parts = context.calendar.dateComponents([.hour, .minute, .weekday], from: context.date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let weekday = parts.weekday ?? 1
            if start <= end {
                return minute >= start && minute < end && (weekdays.isEmpty || weekdays.contains(weekday))
            }
            // Overnight window: after `start` belongs to today, before `end` belongs to yesterday's window.
            if minute >= start { return weekdays.isEmpty || weekdays.contains(weekday) }
            if minute < end { return weekdays.isEmpty || weekdays.contains((weekday + 5) % 7 + 1) }
            return false
        case .activeApp(let ids):
            guard let front = context.frontmostBundleID else { return false }
            return ids.contains { $0.caseInsensitiveCompare(front) == .orderedSame }
        case .display(let id):
            if id.isEmpty { return context.displays.contains { !$0.isMain } }
            return context.displays.contains { $0.id == id }
        }
    }
}
