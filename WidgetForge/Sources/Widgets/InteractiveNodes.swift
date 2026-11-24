import SwiftUI

// Interactive and stateful components. State lives in the widget instance (`state.*`) and is written through
// `env.setState`, so it persists across launches and is visible to templates and automations. In WidgetKit
// the same state changes are expressed as App Intent buttons, because nothing else is interactive there.

struct ButtonNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let title = env.text(node, "title")
        let symbol = node.string("symbol")
        let style = node.string("style") ?? "bordered"
        let color = Theme.color(node.string("color"), tint: env.tint, fallback: env.tint)
        env.button(WidgetAction(json: node.props["action"])) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                if !title.isEmpty { Text(title).lineLimit(1) }
            }
            .font(.system(size: CGFloat(node.number("fontSize") ?? 12), weight: .medium))
            .foregroundStyle(style == "prominent" ? Color.white : color)
            .padding(.horizontal, style == "plain" ? 2 : 10)
            .padding(.vertical, style == "plain" ? 2 : 5)
            .frame(maxWidth: style == "plain" ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(style == "prominent" ? color : (style == "plain" ? Color.clear : color.opacity(0.15)))
            )
            .contentShape(Rectangle())
        }
    }
}

struct SliderNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let key = node.string("bind") ?? "slider"
        let low = node.number("min") ?? 0
        let high = max(low + 0.0001, node.number("max") ?? 1)
        let current = min(high, max(low, env.state(key)?.doubleValue ?? low))
        let label = env.text(node, "label")
        VStack(alignment: .leading, spacing: 2) {
            if !label.isEmpty {
                HStack {
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(JSONValue.format(current, maxFractionDigits: 1)).font(.system(size: 11, design: .rounded)).monospacedDigit()
                }
            }
            if env.isWidgetKit {
                ProgressView(value: (current - low) / (high - low)).tint(env.tint)
            } else {
                Slider(value: Binding(get: { current }, set: { newValue in
                    let step = node.number("step") ?? 0
                    let snapped = step > 0 ? (newValue / step).rounded() * step : newValue
                    env.setState(key, .number(snapped))
                    if let action = WidgetAction(json: node.props["onChange"]) { env.perform(action) }
                }), in: low...high)
                .controlSize(.small)
                .tint(env.tint)
                .disabled(!env.isInteractive)
            }
        }
    }
}

struct ToggleNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    var body: some View {
        let key = node.string("bind") ?? "enabled"
        let isOn = env.state(key)?.boolValue ?? false
        let label = env.text(node, "label")
        if env.isWidgetKit {
            env.button(.toggleState(key: key)) {
                HStack {
                    Text(label).font(.system(size: 12))
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(isOn ? env.tint : .secondary)
                }
            }
        } else {
            Toggle(isOn: Binding(get: { isOn }, set: { newValue in
                env.setState(key, .bool(newValue))
                if let action = WidgetAction(json: node.props["onChange"]) { env.perform(action) }
            })) {
                Text(label).font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(env.tint)
            .disabled(!env.isInteractive)
        }
    }
}

/// Text entry bound to widget state. Keeps a local buffer so typing never fights with re-renders.
struct InputNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        let key = node.string("bind") ?? "text"
        let stored = env.state(key)?.stringValue ?? ""
        let multiline = node.bool("multiline") ?? false
        let size = CGFloat(node.number("fontSize") ?? 13)
        Group {
            if env.isWidgetKit || !env.isInteractive {
                Text(stored.isEmpty ? env.text(node, "placeholder") : stored)
                    .font(.system(size: size))
                    .foregroundStyle(stored.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, maxHeight: multiline ? .infinity : nil, alignment: .topLeading)
            } else if multiline {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(env.text(node, "placeholder")).font(.system(size: size)).foregroundStyle(.tertiary)
                            .padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: size))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                }
            } else {
                TextField(env.text(node, "placeholder"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: size))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    .onSubmit {
                        if let action = WidgetAction(json: node.props["action"]) { env.perform(action) }
                    }
            }
        }
        .onAppear {
            if !loaded { text = stored; loaded = true }
        }
        .onChange(of: text) { _, newValue in
            if loaded, newValue != stored { env.setState(key, .string(newValue)) }
        }
        .onChange(of: stored) { _, newValue in
            if newValue != text { text = newValue }      // changed elsewhere (automation, script, WidgetKit intent)
        }
    }
}

