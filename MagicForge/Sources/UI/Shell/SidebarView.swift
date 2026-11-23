import SwiftUI
import MFCore
import MFEngine

struct ShellSidebarGroup: Identifiable {
    let title: String
    let sections: [SidebarSection]
    var id: String { title }

    static let all: [ShellSidebarGroup] = [
        ShellSidebarGroup(title: "Overview", sections: [.dashboard]),
        ShellSidebarGroup(title: "Gestures", sections: [.gestures, .gestureStudio, .touchLab]),
        ShellSidebarGroup(title: "Configure",
                          sections: [.profiles, .actions, .automation, .radialMenu, .scrolling, .ai]),
        ShellSidebarGroup(title: "System", sections: [.devices, .permissions, .settings]),
    ]
}

@MainActor
struct ShellSidebarView: View {
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        List(selection: selection) {
            ForEach(ShellSidebarGroup.all) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShellStatusFooter()
        }
    }

    private var selection: Binding<SidebarSection?> {
        Binding<SidebarSection?>(
            get: { navigation.section },
            set: { newValue in
                if let newValue { navigation.section = newValue }
            }
        )
    }
}

/// Compact status at the bottom of the sidebar: device, active profile, pause switch.
@MainActor
struct ShellStatusFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            deviceLine
            profileLine
            ShellPauseToggle()
                .controlSize(.small)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private var deviceLine: some View {
        Button {
            navigation.section = .devices
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.connectedDevice == nil ? "magicmouse" : "magicmouse.fill")
                    .foregroundStyle(model.connectedDevice == nil ? Color.secondary : Color.accentColor)
                Text(deviceText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show devices")
        .accessibilityLabel("Device: \(deviceText)")
    }

    private var profileLine: some View {
        Button {
            navigation.section = .profiles
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
                Text(profileText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show profiles")
        .accessibilityLabel("Active profile: \(profileText)")
    }

    private var deviceText: String {
        guard let device = model.connectedDevice else { return "No Magic Mouse" }
        if let battery = device.batteryPercent { return "\(device.name) · \(battery)%" }
        return device.name
    }

    private var profileText: String {
        let name: String = model.activeProfile?.name ?? "No profile"
        return model.profileOverrideID == nil ? name : "\(name) (manual)"
    }
}
