import SwiftUI
import MFCore
import MFEngine

/// Right column: editor for one profile. All edits go through `model.update`.
@MainActor
struct ProfilesDetailPane: View {
    let profileID: UUID

    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    static let symbolChoices: [String] = [
        "cursorarrow.motionlines", "globe", "app", "safari", "doc.text", "paintbrush", "hammer", "terminal",
        "music.note", "film", "gamecontroller", "envelope", "message", "folder", "photo", "keyboard", "star",
    ]

    var body: some View {
        if let profile = model.configuration.profiles.first(where: { $0.id == profileID }) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    generalCard(profile)
                    if !isGlobal {
                        ProfilesAppsCard(profile: profile)
                    }
                    gesturesCard(profile)
                    activationCard(profile)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            MFEmptyState(systemImage: "square.stack.3d.up", title: "No profile selected",
                         message: "Select a profile in the list to edit it.")
        }
    }

    private var isGlobal: Bool { profileID == model.configuration.globalProfileID }

    private func mutate(_ change: (inout Profile) -> Void) {
        let id: UUID = profileID
        model.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
            change(&configuration.profiles[index])
        }
    }

    // MARK: General

    private func generalCard(_ profile: Profile) -> some View {
        MFCard("General", systemImage: "slider.horizontal.3") {
            LabeledContent("Name") {
                ShellCommitTextField(title: "Profile name", value: profile.name, onCommit: { newName in
                    mutate { $0.name = newName }
                })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            }
            Picker("Symbol", selection: symbolBinding(profile)) {
                ForEach(symbolOptions(profile), id: \.self) { name in
                    Label(name, systemImage: name).tag(name)
                }
            }
            .frame(maxWidth: 360)
            if isGlobal {
                Text("The global profile is always enabled and cannot be deleted. Its gestures apply whenever no app profile matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Toggle("Enabled", isOn: Binding<Bool>(
                    get: { profile.isEnabled },
                    set: { newValue in mutate { $0.isEnabled = newValue } }
                ))
                Toggle("Fall back to the global profile for gestures not bound here", isOn: Binding<Bool>(
                    get: { profile.inheritsGlobal },
                    set: { newValue in mutate { $0.inheritsGlobal = newValue } }
                ))
            }
        }
    }

    private func symbolOptions(_ profile: Profile) -> [String] {
        var options: [String] = ProfilesDetailPane.symbolChoices
        if !options.contains(profile.symbolName) { options.insert(profile.symbolName, at: 0) }
        return options
    }

    private func symbolBinding(_ profile: Profile) -> Binding<String> {
        Binding<String>(
            get: { profile.symbolName },
            set: { newValue in mutate { $0.symbolName = newValue } }
        )
    }

    // MARK: Gestures

    private func gesturesCard(_ profile: Profile) -> some View {
        let enabledCount: Int = profile.bindings.filter { $0.isEnabled }.count
        let conflictCount: Int = model.conflicts(inProfile: profile.id).count
        return MFCard("Gestures", systemImage: "hand.tap") {
            MFKeyValueRow("Bindings", value: "\(profile.bindings.count) (\(enabledCount) enabled)")
            MFKeyValueRow("Conflicts and warnings", value: ShellFormat.count(conflictCount))
            Button("Edit Gestures") {
                navigation.editingProfileID = isGlobal ? nil : profile.id
                navigation.section = .gestures
            }
        }
    }

    // MARK: Activation

    private func activationCard(_ profile: Profile) -> some View {
        let isOverride: Bool = model.profileOverrideID == profile.id
        let isActive: Bool = model.activeProfileID == profile.id
        return MFCard("Activation", systemImage: "pin") {
            HStack {
                Text(activationText(isOverride: isOverride, isActive: isActive))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isOverride {
                    MFStatusBadge("Manual override", style: .warning)
                } else if isActive {
                    MFStatusBadge("Active", style: .good)
                }
            }
            HStack {
                Button("Use This Profile Now") {
                    model.setProfileOverride(profile.id)
                }
                .disabled(isOverride || !profile.isEnabled)
                Button("Automatic") {
                    model.setProfileOverride(nil)
                }
                .disabled(model.profileOverrideID == nil)
                .help("Switch profiles automatically with the frontmost app")
            }
        }
    }

    private func activationText(isOverride: Bool, isActive: Bool) -> String {
        if isOverride { return "This profile stays active in every app until you choose Automatic." }
        if model.profileOverrideID != nil { return "Another profile is pinned manually. Choose Automatic to follow the frontmost app again." }
        if isActive { return "Active now, chosen automatically." }
        if isGlobal { return "Used whenever no enabled app profile matches the frontmost app." }
        return "Activates automatically when one of its apps is frontmost."
    }
}
