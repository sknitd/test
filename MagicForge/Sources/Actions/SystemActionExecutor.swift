import AppKit
import Foundation
import MFCore

/// Executes `SystemAction`s. See docs/PERMISSIONS.md for which of them need Accessibility.
struct SystemActionExecutor: Sendable {
    private let keyboard = KeyboardExecutor()
    private let mediaKeys = MediaKeyExecutor()

    // MARK: System applications

    private static let missionControlApp = "/System/Applications/Mission Control.app"
    private static let missionControlExecutable = missionControlApp + "/Contents/MacOS/Mission Control"
    private static let launchpadApp = "/System/Applications/Launchpad.app"
    /// macOS 26 replaced Launchpad with the "Apps" application.
    private static let appsApp = "/System/Applications/Apps.app"

    static var hasMissionControl: Bool {
        FileManager.default.isExecutableFile(atPath: missionControlExecutable)
    }

    /// The app-launcher application present on this macOS version, if any.
    static var launcherApp: URL? {
        for path in [launchpadApp, appsApp] where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Reason an action cannot work on this Mac, or nil when it can (permissions aside).
    static func unavailableReason(for action: SystemAction) -> String? {
        switch action {
        case .missionControl, .appExpose, .showDesktop:
            return hasMissionControl ? nil : "Mission Control.app was not found on this version of macOS."
        case .launchpad:
            return launcherApp == nil ? "Launchpad is not part of this version of macOS." : nil
        case .notificationCenter:
            return "macOS offers no public way to open Notification Center, and it has no default keyboard shortcut."
        default:
            return nil
        }
    }

    /// Whether the action is carried out by posting synthetic events (needs Accessibility).
    static func postsEvents(_ action: SystemAction) -> Bool {
        switch action {
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter: return false
        default: return true
        }
    }

    // MARK: Execution

    func perform(_ action: SystemAction) async throws {
        if let reason = SystemActionExecutor.unavailableReason(for: action) {
            throw ActionError.unsupported(reason)
        }
        switch action {
        case .missionControl: try await runMissionControl(argument: nil)
        // Mission Control.app takes a mode argument: 1 = show desktop, 2 = application windows.
        case .showDesktop: try await runMissionControl(argument: "1")
        case .appExpose: try await runMissionControl(argument: "2")
        case .launchpad: try await openLauncher()
        case .notificationCenter:
            throw ActionError.unsupported("Notification Center cannot be opened programmatically.")

        // Default macOS shortcuts; they follow System Settings › Keyboard › Keyboard Shortcuts.
        case .spotlight:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.space, command: true))
        case .lockScreen:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.q, command: true, control: true))
        case .screenshotFull:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.three, command: true, shift: true))
        case .screenshotSelection:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.four, command: true, shift: true))
        case .screenshotWindow:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.four, command: true, shift: true))
            // The crosshair needs a moment to appear before Space switches it to window mode.
            await SyntheticEvents.gap(0.4)
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.space))

        case .volumeUp: try await mediaKeys.press(.soundUp)
        case .volumeDown: try await mediaKeys.press(.soundDown)
        case .mute: try await mediaKeys.press(.mute)
        case .brightnessUp: try await mediaKeys.press(.brightnessUp)
        case .brightnessDown: try await mediaKeys.press(.brightnessDown)
        case .playPause: try await mediaKeys.press(.play)
        case .nextTrack: try await mediaKeys.press(.next)
        case .previousTrack: try await mediaKeys.press(.previous)
        }
    }

    private func runMissionControl(argument: String?) async throws {
        let executable = URL(fileURLWithPath: SystemActionExecutor.missionControlExecutable)
        let arguments: [String] = argument.map { [$0] } ?? []
        let output = try await ProcessRunner.run(executable: executable, arguments: arguments,
                                                 environment: ProcessRunner.minimalEnvironment(), timeout: 5)
        guard output.exitCode == 0 else {
            throw ActionError.failed("Mission Control exited with status \(output.exitCode).")
        }
    }

    private func openLauncher() async throws {
        guard let url = SystemActionExecutor.launcherApp else {
            throw ActionError.unsupported("Launchpad is not part of this version of macOS.")
        }
        try await AppExecutor.openApplication(at: url)
    }
}
