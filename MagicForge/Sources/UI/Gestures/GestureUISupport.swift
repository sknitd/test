import SwiftUI
import MFCore
import MFEngine

/// Pure helpers shared by the gesture screens (profile lookup, binding edits, conflict styling).
enum GestureUI {
    // MARK: Profiles

    /// The profile a screen edits: `editingProfileID` when it still exists, else the global one.
    static func resolvedProfileID(_ editingProfileID: UUID?, in configuration: Configuration) -> UUID {
        if let id = editingProfileID, configuration.profiles.contains(where: { $0.id == id }) { return id }
        return configuration.globalProfileID
    }

    static func profile(_ id: UUID, in configuration: Configuration) -> Profile? {
        configuration.profiles.first { $0.id == id }
    }

    static func profileTitle(_ profile: Profile, in configuration: Configuration) -> String {
        profile.id == configuration.globalProfileID ? "\(profile.name) (Global)" : profile.name
    }

    // MARK: Binding edits (always called inside `model.update`)

    /// Replaces the binding with the same id, or appends it.
    static func upsert(_ binding: GestureBinding, inProfile profileID: UUID, configuration: inout Configuration) {
        guard let profileIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        if let index = configuration.profiles[profileIndex].bindings.firstIndex(where: { $0.id == binding.id }) {
            configuration.profiles[profileIndex].bindings[index] = binding
        } else {
            configuration.profiles[profileIndex].bindings.append(binding)
        }
    }

    static func removeBinding(_ bindingID: UUID, fromProfile profileID: UUID, configuration: inout Configuration) {
        guard let profileIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        configuration.profiles[profileIndex].bindings.removeAll { $0.id == bindingID }
    }

    static func setEnabled(_ isEnabled: Bool, bindingID: UUID, inProfile profileID: UUID,
                           configuration: inout Configuration) {
        guard let profileIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }),
              let index = configuration.profiles[profileIndex].bindings.firstIndex(where: { $0.id == bindingID })
        else { return }
        configuration.profiles[profileIndex].bindings[index].isEnabled = isEnabled
    }

    // MARK: Conflicts

    static func rank(_ severity: BindingConflict.Severity) -> Int {
        switch severity {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    static func worstSeverity(_ conflicts: [BindingConflict]) -> BindingConflict.Severity? {
        conflicts.map(\.severity).max { rank($0) < rank($1) }
    }

    static func statusStyle(for severity: BindingConflict.Severity) -> MFStatusStyle {
        switch severity {
        case .info: return .info
        case .warning: return .warning
        case .error: return .bad
        }
    }

    static func symbolName(for severity: BindingConflict.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    static func title(for severity: BindingConflict.Severity) -> String {
        switch severity {
        case .info: return "Note"
        case .warning: return "Warning"
        case .error: return "Conflict"
        }
    }

    // MARK: Availability

    /// nil when every gesture of the trigger can be delivered, else the first reason.
    @MainActor static func unavailableReason(for trigger: GestureTrigger, model: AppModel) -> String? {
        for kind in trigger.kinds {
            if case .unavailable(let reason) = model.availability(of: kind) { return reason }
        }
        return nil
    }

    static func symbolName(for trigger: GestureTrigger) -> String {
        switch trigger {
        case .single(let kind): return kind.symbolName
        case .sequence: return "list.number"
        }
    }
}

/// "Available" / "Unavailable" badge for a trigger; the reason is the tooltip and the
/// accessibility value.
@MainActor
struct GestureAvailabilityBadge: View {
    let trigger: GestureTrigger
    @Environment(AppModel.self) private var model

    var body: some View {
        if let reason = GestureUI.unavailableReason(for: trigger, model: model) {
            MFStatusBadge("Unavailable", style: .warning)
                .help(reason)
                .accessibilityLabel(Text("Unavailable: \(reason)"))
        } else {
            MFStatusBadge("Available", style: .good)
        }
    }
}

/// Picks the profile the gesture screens edit. Writes `NavigationState.editingProfileID`
/// (nil for the global profile).
@MainActor
struct GestureProfileScopePicker: View {
    var title: String = "Profile"
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(model.configuration.profiles) { profile in
                Label(GestureUI.profileTitle(profile, in: model.configuration), systemImage: profile.symbolName)
                    .tag(profile.id)
            }
        }
        .frame(maxWidth: 320)
    }

    private var selection: Binding<UUID> {
        let model: AppModel = self.model
        let navigation: NavigationState = self.navigation
        return Binding<UUID>(
            get: { GestureUI.resolvedProfileID(navigation.editingProfileID, in: model.configuration) },
            set: { newValue in
                navigation.editingProfileID = newValue == model.configuration.globalProfileID ? nil : newValue
            }
        )
    }
}

/// Conflict messages with severity colouring.
struct GestureConflictList: View {
    let conflicts: [BindingConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sorted) { conflict in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: GestureUI.symbolName(for: conflict.severity))
                        .foregroundStyle(GestureUI.statusStyle(for: conflict.severity).color)
                        .accessibilityLabel(Text(GestureUI.title(for: conflict.severity)))
                    Text(conflict.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sorted: [BindingConflict] {
        conflicts.sorted { GestureUI.rank($0.severity) > GestureUI.rank($1.severity) }
    }
}
