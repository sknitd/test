import SwiftUI
import MFCore
import MFEngine

/// Smart Scroll settings of the profile being edited. The global profile always has its own
/// settings; an app profile either inherits them (`scroll == nil`) or overrides them.
@MainActor
public struct ScrollingView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    public init() {}

    private var profileID: UUID {
        GestureUI.resolvedProfileID(navigation.editingProfileID, in: model.configuration)
    }

    private var isGlobal: Bool { profileID == model.configuration.globalProfileID }

    private var globalSettings: ScrollSettings { model.configuration.globalProfile?.scroll ?? ScrollSettings() }

    /// True when an app profile has no settings of its own.
    private var inheritsGlobal: Bool {
        !isGlobal && GestureUI.profile(profileID, in: model.configuration)?.scroll == nil
    }

    /// The settings shown: the profile's own, or the global ones it inherits.
    private var settings: ScrollSettings {
        GestureUI.profile(profileID, in: model.configuration)?.scroll ?? globalSettings
    }

    public var body: some View {
        MFPage("Scrolling", subtitle: "Smart Scroll adjusts scroll events from the mouse. It is off unless you turn it on.") {
            GestureProfileScopePicker()
            if !isGlobal {
                MFCard {
                    Toggle("Use global scrolling settings", isOn: inheritBinding)
                    Text(inheritsGlobal ? "This profile follows the global profile's scrolling settings shown below."
                        : "This profile overrides the global scrolling settings while one of its apps is frontmost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollSettingsCards(
                settings: settings,
                binding: { (keyPath: WritableKeyPath<ScrollSettings, Double>) -> Binding<Double> in binding(keyPath) },
                boolBinding: { (keyPath: WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool> in binding(keyPath) }
            )
                .disabled(inheritsGlobal)
            MFCard("Response", systemImage: "chart.xyaxis.line") {
                ScrollResponseChart(settings: settings)
                Text(responseNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollEdgeActionsCard()
            ScrollRequirementsCard(settings: settings)
        }
    }

    private var responseNote: String {
        var parts: [String] = ["The chart shows the speed multipliers and inversion only."]
        if settings.acceleration > 0 {
            parts.append("Acceleration is on: fast flicks get additional gain on top of these lines, slow scrolling does not.")
        } else {
            parts.append("Acceleration is off, so the response is linear.")
        }
        if settings.smoothing > 0 {
            parts.append("Smoothing averages line-based scroll steps over time and is not drawn.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Bindings

    private var inheritBinding: Binding<Bool> {
        let model: AppModel = self.model
        let profileID: UUID = self.profileID
        let inherited: ScrollSettings = globalSettings
        return Binding<Bool>(
            get: { GestureUI.profile(profileID, in: model.configuration)?.scroll == nil },
            set: { useGlobal in
                model.update { configuration in
                    guard let index = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
                    // Overriding starts from the values that were in effect.
                    configuration.profiles[index].scroll = useGlobal ? nil : inherited
                }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ScrollSettings, Value>) -> Binding<Value> {
        let model: AppModel = self.model
        let profileID: UUID = self.profileID
        let current: ScrollSettings = settings
        return Binding<Value>(
            get: { current[keyPath: keyPath] },
            set: { newValue in
                model.update { configuration in
                    guard let index = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
                    var updated: ScrollSettings = configuration.profiles[index].scroll ?? current
                    updated[keyPath: keyPath] = newValue
                    configuration.profiles[index].scroll = updated
                }
            }
        )
    }
}

/// Master switch, speed, direction and feel.
@MainActor
private struct ScrollSettingsCards: View {
    let settings: ScrollSettings
    let boolBinding: (WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool>
    let doubleBinding: (WritableKeyPath<ScrollSettings, Double>) -> Binding<Double>

    init(settings: ScrollSettings, binding: @escaping (WritableKeyPath<ScrollSettings, Double>) -> Binding<Double>,
         boolBinding: @escaping (WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool>) {
        self.settings = settings
        self.doubleBinding = binding
        self.boolBinding = boolBinding
    }

    var body: some View {
        MFCard("Smart Scroll", systemImage: "arrow.up.and.down") {
            Toggle("Enable Smart Scroll", isOn: boolBinding(\.isEnabled))
            Text("While this is off, scroll events are never touched and native scrolling behaves exactly as macOS delivers it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Only change scrolling from a Magic Mouse", isOn: boolBinding(\.magicMouseOnly))
                .help("Trackpads and other mice are left alone")
        }
        MFCard("Speed and Direction", systemImage: "speedometer") {
            ScrollSliderRow(title: "Vertical speed", value: doubleBinding(\.verticalMultiplier), range: 0.1...5,
                            text: String(format: "×%.2f", settings.verticalMultiplier))
            ScrollSliderRow(title: "Horizontal speed", value: doubleBinding(\.horizontalMultiplier), range: 0.1...5,
                            text: String(format: "×%.2f", settings.horizontalMultiplier))
            Toggle("Invert vertical scrolling", isOn: boolBinding(\.invertVertical))
            Toggle("Invert horizontal scrolling", isOn: boolBinding(\.invertHorizontal))
        }
        MFCard("Feel", systemImage: "waveform") {
            ScrollSliderRow(title: "Acceleration", value: doubleBinding(\.acceleration), range: 0...1,
                            text: Self.level(settings.acceleration, zero: "Linear"))
            ScrollSliderRow(title: "Smoothing", value: doubleBinding(\.smoothing), range: 0...1,
                            text: Self.level(settings.smoothing, zero: "None"))
            ScrollSliderRow(title: "Horizontal dead zone", value: doubleBinding(\.horizontalDeadZone), range: 0...1,
                            text: Self.level(settings.horizontalDeadZone, zero: "Off"))
            Text("The dead zone ignores sideways movement smaller than this fraction of the vertical movement, "
                + "which keeps vertical scrolling from drifting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func level(_ value: Double, zero: String) -> String {
        value <= 0 ? zero : "\(Int((value * 100).rounded())) %"
    }
}

private struct ScrollSliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 150, alignment: .leading)
            Slider(value: value, in: range) {
                Text(title)
            }
            .labelsHidden()
            Text(text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

/// Edge-based scroll actions: shortcuts into Gesture Studio for the four edge swipes.
@MainActor
private struct ScrollEdgeActionsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    private static let edgeKinds: [GestureKind] = [.leftEdgeSwipe, .rightEdgeSwipe, .topEdgeSwipe, .bottomEdgeSwipe]

    var body: some View {
        MFCard("Edge Actions", systemImage: "rectangle.portrait.and.arrow.right") {
            Text("Sliding along an edge strip of the mouse is a separate gesture and does not scroll. "
                + "Bind an action to each edge in Gesture Studio.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.edgeKinds, id: \.self) { kind in
                row(kind)
            }
        }
    }

    private func row(_ kind: GestureKind) -> some View {
        let binding: GestureBinding? = currentBinding(for: kind)
        return HStack(spacing: 10) {
            Image(systemName: kind.symbolName)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(kind.displayName)
            Spacer()
            if let binding {
                ActionLabel(action: binding.action)
                if !binding.isEnabled { MFStatusBadge("Disabled", style: .neutral) }
            } else {
                Text("Not bound")
                    .foregroundStyle(.secondary)
            }
            GestureAvailabilityBadge(trigger: .single(kind))
            Button(binding == nil ? "Bind…" : "Edit…") {
                navigation.selectedGesture = kind
                navigation.section = .gestureStudio
            }
        }
    }

    private func currentBinding(for kind: GestureKind) -> GestureBinding? {
        let profileID: UUID = GestureUI.resolvedProfileID(navigation.editingProfileID, in: model.configuration)
        return GestureUI.profile(profileID, in: model.configuration)?.bindings.first { $0.trigger == .single(kind) }
    }
}

/// What Smart Scroll needs, with the live permission status and the state of the settings.
@MainActor
private struct ScrollRequirementsCard: View {
    let settings: ScrollSettings
    @Environment(AppModel.self) private var model

    var body: some View {
        let status: PermissionStatus = model.permissions[.accessibility] ?? .notDetermined
        MFCard("Requirements and Status", systemImage: "lock.shield") {
            Text("Smart Scroll rewrites scroll events in a global event tap, which macOS only allows with the "
                + "Accessibility permission.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(PermissionKind.accessibility.displayName)
                Spacer()
                MFStatusBadge(Self.title(for: status), style: Self.style(for: status))
            }
            HStack {
                Text("Smart Scroll setting")
                Spacer()
                MFStatusBadge(settings.isEnabled ? "On" : "Off", style: settings.isEnabled ? .good : .neutral)
            }
            if settings.isEnabled && status != .granted && status != .notRequired {
                Label("Smart Scroll is on but cannot modify scrolling until Accessibility access is granted.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Whether the event tap is currently installed is not reported by the engine, so only the permission "
                + "and the setting are shown here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if status != .granted && status != .notRequired {
                    Button("Request Access") { model.requestPermission(.accessibility) }
                    Button("Open System Settings") { model.openPermissionSettings(.accessibility) }
                }
                Button("Refresh Status") { model.refreshPermissions() }
            }
        }
    }

    private static func title(for status: PermissionStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        case .notRequired: return "Not required"
        }
    }

    private static func style(for status: PermissionStatus) -> MFStatusStyle {
        switch status {
        case .granted, .notRequired: return .good
        case .denied: return .bad
        case .notDetermined: return .warning
        }
    }
}
