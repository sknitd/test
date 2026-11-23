import SwiftUI
import AppKit
import ServiceManagement
import MFCore
import MFEngine
import MFUtilities

/// Launch at login (SMAppService), start minimized and the menu bar icon.
@MainActor
struct SettingsStartupSection: View {
    @Environment(AppModel.self) private var model

    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?

    private let log = Log("ui.settings")

    var body: some View {
        let bindings = SettingsBinding(model: model)
        Section("Startup") {
            Toggle("Launch at login", isOn: loginBinding)
                .disabled(!isBundledApp)
                .onAppear { refreshLoginStatus() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    refreshLoginStatus()
                }
            Text(loginStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
            if isBundledApp, loginStatus == .requiresApproval {
                Button("Open Login Items Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            Toggle("Start minimized (no window at launch)", isOn: bindings.bool(\.startMinimized))
            Toggle("Show menu bar icon", isOn: bindings.bool(\.showMenuBarIcon))
            if !model.configuration.settings.showMenuBarIcon {
                Text("Without the menu bar icon, click MagicForge in the Dock to open this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Login items can only be registered for a real .app bundle (not `swift run` builds).
    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var loginBinding: Binding<Bool> {
        let isEnabled: Bool = loginStatus == .enabled
        return Binding<Bool>(
            get: { isEnabled },
            set: { newValue in setLaunchAtLogin(newValue) }
        )
    }

    private var loginStatusText: String {
        guard isBundledApp else {
            return "Unavailable: MagicForge is not running from an app bundle, so macOS cannot register it as a login item."
        }
        switch loginStatus {
        case .enabled:
            return "Registered. MagicForge opens when you log in."
        case .notRegistered:
            return "Not registered."
        case .requiresApproval:
            return "Waiting for your approval in System Settings › General › Login Items."
        case .notFound:
            return "macOS could not find the app to register. Move MagicForge to the Applications folder and try again."
        @unknown default:
            return "Unknown login item status."
        }
    }

    private func refreshLoginStatus() {
        guard isBundledApp else { return }
        loginStatus = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard isBundledApp else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "macOS refused the change: \(error.localizedDescription)"
            log.error("Launch at login change failed: \(error.localizedDescription)")
        }
        refreshLoginStatus()
        let registered: Bool = loginStatus == .enabled || loginStatus == .requiresApproval
        model.update { configuration in
            configuration.settings.launchAtLogin = registered
        }
    }
}
