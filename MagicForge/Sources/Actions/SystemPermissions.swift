import AppKit
import ApplicationServices
import Foundation
import IOKit
import IOKit.hidsystem
import MFCore
import MFUtilities

/// Reads and requests the privacy (TCC) permissions MagicForge uses.
///
/// - `status(of:)` never prompts.
/// - `request(_:)` shows the system prompt at most once per kind per launch.
///
/// Thread-safe: the only mutable state is the set of already-requested kinds, guarded by a lock.
public final class SystemPermissions: PermissionsProviding, @unchecked Sendable {
    private let requested = Locked<Set<PermissionKind>>([])
    private let log = Log("permissions")

    public init() {}

    public func status(of kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            if AXIsProcessTrusted() { return .granted }
            // The Accessibility API cannot tell "never asked" from "refused". Report
            // `.denied` only once we know the user has seen the prompt during this launch.
            return requested.current.contains(.accessibility) ? .denied : .notDetermined
        case .inputMonitoring:
            let access: IOHIDAccessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            if access == kIOHIDAccessTypeGranted { return .granted }
            if access == kIOHIDAccessTypeDenied { return .denied }
            return .notDetermined
        case .automation:
            // Automation consent is stored per target application and can only be queried for a
            // specific target (which may launch it or prompt). There is no global answer, so
            // this is reported as not determined; AppleScript actions surface a precise
            // `permissionDenied(.automation)` error when macOS refuses an Apple Event.
            return .notDetermined
        }
    }

    public func request(_ kind: PermissionKind) {
        let isFirstRequest: Bool = requested.withLock { $0.insert(kind).inserted }
        guard isFirstRequest else { return }
        switch kind {
        case .accessibility:
            guard !AXIsProcessTrusted() else { return }
            let promptKey: String = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options: CFDictionary = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            log.info("Requested Accessibility permission")
        case .inputMonitoring:
            let granted: Bool = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            log.info("Requested Input Monitoring permission (granted: \(granted))")
        case .automation:
            // Nothing to do: macOS shows the Automation prompt itself the first time an
            // AppleScript action sends an Apple Event to a given application.
            log.info("Automation permission is requested by macOS on first use per target app")
        }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        let anchor: String
        switch kind {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .automation: anchor = "Privacy_Automation"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        if !NSWorkspace.shared.open(url) {
            log.error("Could not open System Settings for \(kind.rawValue)")
        }
    }
}
