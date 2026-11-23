import Foundation

// Display metadata for actions. Symbol names are SF Symbols that ship with macOS 14.

public enum ActionCategory: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case system, window, app, keyboard, mouse, text, script, workflow, radialMenu, ai, control

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .window: return "Windows"
        case .app: return "Apps & Files"
        case .keyboard: return "Keyboard Shortcuts"
        case .mouse: return "Mouse"
        case .text: return "Text & Clipboard"
        case .script: return "Scripts"
        case .workflow: return "Workflows"
        case .radialMenu: return "Radial Menus"
        case .ai: return "AI Prompts"
        case .control: return "MagicForge"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: return "gearshape"
        case .window: return "macwindow"
        case .app: return "app"
        case .keyboard: return "keyboard"
        case .mouse: return "cursorarrow.click"
        case .text: return "doc.on.clipboard"
        case .script: return "terminal"
        case .workflow: return "flowchart"
        case .radialMenu: return "circle.grid.cross"
        case .ai: return "sparkles"
        case .control: return "slider.horizontal.3"
        }
    }
}

public extension SystemAction {
    var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .spotlight: return "Spotlight"
        case .notificationCenter: return "Notification Center"
        case .lockScreen: return "Lock Screen"
        case .screenshotFull: return "Screenshot: Entire Screen"
        case .screenshotSelection: return "Screenshot: Selection"
        case .screenshotWindow: return "Screenshot: Window"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        }
    }

    var symbolName: String {
        switch self {
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "square.stack.3d.up"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .spotlight: return "magnifyingglass"
        case .notificationCenter: return "bell"
        case .lockScreen: return "lock"
        case .screenshotFull: return "camera.viewfinder"
        case .screenshotSelection: return "crop"
        case .screenshotWindow: return "macwindow"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        }
    }
}

public extension WindowAction {
    var displayName: String {
        switch self {
        case .snapLeft: return "Snap Window Left"
        case .snapRight: return "Snap Window Right"
        case .snapTop: return "Snap Window Top"
        case .snapBottom: return "Snap Window Bottom"
        case .maximize: return "Maximize Window"
        case .center: return "Center Window"
        case .restorePreviousFrame: return "Restore Window Size"
        case .moveToNextDisplay: return "Move Window to Next Display"
        case .minimize: return "Minimize Window"
        case .close: return "Close Window"
        case .resize(let fraction):
            guard fraction.isFinite, fraction != 0 else { return "Resize Window" }
            let percent = Int((abs(fraction) * 100).rounded())
            return fraction > 0 ? "Grow Window by \(percent)%" : "Shrink Window by \(percent)%"
        }
    }

    var symbolName: String {
        switch self {
        case .snapLeft: return "rectangle.lefthalf.filled"
        case .snapRight: return "rectangle.righthalf.filled"
        case .snapTop: return "rectangle.tophalf.filled"
        case .snapBottom: return "rectangle.bottomhalf.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .restorePreviousFrame: return "arrow.uturn.backward"
        case .moveToNextDisplay: return "display.2"
        case .minimize: return "minus.rectangle"
        case .close: return "xmark.rectangle"
        case .resize(let fraction): return fraction < 0 ? "minus.magnifyingglass" : "plus.magnifyingglass"
        }
    }
}

public extension AppAction {
    /// Includes the parameter when it is set, e.g. "Launch com.apple.Safari".
    var displayName: String {
        switch self {
        case .launch(let bundleID): return bundleID.isEmpty ? "Launch App" : "Launch \(bundleID)"
        case .switchTo(let bundleID): return bundleID.isEmpty ? "Switch to App" : "Switch to \(bundleID)"
        case .hideFrontmost: return "Hide Frontmost App"
        case .quitFrontmost: return "Quit Frontmost App"
        case .openURL(let url): return url.isEmpty ? "Open URL" : "Open \(ActionText.shortened(url))"
        case .openPath(let path): return path.isEmpty ? "Open File or Folder" : "Open \(ActionText.shortened(path))"
        }
    }

    var symbolName: String {
        switch self {
        case .launch: return "arrow.up.forward.app"
        case .switchTo: return "arrow.left.arrow.right"
        case .hideFrontmost: return "eye.slash"
        case .quitFrontmost: return "xmark.circle"
        case .openURL: return "link"
        case .openPath: return "folder"
        }
    }
}

public extension MouseAction {
    var displayName: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .toggleDrag: return "Toggle Drag Lock"
        case .scroll(let dx, let dy):
            if dx == 0, dy > 0 { return "Scroll Up" }
            if dx == 0, dy < 0 { return "Scroll Down" }
            if dy == 0, dx > 0 { return "Scroll Right" }
            if dy == 0, dx < 0 { return "Scroll Left" }
            return "Scroll"
        }
    }

    var symbolName: String {
        switch self {
        case .leftClick: return "cursorarrow.click"
        case .rightClick: return "cursorarrow.click.2"
        case .middleClick: return "computermouse"
        case .doubleClick: return "cursorarrow.rays"
        case .toggleDrag: return "hand.draw"
        case .scroll(let dx, let dy):
            if dx == 0, dy > 0 { return "arrow.up" }
            if dx == 0, dy < 0 { return "arrow.down" }
            if dy == 0, dx > 0 { return "arrow.right" }
            if dy == 0, dx < 0 { return "arrow.left" }
            return "scroll"
        }
    }
}

