import SwiftUI
import AppKit
import Observation
import MFCore
import MFEngine

/// Remembers which permission prompts were already requested during this launch, so the
/// "Request" button is offered once (macOS shows each prompt at most once anyway).
@MainActor
@Observable
final class ShellPermissionRequestTracker {
    static let shared = ShellPermissionRequestTracker()
    var requested: Set<PermissionKind> = []
    private init() {}
}

/// Status and controls for every permission MagicForge can use.
@MainActor
public struct PermissionsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        MFPage("Permissions", subtitle: "MagicForge only asks for what your configuration needs. Status refreshes whenever you return to the app.",
               toolbar: {
            Button("Check Again") {
                model.refreshPermissions()
            }
            Button("Restart Input") {
                model.restartInput()
            }
            .help("Restart the touch adapter and event tap after granting a permission")
        }, content: {
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                PermissionsKindCard(kind: kind)
            }
            Text("Permissions are granted in System Settings › Privacy & Security. macOS may require you to quit and reopen MagicForge after changing Accessibility or Input Monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        })
        .onAppear {
            model.refreshPermissions()
        }
        .shellRefreshPermissionsOnActivation(model)
    }
}

extension View {
    /// Re-reads permission status when the app becomes active again (no polling).
    @MainActor
    func shellRefreshPermissionsOnActivation(_ model: AppModel) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }
}

/// One permission: status badge, rationale and the actions that make sense for it.
@MainActor
struct PermissionsKindCard: View {
    let kind: PermissionKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let status: PermissionStatus = model.permissions[kind] ?? .notDetermined
        let rationale: String? = model.permissionRationale(kind)
        MFCard {
            HStack {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(kind.displayName)
                    .font(.headline)
                Spacer()
                if rationale == nil, status != .granted {
                    MFStatusBadge("Not required", style: .neutral)
                } else {
                    MFStatusBadge(status.shellLabel, style: status.shellStyle)
                }
            }
            Text(rationale ?? "Not required by your current configuration. You do not need to grant it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .automation, rationale != nil {
                Text("macOS asks for Automation access separately for each app, the first time a script controls it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PermissionsActionRow(kind: kind, status: status, isRequired: rationale != nil)
        }
    }

    private var symbolName: String {
        switch kind {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "keyboard"
        case .automation: return "applescript"
        }
    }
}

@MainActor
struct PermissionsActionRow: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let isRequired: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if canRequest {
                Button("Request Access") {
                    ShellPermissionRequestTracker.shared.requested.insert(kind)
                    model.requestPermission(kind)
                }
            } else if showsRequestedNote {
                Text("Requested. Finish in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Open System Settings") {
                model.openPermissionSettings(kind)
            }
            Button("Check Again") {
                model.refreshPermissions()
            }
            Spacer()
        }
        .controlSize(.small)
    }

    private var needsGrant: Bool {
        isRequired && (status == .denied || status == .notDetermined)
    }

    private var alreadyRequested: Bool {
        ShellPermissionRequestTracker.shared.requested.contains(kind)
    }

    /// A system prompt only exists for Accessibility and Input Monitoring; Automation is asked
    /// per target app by macOS when a script first runs.
    private var canRequest: Bool {
        needsGrant && kind != .automation && !alreadyRequested
    }

    private var showsRequestedNote: Bool {
        needsGrant && kind != .automation && alreadyRequested
    }
}