// MARK: To-do

struct TodoNode: View {
    let node: WidgetNode
    let env: RenderEnvironment
    @State private var draft = ""

    var body: some View {
        let key = node.string("bind") ?? "items"
        let items = env.state(key)?.arrayValue ?? []
        VStack(alignment: .leading, spacing: 5) {
            if !env.isWidgetKit && env.isInteractive {
                HStack(spacing: 4) {
                    TextField(env.text(node, "placeholder", default: "New task"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { add(key, items) }
                    Button { add(key, items) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(env.tint)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add task")
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            if items.isEmpty {
                Text("No tasks yet").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        row(key, items, index, item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ key: String, _ items: [JSONValue], _ index: Int, _ item: JSONValue) -> some View {
        let done = item["done"]?.boolValue ?? false
        var toggled = items
        toggled[index] = item.setting("done", to: .bool(!done))
        var removed = items
        removed.remove(at: index)
        return HStack(spacing: 6) {
            env.button(.setState(key: key, value: .array(toggled))) {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? env.tint : .secondary)
                    Text(item["title"]?.stringValue ?? "")
                        .font(.system(size: 12))
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            if !env.isWidgetKit && env.isInteractive {
                Button { env.setState(key, .array(removed)) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Delete task")
            }
        }
    }

    private func add(_ key: String, _ items: [JSONValue]) {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        env.setState(key, .array(items + [["title": .string(title), "done": false]]))
        draft = ""
    }
}

// MARK: Pomodoro

/// State: `{phase: idle|work|break, endsAt: epoch seconds, remaining: seconds when paused, paused, sessions}`.
/// The end time is stored (not a ticking counter), so the timer stays correct across sleep and relaunch.
struct PomodoroNode: View {
    let node: WidgetNode
    let env: RenderEnvironment

    var body: some View {
        if let entry = env.entryDate {
            face(now: entry)
        } else {
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                face(now: timeline.date)
                    .onChange(of: PomodoroNode.isExpired(state, now: timeline.date)) { _, expired in
                        if expired { advance(now: timeline.date) }
                    }
            }
        }
    }

    private var key: String { node.string("bind") ?? "pomodoro" }
    private var state: JSONValue { env.state(key) ?? .object([:]) }
    private var workSeconds: Double { max(1, env.number(node, "workMinutes") ?? 25) * 60 }
    private var breakSeconds: Double { max(1, env.number(node, "breakMinutes") ?? 5) * 60 }

    static func isExpired(_ state: JSONValue, now: Date) -> Bool {
        guard let phase = state["phase"]?.stringValue, phase != "idle", state["paused"]?.boolValue != true,
              let endsAt = state["endsAt"]?.doubleValue else { return false }
        return now.timeIntervalSince1970 >= endsAt
    }

    static func remaining(_ state: JSONValue, now: Date, idle: Double) -> Double {
        switch state["phase"]?.stringValue ?? "idle" {
        case "idle": return idle
        default:
            if state["paused"]?.boolValue == true { return state["remaining"]?.doubleValue ?? idle }
            return max(0, (state["endsAt"]?.doubleValue ?? 0) - now.timeIntervalSince1970)
        }
    }

    private func face(now: Date) -> some View {
        let phase = state["phase"]?.stringValue ?? "idle"
        let paused = state["paused"]?.boolValue ?? false
        let left = PomodoroNode.remaining(state, now: now, idle: workSeconds)
        let total = phase == "break" ? breakSeconds : workSeconds
        let sessions = state["sessions"]?.intValue ?? 0
        let color: Color = phase == "break" ? .green : env.tint
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, 1 - left / total))))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Formatters.clock(left)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(phase == "idle" ? "Ready" : (paused ? "Paused" : (phase == "break" ? "Break" : "Focus")))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 110, maxHeight: 110)
            HStack(spacing: 10) {
                env.button(.setState(key: key, value: toggleValue(now: now))) {
                    Image(systemName: phase == "idle" || paused ? "play.fill" : "pause.fill").frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.18))).foregroundStyle(color)
                }
                env.button(.setState(key: key, value: ["phase": "idle", "sessions": .number(Double(sessions))])) {
                    Image(systemName: "arrow.counterclockwise").frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))).foregroundStyle(.secondary)
                }
                Text("\(sessions) done").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The state after pressing play/pause.
    private func toggleValue(now: Date) -> JSONValue {
        let phase = state["phase"]?.stringValue ?? "idle"
        let sessions = state["sessions"] ?? 0
        let t = now.timeIntervalSince1970
        if phase == "idle" { return ["phase": "work", "endsAt": .number(t + workSeconds), "paused": false, "sessions": sessions] }
        if state["paused"]?.boolValue == true {
            let left = state["remaining"]?.doubleValue ?? workSeconds
            return ["phase": .string(phase), "endsAt": .number(t + left), "paused": false, "sessions": sessions]
        }
        let left = max(0, (state["endsAt"]?.doubleValue ?? t) - t)
        return ["phase": .string(phase), "remaining": .number(left), "paused": true, "sessions": sessions]
    }

    private func advance(now: Date) {
        let phase = state["phase"]?.stringValue ?? "idle"
        let sessions = state["sessions"]?.doubleValue ?? 0
        let t = now.timeIntervalSince1970
        if phase == "work" {
            env.setState(key, ["phase": "break", "endsAt": .number(t + breakSeconds), "paused": false, "sessions": .number(sessions + 1)])
            env.notify("Focus session complete", "Time for a \(Int(breakSeconds / 60))-minute break.")
            env.perform(.trigger("pomodoro.workFinished"))
        } else if phase == "break" {
            env.setState(key, ["phase": "idle", "sessions": .number(sessions)])
            env.notify("Break over", "Ready for the next focus session.")
            env.perform(.trigger("pomodoro.breakFinished"))
        }
    }
}