public extension TextAction {
    /// Never includes the stored text itself, only that there is some.
    var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .copyText: return "Copy Text to Clipboard"
        case .pasteText: return "Paste Text"
        }
    }

    var symbolName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .copyText: return "text.badge.plus"
        case .pasteText: return "text.cursor"
        }
    }
}

public extension ScriptAction {
    /// Shortcut names are shown; script and command bodies never are.
    var displayName: String {
        switch self {
        case .appleScript: return "Run AppleScript"
        case .shell: return "Run Shell Command"
        case .shortcut(let name): return name.isEmpty ? "Run Shortcut" : "Run Shortcut “\(ActionText.shortened(name))”"
        }
    }

    var symbolName: String {
        switch self {
        case .appleScript: return "applescript"
        case .shell: return "terminal"
        case .shortcut: return "square.stack.3d.up"
        }
    }

    /// The user-authored text of the script (source, command or Shortcut name).
    var body: String {
        switch self {
        case .appleScript(let source): return source
        case .shell(let command): return command
        case .shortcut(let name): return name
        }
    }
}

public extension ControlAction {
    var displayName: String {
        switch self {
        case .toggleGesturesPaused: return "Pause or Resume Gestures"
        case .openDashboard: return "Open MagicForge"
        case .nextProfile: return "Switch to Next Profile"
        case .clearProfileOverride: return "Return to Automatic Profile"
        case .cancelWorkflows: return "Cancel Running Workflows"
        }
    }

    var symbolName: String {
        switch self {
        case .toggleGesturesPaused: return "pause.circle"
        case .openDashboard: return "macwindow"
        case .nextProfile: return "person.2"
        case .clearProfileOverride: return "arrow.uturn.backward"
        case .cancelWorkflows: return "stop.circle"
        }
    }
}

public extension Action {
    /// Name that needs no configuration lookup. Workflows, radial menus and AI prompts are
    /// named generically; use `displayName(in:)` to resolve their titles.
    var displayName: String {
        switch self {
        case .none: return "No Action"
        case .system(let action): return action.displayName
        case .window(let action): return action.displayName
        case .app(let action): return action.displayName
        case .keyboard(let combo): return "Press \(combo.label.isEmpty ? combo.displayString : combo.label)"
        case .mouse(let action): return action.displayName
        case .text(let action): return action.displayName
        case .script(let action): return action.displayName
        case .workflow: return "Run Workflow"
        case .radialMenu: return "Show Radial Menu"
        case .ai: return "Run AI Prompt"
        case .control(let action): return action.displayName
        }
    }

    /// Like `displayName`, with workflow / radial menu / prompt template names resolved.
    /// References to items that no longer exist are labelled "(missing)".
    func displayName(in configuration: Configuration) -> String {
        switch self {
        case .workflow(let id):
            guard let workflow = configuration.workflows.first(where: { $0.id == id }) else { return "Run Workflow (missing)" }
            return "Run Workflow “\(workflow.name)”"
        case .radialMenu(let id):
            guard let menu = configuration.radialMenus.first(where: { $0.id == id }) else { return "Show Radial Menu (missing)" }
            return "Show Radial Menu “\(menu.name)”"
        case .ai(let templateID):
            guard let template = configuration.ai.templates.first(where: { $0.id == templateID }) else {
                return "Run AI Prompt (missing)"
            }
            return "AI: \(template.name)"
        default:
            return displayName
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "nosign"
        case .system(let action): return action.symbolName
        case .window(let action): return action.symbolName
        case .app(let action): return action.symbolName
        case .keyboard: return "keyboard"
        case .mouse(let action): return action.symbolName
        case .text(let action): return action.symbolName
        case .script(let action): return action.symbolName
        case .workflow: return "flowchart"
        case .radialMenu: return "circle.grid.cross"
        case .ai: return "sparkles"
        case .control(let action): return action.symbolName
        }
    }

    /// `.none` has no natural category and is filed under `.control`.
    var category: ActionCategory {
        switch self {
        case .none, .control: return .control
        case .system: return .system
        case .window: return .window
        case .app: return .app
        case .keyboard: return .keyboard
        case .mouse: return .mouse
        case .text: return .text
        case .script: return .script
        case .workflow: return .workflow
        case .radialMenu: return .radialMenu
        case .ai: return .ai
        }
    }
}

public extension PermissionKind {
    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .automation: return "Automation"
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "keyboard"
        case .automation: return "gearshape.2"
        }
    }

    /// Why MagicForge asks for the permission.
    var summary: String {
        switch self {
        case .accessibility:
            return "Needed to send keyboard shortcuts and clicks, move windows and adjust scrolling."
        case .inputMonitoring:
            return "Needed only when gestures must observe input from other apps."
        case .automation:
            return "Needed to run AppleScript actions that control other apps."
        }
    }
}

public extension PermissionStatus {
    var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not Granted"
        case .notDetermined: return "Not Requested"
        case .notRequired: return "Not Required"
        }
    }
}

enum ActionText {
    /// Middle-truncates long parameters so names stay on one line.
    static func shortened(_ text: String, limit: Int = 40) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard singleLine.count > limit else { return singleLine }
        let head = singleLine.prefix(limit / 2)
        let tail = singleLine.suffix(limit / 2 - 1)
        return head + "…" + tail
    }
}
