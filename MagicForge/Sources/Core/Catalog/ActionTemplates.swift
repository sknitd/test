import Foundation

/// A ready-made action the user can pick from the library and then customize.
public struct ActionTemplate: Identifiable, Sendable, Hashable {
    /// Stable identifier such as "keyboard.newTab".
    public var id: String
    public var name: String
    public var symbolName: String
    public var category: ActionCategory
    public var action: Action

    public init(id: String, name: String, symbolName: String, category: ActionCategory, action: Action) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.category = category; self.action = action
    }
}

/// The built-in action library. Workflows, radial menus and AI prompts are user-created, so
/// they have no templates here: list them from `Configuration`.
public enum ActionCatalog {
    public static let templates: [ActionTemplate] =
        systemTemplates + windowTemplates + appTemplates + keyboardTemplates + mouseTemplates + textTemplates
            + scriptTemplates + controlTemplates

    public static func templates(in category: ActionCategory) -> [ActionTemplate] {
        templates.filter { $0.category == category }
    }

    public static func template(id: String) -> ActionTemplate? { templates.first { $0.id == id } }

    /// Fraction used by the grow / shrink window templates.
    public static let resizeStep: Double = 0.10

    // MARK: Sections

    private static let systemTemplates: [ActionTemplate] = SystemAction.allCases.map { action in
        ActionTemplate(id: "system.\(action.rawValue)", name: action.displayName, symbolName: action.symbolName,
                       category: .system, action: .system(action))
    }

    private static let windowTemplates: [ActionTemplate] = {
        let actions: [(String, WindowAction)] = [
            ("snapLeft", .snapLeft), ("snapRight", .snapRight), ("snapTop", .snapTop), ("snapBottom", .snapBottom),
            ("maximize", .maximize), ("center", .center), ("restorePreviousFrame", .restorePreviousFrame),
            ("moveToNextDisplay", .moveToNextDisplay), ("minimize", .minimize), ("close", .close),
            ("grow", .resize(byFraction: resizeStep)), ("shrink", .resize(byFraction: -resizeStep)),
        ]
        return actions.map { key, action in
            ActionTemplate(id: "window.\(key)", name: action.displayName, symbolName: action.symbolName,
                           category: .window, action: .window(action))
        }
    }()

    private static let appTemplates: [ActionTemplate] = {
        let actions: [(String, AppAction)] = [
            ("launch", .launch(bundleID: "")), ("switchTo", .switchTo(bundleID: "")),
            ("hideFrontmost", .hideFrontmost), ("quitFrontmost", .quitFrontmost),
            ("openURL", .openURL("")), ("openPath", .openPath("")),
        ]
        return actions.map { key, action in
            ActionTemplate(id: "app.\(key)", name: action.displayName, symbolName: action.symbolName,
                           category: .app, action: .app(action))
        }
    }()

    private static func shortcut(_ key: String, _ name: String, _ symbol: String, _ keyCode: UInt16,
                                 command: Bool = false, option: Bool = false, control: Bool = false,
                                 shift: Bool = false) -> ActionTemplate {
        var combo = KeyCombo(keyCode: keyCode, command: command, option: option, control: control, shift: shift)
        combo.label = combo.displayString
        return ActionTemplate(id: "keyboard.\(key)", name: "\(name) (\(combo.displayString))", symbolName: symbol,
                              category: .keyboard, action: .keyboard(combo))
    }