// MARK: Habits

/// State: `{habitName: ["2026-11-22", …]}`. Shows the last seven days per habit; tap a day to toggle it.
struct HabitsNode: View {
    let node: WidgetNode
    let env: RenderEnvironment

    var body: some View {
        let key = node.string("bind") ?? "habits"
        let names = (env.value(node, "habits")?.arrayValue ?? []).map(\.displayString).filter { !$0.isEmpty }
        let state = env.state(key) ?? .object([:])
        let days = HabitsNode.lastDays(7, endingAt: env.now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Spacer()
                ForEach(days) { day in
                    Text(day.label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(width: 22)
                }
            }
            if names.isEmpty { Text("Add habits in settings").font(.system(size: 11)).foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { name in
                let done = Set((state[name]?.arrayValue ?? []).compactMap(\.stringValue))
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(HabitsNode.streak(done, endingAt: env.now))-day streak").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    ForEach(days) { day in
                        let isDone = done.contains(day.key)
                        let next = isDone ? done.subtracting([day.key]) : done.union([day.key])
                        env.button(.setState(key: key, value: state.setting(name, to: .array(next.sorted().suffix(400).map { .string($0) })))) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(isDone ? env.tint : Color.secondary.opacity(0.5))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(name), \(day.key)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    struct Day: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    static func lastDays(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [Day] {
        var days: [Day] = []
        for offset in (0..<count).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            let symbol = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
            days.append(Day(key: dayKey(day, calendar: calendar), label: symbol))
        }
        return days
    }

    /// Consecutive completed days ending today (or yesterday, so an unfinished today does not zero the streak).
    static func streak(_ done: Set<String>, endingAt date: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var offset = done.contains(dayKey(date, calendar: calendar)) ? 0 : 1
        while let day = calendar.date(byAdding: .day, value: -offset, to: date), done.contains(dayKey(day, calendar: calendar)) {
            count += 1
            offset += 1
        }
        return count
    }
}

// MARK: Clipboard

/// Saves the clipboard only when the user presses the button. There is no background monitoring.
struct ClipboardNode: View {
    let node: WidgetNode
    let env: RenderEnvironment

    var body: some View {
        let key = node.string("bind") ?? "clips"
        let clips = (env.state(key)?.arrayValue ?? []).compactMap(\.stringValue)
        let limit = Int(node.number("limit") ?? 6)
        VStack(alignment: .leading, spacing: 5) {
            if env.isWidgetKit {
                Text("Open WidgetForge to save clipboard items").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button {
                        guard let text = env.readClipboard(), !text.isEmpty else { return }
                        let next = ([text] + clips.filter { $0 != text }).prefix(limit)
                        env.setState(key, .array(next.map { .string(String($0.prefix(4000))) }))
                    } label: {
                        Label("Save Clipboard", systemImage: "plus.square.on.square").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(env.tint)
                    .disabled(!env.isInteractive)
                    Spacer()
                    if !clips.isEmpty {
                        Button("Clear") { env.setState(key, .array([])) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                            .disabled(!env.isInteractive)
                    }
                }
            }
            if clips.isEmpty { Text("Nothing saved").font(.system(size: 11)).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(clips.enumerated()), id: \.offset) { _, clip in
                        env.button(env.isWidgetKit ? nil : .copy(clip)) {
                            Text(clip.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 11))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                                .contentShape(Rectangle())
                        }
                        .help("Click to copy")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediaNode: View {
    let env: RenderEnvironment
    var body: some View {
        HStack(spacing: 18) {
            control("backward.fill", "previous", "Previous track")
            control("playpause.fill", "playpause", "Play or pause")
            control("forward.fill", "next", "Next track")
        }
        .font(.system(size: 20))
        .frame(maxWidth: .infinity)
    }

    private func control(_ symbol: String, _ command: String, _ label: String) -> some View {
        env.button(env.isWidgetKit ? nil : .media(command)) {
            Image(systemName: symbol).foregroundStyle(env.tint).frame(width: 34, height: 28).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: Widget chrome

/// The rounded, translucent container every widget is drawn in.
struct WidgetChrome<Content: View>: View {
    let style: WidgetStyle
    /// WidgetKit supplies its own container background and margins.
    var drawsBackground = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(style.cornerRadius), style: .continuous)
        content()
            .padding(CGFloat(style.padding))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if drawsBackground {
                    switch style.background {
                    case "material": shape.fill(.regularMaterial)
                    case "clear": Color.clear
                    default: shape.fill(Theme.hex(style.background) ?? Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .overlay {
                if style.borderWidth > 0 {
                    shape.strokeBorder(Theme.color(style.borderColor, fallback: Color.primary.opacity(0.2)), lineWidth: CGFloat(style.borderWidth))
                } else if drawsBackground && style.background == "material" {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .clipShape(shape)
    }
}

/// A complete widget: chrome plus its node tree. Used by overlay windows, previews and thumbnails.
struct WidgetContentView: View {
    let definition: WidgetDefinition
    var env: RenderEnvironment
    var drawsBackground = true

    var body: some View {
        var environment = env
        environment.tint = Theme.color(definition.style.tint, fallback: .accentColor)
        environment.designSize = WidgetSize(max(1, definition.size.width - definition.style.padding * 2),
                                            max(1, definition.size.height - definition.style.padding * 2))
        return WidgetChrome(style: definition.style, drawsBackground: drawsBackground) {
            NodeView(node: definition.root, env: environment)
        }
    }
}
