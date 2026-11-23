import SwiftUI
import MFCore
import MFEngine

/// Persistent warnings shown above every screen until the problem is fixed or the banner is
/// dismissed for this session.
@MainActor
struct ShellBannerStack: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    @State private var dismissedAdapter: Bool = false
    @State private var dismissedAccessibility: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let reason = adapterProblem, !dismissedAdapter {
                ShellBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    message: "Touch input is unavailable: \(reason) Only fallback triggers work.",
                    actionTitle: "Show Devices",
                    action: { navigation.section = .devices },
                    onDismiss: { dismissedAdapter = true }
                )
            }
            if accessibilityMissing, !dismissedAccessibility {
                ShellBanner(
                    systemImage: "lock.shield",
                    message: "Accessibility permission is not granted, so MagicForge cannot perform actions or observe clicks and scrolling.",
                    actionTitle: "Show Permissions",
                    action: { navigation.section = .permissions },
                    onDismiss: { dismissedAccessibility = true }
                )
            }
        }
    }

    private var adapterProblem: String? {
        guard model.isRunning else { return nil }
        return model.adapterStatus.state.shellUnavailableReason
    }

    private var accessibilityMissing: Bool {
        guard model.isRunning, let status = model.permissions[.accessibility] else { return false }
        return status == .denied || status == .notDetermined
    }
}

@MainActor
struct ShellBanner: View {
    let systemImage: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(actionTitle, action: action)
                    .controlSize(.small)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Dismiss until next launch")
                .accessibilityLabel("Dismiss warning")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.14))
            Divider()
        }
    }
}
