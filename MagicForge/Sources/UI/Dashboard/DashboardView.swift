import SwiftUI
import MFCore
import MFEngine

/// Overview of the device, active profile, input pipeline and recent activity.
@MainActor
public struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    public init() {}

    public var body: some View {
        MFPage("Dashboard", subtitle: "What MagicForge sees and does right now.", toolbar: {
            ShellPauseToggle()
        }, content: {
            if let persistenceError = model.persistenceError {
                DashboardPersistenceErrorCard(message: persistenceError)
            }
            HStack(alignment: .top, spacing: 16) {
                DashboardDeviceCard()
                DashboardProfileCard()
            }
            HStack(alignment: .top, spacing: 16) {
                DashboardInputCard()
                DashboardPermissionsCard()
            }
            if !model.runningWorkflows.isEmpty {
                DashboardWorkflowsCard()
            }
            DashboardRecentGesturesCard()
            DashboardMetricsCard()
        })
    }
}

@MainActor
struct DashboardPersistenceErrorCard: View {
    let message: String

    var body: some View {
        MFCard("Configuration problem", systemImage: "exclamationmark.octagon") {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
struct DashboardDeviceCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        MFCard("Mouse", systemImage: "magicmouse") {
            if let device = model.connectedDevice {
                connected(device)
            } else {
                MFEmptyState(
                    systemImage: "magicmouse",
                    title: "No Magic Mouse connected",
                    message: "Turn on your Magic Mouse and connect it with Bluetooth or its cable. It appears here automatically."
                )
            }
            Button("Device Details") {
                navigation.section = .devices
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func connected(_ device: DeviceInfo) -> some View {
        HStack {
            Text(device.name)
                .font(.title3)
                .fontWeight(.medium)
            Spacer()
            MFStatusBadge("Connected", style: .good)
        }
        MFKeyValueRow("Model", value: device.model.displayName)
        MFKeyValueRow("Connection", value: device.transport)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Battery")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Image(systemName: ShellFormat.batterySymbol(device.batteryPercent))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(ShellFormat.battery(device.batteryPercent))
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct DashboardProfileCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        MFCard("Active profile", systemImage: "square.stack.3d.up") {
            HStack {
                Image(systemName: model.activeProfile?.symbolName ?? "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(model.activeProfile?.name ?? "No profile")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                modeBadge
            }
            MFKeyValueRow("Enabled gestures", value: ShellFormat.count(model.enabledGestureCount))
            MFKeyValueRow("Frontmost app", value: frontmostText)
            HStack {
                overrideMenu
                Button("Edit Profiles") {
                    navigation.section = .profiles
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var modeBadge: some View {
        if model.profileOverrideID != nil {
            MFStatusBadge("Manual override", style: .warning)
        } else {
            MFStatusBadge("Automatic", style: .info)
        }
    }

    private var overrideMenu: some View {
        Menu("Switch Profile") {
            Button("Automatic (follow the frontmost app)") {
                model.setProfileOverride(nil)
            }
            .disabled(model.profileOverrideID == nil)
            Divider()
            ForEach(model.configuration.profiles) { profile in
                Button(profile.name) {
                    model.setProfileOverride(profile.id)
                }
                .disabled(!profile.isEnabled || model.profileOverrideID == profile.id)
            }
        }
        .controlSize(.small)
        .fixedSize()
    }

    private var frontmostText: String {
        guard let bundleID = model.frontmostBundleID else { return ShellFormat.placeholder }
        return ShellAppLookup.name(forBundleID: bundleID) ?? bundleID
    }
}

@MainActor
struct DashboardInputCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status: AdapterStatus = model.adapterStatus
        MFCard("Touch input", systemImage: "dot.radiowaves.left.and.right") {
            HStack {
                Text(status.displayName)
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                MFStatusBadge(status.state.shellLabel, style: status.state.shellStyle)
            }
            if let reason = status.state.shellUnavailableReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status.usesPrivateAPI {
                Label("Uses Apple's private MultitouchSupport framework. It is unsupported and can stop working after a macOS update.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MFKeyValueRow("Finger positions", value: ShellFormat.yesNo(status.capabilities.rawContacts))
            MFKeyValueRow("Simultaneous contacts", value: ShellFormat.count(status.capabilities.maxContacts))
            MFKeyValueRow("Contact size", value: ShellFormat.yesNo(status.capabilities.contactSize))
            MFKeyValueRow("Click and scroll events", value: ShellFormat.yesNo(status.capabilities.pointerEvents))
            Button("Restart Input") {
                model.restartInput()
            }
            .controlSize(.small)
        }
    }
}

@MainActor
struct DashboardPermissionsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        MFCard("Permissions", systemImage: "lock.shield") {
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                DashboardPermissionRow(kind: kind)
            }
            Button("Manage Permissions") {
                navigation.section = .permissions
            }
            .controlSize(.small)
        }
    }
}

@MainActor
struct DashboardPermissionRow: View {
    let kind: PermissionKind
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text(kind.displayName)
                .font(.callout)
            Spacer()
            badge
        }
    }

    @ViewBuilder private var badge: some View {
        let status: PermissionStatus? = model.permissions[kind]
        if let status {
            if status != .granted, model.permissionRationale(kind) == nil {
                MFStatusBadge("Not needed", style: .neutral)
            } else {
                MFStatusBadge(status.shellLabel, style: status.shellStyle)
            }
        } else {
            MFStatusBadge("Unknown", style: .neutral)
        }
    }
}
