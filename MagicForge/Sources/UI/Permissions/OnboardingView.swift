import SwiftUI
import MFCore
import MFEngine

/// First-run sheet: what the app does (with the private-API disclosure), permissions, done.
@MainActor
struct ShellOnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    @State private var step: Int = 0
    private let lastStep: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step \(step + 1) of \(lastStep + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            controls
        }
        .padding(24)
        .frame(width: 600, height: 520)
        .interactiveDismissDisabled(true)
        .shellRefreshPermissionsOnActivation(model)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: OnboardingWelcomeStep()
        case 1: OnboardingPermissionsStep()
        default: OnboardingDoneStep()
        }
    }

    private var controls: some View {
        HStack {
            Button("Skip Setup") { finish(openSection: nil) }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            if step < lastStep {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Open Gestures") { finish(openSection: .gestures) }
                Button("Done") { finish(openSection: nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish(openSection: SidebarSection?) {
        model.update { configuration in
            configuration.settings.hasCompletedOnboarding = true
        }
        if let openSection { navigation.section = openSection }
    }
}

@MainActor
struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Welcome to MagicForge", systemImage: "magicmouse.fill")
                .font(.title2)
                .fontWeight(.semibold)
            Text("MagicForge turns taps, swipes, pinches and other touches on your Magic Mouse into actions: shortcuts, window management, workflows, a radial menu and more. Profiles switch automatically with the app you are using.")
                .fixedSize(horizontal: false, vertical: true)
            MFCard("How touch data is read", systemImage: "info.circle") {
                Text("macOS offers no public way to read finger positions from a Magic Mouse. MagicForge uses Apple's private MultitouchSupport framework for this. It is unsupported by Apple and may stop working after a macOS update; if that happens MagicForge tells you and only offers fallback triggers (Control-Option with a click or scroll). You can turn the private adapter off at any time in Settings › Privacy.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MFCard("Privacy", systemImage: "hand.raised") {
                Text("Touch data is processed on this Mac and never stored or sent anywhere. MagicForge collects no analytics or telemetry. AI features are off until you set them up, and nothing is sent without your explicit action.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct OnboardingPermissionsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Grant only what you need. You can change this later in the Permissions section.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(PermissionKind.allCases, id: \.self) { kind in
                        PermissionsKindCard(kind: kind)
                    }
                }
            }
        }
    }
}

@MainActor
struct OnboardingDoneStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("You're set", systemImage: "checkmark.circle")
                .font(.title2)
                .fontWeight(.semibold)
            Text("MagicForge keeps running in the menu bar when you close this window. Open Gestures to see and change what each touch does, or try the Touch Lab to watch your fingers live.")
                .fixedSize(horizontal: false, vertical: true)
            MFCard("Current status", systemImage: "list.bullet") {
                MFKeyValueRow("Mouse", value: model.connectedDevice?.name ?? "No Magic Mouse connected")
                MFKeyValueRow("Touch input", value: model.adapterStatus.state.shellLabel)
                MFKeyValueRow("Accessibility", value: (model.permissions[.accessibility] ?? .notDetermined).shellLabel)
            }
            if let reason = model.adapterStatus.state.shellUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
