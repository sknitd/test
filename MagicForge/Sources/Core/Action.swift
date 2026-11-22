import Foundation

public enum SystemAction: String, Codable, Sendable, CaseIterable, Hashable {
    case missionControl, appExpose, showDesktop, launchpad, spotlight, notificationCenter, lockScreen
    case screenshotFull, screenshotSelection, screenshotWindow
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    case playPause, nextTrack, previousTrack
}

public enum WindowAction: Codable, Sendable, Hashable {
    case snapLeft, snapRight, snapTop, snapBottom, maximize, center, restorePreviousFrame
    case moveToNextDisplay, minimize, close
    /// Grow (positive) or shrink (negative) the focused window by this fraction of the screen, keeping it centred.
    case resize(byFraction: Double)
}

public enum AppAction: Codable, Sendable, Hashable {
    case launch(bundleID: String)
    case switchTo(bundleID: String)
    case hideFrontmost, quitFrontmost
    case openURL(String)
    /// File or folder path; `~` is expanded.
    case openPath(String)
}

/// Keyboard shortcut. `keyCode` is a macOS virtual key code (kVK_*).
public struct KeyCombo: Codable, Sendable, Hashable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public var function: Bool
    /// Human readable label captured when the shortcut was recorded, e.g. "⌘⇧P".
    public var label: String

    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false,
                shift: Bool = false, function: Bool = false, label: String = "") {
        self.keyCode = keyCode; self.command = command; self.option = option; self.control = control
        self.shift = shift; self.function = function; self.label = label
    }
}

public enum MouseAction: Codable, Sendable, Hashable {
    case leftClick, rightClick, middleClick, doubleClick
    /// Toggles a held left button so the pointer drags until triggered again.
    case toggleDrag
    /// Scroll by lines (positive dy = up, positive dx = right).
    case scroll(dx: Double, dy: Double)
}

public enum TextAction: Codable, Sendable, Hashable {
    case copy, paste
    /// Puts the string on the clipboard.
    case copyText(String)
    /// Puts the string on the clipboard and pastes it into the frontmost app.
    case pasteText(String)
}

/// Actions that run user-authored code. They require explicit trust (see `ScriptTrust`).
public enum ScriptAction: Codable, Sendable, Hashable {
    case appleScript(source: String)
    case shell(command: String)
    /// Runs a macOS Shortcut by name.
    case shortcut(name: String)

    /// Text whose hash is recorded when the user approves this script.
    public var trustPayload: String {
        switch self {
        case .appleScript(let source): return "applescript:" + source
        case .shell(let command): return "shell:" + command
        case .shortcut(let name): return "shortcut:" + name
        }
    }
}

public enum ControlAction: String, Codable, Sendable, CaseIterable, Hashable {
    case toggleGesturesPaused, openDashboard, nextProfile, clearProfileOverride, cancelWorkflows
}

/// Everything a gesture, radial-menu item or workflow step can do.
/// `system/window/app/keyboard/mouse/text/script` are leaf actions executed by `ActionPerforming`
/// (MFActions on macOS). `workflow/radialMenu/ai/control` are routed by the engine.
public enum Action: Codable, Sendable, Hashable {
    case none
    case system(SystemAction)
    case window(WindowAction)
    case app(AppAction)
    case keyboard(KeyCombo)
    case mouse(MouseAction)
    case text(TextAction)
    case script(ScriptAction)
    case workflow(id: UUID)
    case radialMenu(id: UUID)
    case ai(templateID: UUID)
    case control(ControlAction)

    public var isLeaf: Bool {
        switch self {
        case .system, .window, .app, .keyboard, .mouse, .text, .script: return true
        case .none, .workflow, .radialMenu, .ai, .control: return false
        }
    }

    /// Non-nil for actions that execute user-authored code.
    public var script: ScriptAction? {
        if case .script(let script) = self { return script }
        return nil
    }
}

public enum PermissionKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Posting synthetic events, moving windows, active event taps.
    case accessibility
    /// Listen-only observation of input from other apps (only used when the feasibility probe shows it is needed).
    case inputMonitoring
    /// Apple Events to other apps (AppleScript actions).
    case automation
}

public enum PermissionStatus: String, Codable, Sendable { case granted, denied, notDetermined, notRequired }

public enum ActionError: Error, Equatable, Sendable {
    case permissionDenied(PermissionKind)
    case unsupported(String)
    case failed(String)
    case timedOut
    case cancelled
    /// A script action that the user has not approved (e.g. from an imported profile).
    case untrusted
    case notFound(String)
}

public enum ActionSource: String, Codable, Sendable { case gesture, radialMenu, workflow, manualTest, menuBar }

public struct ActionContext: Sendable {
    public var source: ActionSource
    public var frontmostBundleID: String?
    public var gesture: GestureEvent?
    public init(source: ActionSource, frontmostBundleID: String? = nil, gesture: GestureEvent? = nil) {
        self.source = source; self.frontmostBundleID = frontmostBundleID; self.gesture = gesture
    }
}

/// Executes leaf actions against the operating system. Implementations must throw
/// `ActionError.unsupported` for anything they cannot do rather than silently succeeding, and
/// `ActionError.permissionDenied` without prompting when a permission is missing.
public protocol ActionPerforming: Sendable {
    func perform(_ action: Action, context: ActionContext) async throws
    /// Whether this action can work on the current machine / OS version, with the reason when not.
    func availability(of action: Action) -> ActionAvailability
}

public enum ActionAvailability: Equatable, Sendable {
    case available
    case needsPermission(PermissionKind)
    case unavailable(reason: String)
}
