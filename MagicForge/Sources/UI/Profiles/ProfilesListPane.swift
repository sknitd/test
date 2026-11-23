import SwiftUI
import MFCore
import MFEngine

/// Left column: every profile (global first) with add / duplicate / delete controls.
@MainActor
struct ProfilesListPane: View {
    let selection: Binding<UUID?>
    let onAdd: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(orderedProfiles) { profile in
                    ProfilesListRow(profile: profile)
                        .tag(profile.id)
                }
            }
            .listStyle(.inset)
            Divider()
            controls
        }
    }

    private var orderedProfiles: [Profile] {
        let globalID: UUID = model.configuration.globalProfileID
        let profiles: [Profile] = model.configuration.profiles
        let global: [Profile] = profiles.filter { $0.id == globalID }
        let others: [Profile] = profiles.filter { $0.id != globalID }
        return global + others
    }

    private var selectionIsGlobal: Bool {
        selection.wrappedValue == nil || selection.wrappedValue == model.configuration.globalProfileID
    }

    private var controls: some View {
        HStack(spacing: 2) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 18)
            }
            .help("Add a profile")
            .accessibilityLabel("Add profile")
            Button(action: onDelete) {
                Image(systemName: "minus")
                    .frame(width: 22, height: 18)
            }
            .disabled(selectionIsGlobal)
            .help(selectionIsGlobal ? "The global profile cannot be deleted" : "Delete the selected profile")
            .accessibilityLabel("Delete profile")
            Button(action: onDuplicate) {
                Image(systemName: "plus.square.on.square")
                    .frame(width: 22, height: 18)
            }
            .help("Duplicate the selected profile")
            .accessibilityLabel("Duplicate profile")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

@MainActor
struct ProfilesListRow: View {
    let profile: Profile
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            indicators
        }
        .padding(.vertical, 2)
        .opacity(profile.isEnabled ? 1 : 0.55)
    }

    @ViewBuilder private var icon: some View {
        if let bundleID = profile.bundleIdentifiers.first, ShellAppLookup.icon(forBundleID: bundleID) != nil {
            ShellAppIcon(bundleID: bundleID, size: 22)
        } else {
            Image(systemName: isGlobal ? "globe" : profile.symbolName)
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var indicators: some View {
        if model.profileOverrideID == profile.id {
            Image(systemName: "pin.fill")
                .foregroundStyle(Color.orange)
                .help("Manual override")
                .accessibilityLabel("Manual override")
        }
        if model.activeProfileID == profile.id {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .help("Active now")
                .accessibilityLabel("Active now")
        }
    }

    private var isGlobal: Bool { profile.id == model.configuration.globalProfileID }

    private var subtitle: String {
        if isGlobal { return "Global · all apps" }
        if !profile.isEnabled { return "Disabled" }
        switch profile.bundleIdentifiers.count {
        case 0: return "Manual profile"
        case 1: return ShellAppLookup.name(forBundleID: profile.bundleIdentifiers[0]) ?? profile.bundleIdentifiers[0]
        default: return "\(profile.bundleIdentifiers.count) apps"
        }
    }
}
