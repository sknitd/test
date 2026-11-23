import Foundation
import MFCore

// Payload-free mirrors of the action enums so they can drive pickers. No UI types in this file.

enum WindowActionChoice: String, CaseIterable, Identifiable {
    case snapLeft, snapRight, snapTop, snapBottom, maximize, center, restorePreviousFrame
    case moveToNextDisplay, minimize, close, resize

    var id: String { rawValue }

    init(_ action: WindowAction) {
        switch action {
        case .snapLeft: self = .snapLeft
        case .snapRight: self = .snapRight
        case .snapTop: self = .snapTop
        case .snapBottom: self = .snapBottom
        case .maximize: self = .maximize
        case .center: self = .center
        case .restorePreviousFrame: self = .restorePreviousFrame
        case .moveToNextDisplay: self = .moveToNextDisplay
        case .minimize: self = .minimize
        case .close: self = .close
        case .resize: self = .resize
        }
    }

    func action(resizeFraction: Double) -> WindowAction {
        switch self {
        case .snapLeft: return .snapLeft
        case .snapRight: return .snapRight
        case .snapTop: return .snapTop
        case .snapBottom: return .snapBottom
        case .maximize: return .maximize
        case .center: return .center
        case .restorePreviousFrame: return .restorePreviousFrame
        case .moveToNextDisplay: return .moveToNextDisplay
        case .minimize: return .minimize
        case .close: return .close
        case .resize: return .resize(byFraction: resizeFraction)
        }
    }

    var title: String {
        if self == .resize { return "Grow or Shrink" }
        return action(resizeFraction: 0.1).displayName
    }
}

enum AppActionChoice: String, CaseIterable, Identifiable {
    case launch, switchTo, hideFrontmost, quitFrontmost, openURL, openPath

    var id: String { rawValue }

    init(_ action: AppAction) {
        switch action {
        case .launch: self = .launch
        case .switchTo: self = .switchTo
        case .hideFrontmost: self = .hideFrontmost
        case .quitFrontmost: self = .quitFrontmost
        case .openURL: self = .openURL
        case .openPath: self = .openPath
        }
    }

    var title: String {
        switch self {
        case .launch: return "Launch App"
        case .switchTo: return "Switch to App"
        case .hideFrontmost: return "Hide Frontmost App"
        case .quitFrontmost: return "Quit Frontmost App"
        case .openURL: return "Open URL"
        case .openPath: return "Open File or Folder"
        }
    }

    var usesBundleID: Bool { self == .launch || self == .switchTo }

    /// Builds the action, keeping the bundle identifier when switching between the two app kinds.
    func action(replacing previous: AppAction) -> AppAction {
        var bundleID: String = ""
        switch previous {
        case .launch(let id), .switchTo(let id): bundleID = id
        default: break
        }
        switch self {
        case .launch: return .launch(bundleID: bundleID)
        case .switchTo: return .switchTo(bundleID: bundleID)
        case .hideFrontmost: return .hideFrontmost
        case .quitFrontmost: return .quitFrontmost
        case .openURL: return .openURL("https://")
        case .openPath: return .openPath("~/")
        }
    }
}

enum MouseActionChoice: String, CaseIterable, Identifiable {
    case leftClick, rightClick, middleClick, doubleClick, toggleDrag, scroll

    var id: String { rawValue }

    init(_ action: MouseAction) {
        switch action {
        case .leftClick: self = .leftClick
        case .rightClick: self = .rightClick
        case .middleClick: self = .middleClick
        case .doubleClick: self = .doubleClick
        case .toggleDrag: self = .toggleDrag
        case .scroll: self = .scroll
        }
    }

    var title: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .toggleDrag: return "Toggle Drag Lock"
        case .scroll: return "Scroll by Lines"
        }
    }

    var action: MouseAction {
        switch self {
        case .leftClick: return .leftClick
        case .rightClick: return .rightClick
        case .middleClick: return .middleClick
        case .doubleClick: return .doubleClick
        case .toggleDrag: return .toggleDrag
        case .scroll: return .scroll(dx: 0, dy: -3)
        }
    }
}

enum TextActionChoice: String, CaseIterable, Identifiable {
    case copy, paste, copyText, pasteText

    var id: String { rawValue }

    init(_ action: TextAction) {
        switch action {
        case .copy: self = .copy
        case .paste: self = .paste
        case .copyText: self = .copyText
        case .pasteText: self = .pasteText
        }
    }

    var title: String {
        switch self {
        case .copy: return "Copy Selection"
        case .paste: return "Paste"
        case .copyText: return "Copy Fixed Text to Clipboard"
        case .pasteText: return "Paste Fixed Text"
        }
    }

    /// Builds the action, keeping the text when switching between the two fixed-text kinds.
    func action(replacing previous: TextAction) -> TextAction {
        var text: String = ""
        switch previous {
        case .copyText(let value), .pasteText(let value): text = value
        default: break
        }
        switch self {
        case .copy: return .copy
        case .paste: return .paste
        case .copyText: return .copyText(text)
        case .pasteText: return .pasteText(text)
        }
    }
}

enum ScriptActionChoice: String, CaseIterable, Identifiable {
    case shortcut, appleScript, shell

    var id: String { rawValue }

    init(_ action: ScriptAction) {
        switch action {
        case .shortcut: self = .shortcut
        case .appleScript: self = .appleScript
        case .shell: self = .shell
        }
    }

    var title: String {
        switch self {
        case .shortcut: return "Run Shortcut"
        case .appleScript: return "AppleScript"
        case .shell: return "Shell Command"
        }
    }

    var symbolName: String {
        switch self {
        case .shortcut: return "square.2.layers.3d"
        case .appleScript: return "applescript"
        case .shell: return "terminal"
        }
    }

    /// The text the user edits (script source, command line or Shortcut name).
    static func body(of action: ScriptAction) -> String {
        switch action {
        case .shortcut(let name): return name
        case .appleScript(let source): return source
        case .shell(let command): return command
        }
    }

    func action(body: String) -> ScriptAction {
        switch self {
        case .shortcut: return .shortcut(name: body)
        case .appleScript: return .appleScript(source: body)
        case .shell: return .shell(command: body)
        }
    }
}