    private static let keyboardTemplates: [ActionTemplate] = [
        shortcut("back", "Back", "chevron.left", KeyCodes.leftBracket, command: true),
        shortcut("forward", "Forward", "chevron.right", KeyCodes.rightBracket, command: true),
        shortcut("newTab", "New Tab", "plus.square", KeyCodes.t, command: true),
        shortcut("closeTab", "Close Tab", "xmark.square", KeyCodes.w, command: true),
        shortcut("reopenTab", "Reopen Closed Tab", "arrow.uturn.backward.square", KeyCodes.t, command: true, shift: true),
        shortcut("nextTab", "Next Tab", "arrow.right.square", KeyCodes.tab, control: true),
        shortcut("previousTab", "Previous Tab", "arrow.left.square", KeyCodes.tab, control: true, shift: true),
        shortcut("newWindow", "New Window", "macwindow.badge.plus", KeyCodes.n, command: true),
        shortcut("closeWindow", "Close Window", "xmark.rectangle", KeyCodes.w, command: true, shift: true),
        shortcut("reload", "Reload", "arrow.clockwise", KeyCodes.r, command: true),
        shortcut("zoomIn", "Zoom In", "plus.magnifyingglass", KeyCodes.equal, command: true),
        shortcut("zoomOut", "Zoom Out", "minus.magnifyingglass", KeyCodes.minus, command: true),
        shortcut("actualSize", "Actual Size", "1.magnifyingglass", KeyCodes.zero, command: true),
        shortcut("copy", "Copy", "doc.on.doc", KeyCodes.c, command: true),
        shortcut("paste", "Paste", "doc.on.clipboard", KeyCodes.v, command: true),
        shortcut("cut", "Cut", "scissors", KeyCodes.x, command: true),
        shortcut("undo", "Undo", "arrow.uturn.backward", KeyCodes.z, command: true),
        shortcut("redo", "Redo", "arrow.uturn.forward", KeyCodes.z, command: true, shift: true),
        shortcut("selectAll", "Select All", "selection.pin.in.out", KeyCodes.a, command: true),
        shortcut("save", "Save", "square.and.arrow.down", KeyCodes.s, command: true),
        shortcut("find", "Find", "magnifyingglass", KeyCodes.f, command: true),
        shortcut("appSwitcher", "App Switcher", "square.on.square", KeyCodes.tab, command: true),
        shortcut("nextAppWindow", "Next Window of App", "rectangle.on.rectangle", KeyCodes.grave, command: true),
        shortcut("settings", "App Settings", "gearshape", KeyCodes.comma, command: true),
        shortcut("escape", "Escape", "escape", KeyCodes.escape),
        shortcut("return", "Return", "return", KeyCodes.returnKey),
        shortcut("space", "Space", "space", KeyCodes.space),
        shortcut("pageUp", "Page Up", "arrow.up.to.line", KeyCodes.pageUp),
        shortcut("pageDown", "Page Down", "arrow.down.to.line", KeyCodes.pageDown),
        shortcut("leftArrow", "Left Arrow", "arrow.left", KeyCodes.leftArrow),
        shortcut("rightArrow", "Right Arrow", "arrow.right", KeyCodes.rightArrow),
        shortcut("upArrow", "Up Arrow", "arrow.up", KeyCodes.upArrow),
        shortcut("downArrow", "Down Arrow", "arrow.down", KeyCodes.downArrow),
    ]

    /// Lines scrolled by the scroll templates.
    public static let scrollStepLines: Double = 3

    private static let mouseTemplates: [ActionTemplate] = {
        let actions: [(String, MouseAction)] = [
            ("leftClick", .leftClick), ("rightClick", .rightClick), ("middleClick", .middleClick),
            ("doubleClick", .doubleClick), ("toggleDrag", .toggleDrag),
            ("scrollUp", .scroll(dx: 0, dy: scrollStepLines)), ("scrollDown", .scroll(dx: 0, dy: -scrollStepLines)),
            ("scrollLeft", .scroll(dx: -scrollStepLines, dy: 0)), ("scrollRight", .scroll(dx: scrollStepLines, dy: 0)),
        ]
        return actions.map { key, action in
            ActionTemplate(id: "mouse.\(key)", name: action.displayName, symbolName: action.symbolName,
                           category: .mouse, action: .mouse(action))
        }
    }()

    private static let textTemplates: [ActionTemplate] = {
        let actions: [(String, TextAction)] = [
            ("copy", .copy), ("paste", .paste), ("copyText", .copyText("")), ("pasteText", .pasteText("")),
        ]
        return actions.map { key, action in
            ActionTemplate(id: "text.\(key)", name: action.displayName, symbolName: action.symbolName,
                           category: .text, action: .text(action))
        }
    }()

    private static let scriptTemplates: [ActionTemplate] = {
        let actions: [(String, ScriptAction)] = [
            ("appleScript", .appleScript(source: "")), ("shell", .shell(command: "")), ("shortcut", .shortcut(name: "")),
        ]
        return actions.map { key, action in
            ActionTemplate(id: "script.\(key)", name: action.displayName, symbolName: action.symbolName,
                           category: .script, action: .script(action))
        }
    }()

    private static let controlTemplates: [ActionTemplate] = ControlAction.allCases.map { action in
        ActionTemplate(id: "control.\(action.rawValue)", name: action.displayName, symbolName: action.symbolName,
                       category: .control, action: .control(action))
    }
}
