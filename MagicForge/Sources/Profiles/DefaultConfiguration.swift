import Foundation
import MFCore

/// The configuration a new installation starts with.
///
/// Deliberately conservative: nothing overlaps native scrolling, the two-finger sideways swipes
/// that macOS owns are present but switched off, there are no script actions, and AI is disabled.
/// Identifiers are derived from fixed names, so `make()` returns the same value every time.
public enum DefaultConfiguration {
    public static let safariBundleID = "com.apple.Safari"
    public static let chromeBundleID = "com.google.Chrome"
    public static let finderBundleID = "com.apple.finder"
    public static let vsCodeBundleID = "com.microsoft.VSCode"
    public static let photosBundleID = "com.apple.Photos"

    public static func make() -> Configuration {
        var configuration = Configuration()
        configuration.globalProfileID = id("profile.global")
        let workflow = revealDownloadsWorkflow()
        let menu = quickActionsMenu(revealDownloads: workflow.id)
        configuration.workflows = [workflow]
        configuration.radialMenus = [menu]
        configuration.profiles = [makeGlobalProfile(id: configuration.globalProfileID, radialMenuID: menu.id)]
            + DefaultProfiles.appProfiles()
        configuration.ai.isEnabled = false
        configuration.ai.templates = promptTemplates()
        return configuration
    }

    static func id(_ name: String) -> UUID { Digest.stableUUID("magicforge.default." + name) }

    /// The default global profile. Without a radial menu id the bindings that open the Quick
    /// Actions menu are left out (used when a damaged configuration needs a new global profile).
    static func makeGlobalProfile(id profileID: UUID, radialMenuID: UUID?) -> Profile {
        var builder = BindingBuilder(scope: "global")
        builder.add(.centerTap, .mouse(.middleClick), note: "Tap the middle of the surface for a middle click.")
        builder.add(.twoFingerTap, .system(.missionControl))
        builder.add(.threeFingerTap, .system(.appExpose))
        builder.add(.twoFingerSwipeDown, .system(.showDesktop))
        builder.add(.pinchOut, .keyboard(DefaultKeys.zoomIn), note: "Zoom in (⌘+) in most apps.")
        builder.add(.pinchIn, .keyboard(DefaultKeys.zoomOut), note: "Zoom out (⌘−) in most apps.")
        builder.add(.twoFingerSwipeLeft, .none, isEnabled: false,
                    note: "Off by default: macOS uses this to swipe between full-screen apps.")
        builder.add(.twoFingerSwipeRight, .none, isEnabled: false,
                    note: "Off by default: macOS uses this to swipe between full-screen apps.")
        if let radialMenuID {
            builder.add(.twoFingerHold, .radialMenu(id: radialMenuID), note: "Hold two fingers to open Quick Actions.")
            builder.add(.chordRightClick, .radialMenu(id: radialMenuID),
                        note: "Fallback that needs no touch data: Control-Option-right-click.")
        }
        builder.add(.chordScrollUp, .system(.missionControl),
                    note: "Fallback that needs no touch data: Control-Option-scroll up.")
        builder.add(.chordScrollDown, .system(.appExpose),
                    note: "Fallback that needs no touch data: Control-Option-scroll down.")
        return Profile(id: profileID, name: "Global", symbolName: "globe", bindings: builder.bindings,
                       scroll: ScrollSettings())
    }

    static func revealDownloadsWorkflow() -> Workflow {
        Workflow(id: id("workflow.reveal-downloads"), name: "Reveal Downloads", symbolName: "arrow.down.circle",
                 steps: [
                     .action(.app(.launch(bundleID: finderBundleID))),
                     .waitForApp(bundleID: finderBundleID, timeout: 5),
                     .action(.keyboard(DefaultKeys.goToDownloads)),
                 ],
                 timeout: 15, continueOnError: false)
    }

    static func quickActionsMenu(revealDownloads workflowID: UUID) -> RadialMenu {
        func item(_ key: String, _ title: String, _ symbol: String, _ action: Action = .none,
                  children: [RadialMenuItem] = []) -> RadialMenuItem {
            RadialMenuItem(id: id("menu.quick." + key), title: title, symbolName: symbol, action: action, children: children)
        }
        let screenshots = [
            item("shot.selection", "Selection", "rectangle.dashed", .system(.screenshotSelection)),
            item("shot.window", "Window", "macwindow", .system(.screenshotWindow)),
            item("shot.full", "Full Screen", "display", .system(.screenshotFull)),
        ]
        let windows = [
            item("win.left", "Left Half", "rectangle.lefthalf.filled", .window(.snapLeft)),
            item("win.right", "Right Half", "rectangle.righthalf.filled", .window(.snapRight)),
            item("win.max", "Maximize", "arrow.up.left.and.arrow.down.right", .window(.maximize)),
            item("win.center", "Center", "rectangle.center.inset.filled", .window(.center)),
        ]
        return RadialMenu(id: id("menu.quick"), name: "Quick Actions", items: [
            item("mission", "Mission Control", "rectangle.3.group", .system(.missionControl)),
            item("shot", "Screenshot", "camera.viewfinder", children: screenshots),
            item("win", "Window", "macwindow.on.rectangle", children: windows),
            item("play", "Play / Pause", "playpause", .system(.playPause)),
            item("downloads", "Downloads", "arrow.down.circle", .workflow(id: workflowID)),
            item("spotlight", "Spotlight", "magnifyingglass", .system(.spotlight)),
        ])
    }

    static func promptTemplates() -> [PromptTemplate] {
        [
            PromptTemplate(id: id("ai.summarize"), name: "Summarize",
                           systemPrompt: "You summarize text accurately and concisely.",
                           userPrompt: "Summarize the following text in a few sentences:\n\n{{input}}", input: .selectedText),
            PromptTemplate(id: id("ai.fix-grammar"), name: "Fix Grammar",
                           systemPrompt: "You correct spelling and grammar without changing meaning or tone. "
                               + "Reply with the corrected text only.",
                           userPrompt: "{{input}}", input: .selectedText),
            PromptTemplate(id: id("ai.explain"), name: "Explain",
                           systemPrompt: "You explain things clearly to a curious non-expert.",
                           userPrompt: "Explain the following in plain language:\n\n{{input}}", input: .selectedText),
        ]
    }
}

/// Builds bindings with identifiers that are stable for a given scope and trigger.
struct BindingBuilder {
    let scope: String
    private(set) var bindings: [GestureBinding] = []

    init(scope: String) { self.scope = scope }

    mutating func add(_ kind: GestureKind, _ action: Action, isEnabled: Bool = true, note: String = "") {
        bindings.append(GestureBinding(id: DefaultConfiguration.id("binding.\(scope).\(kind.rawValue)"),
                                       trigger: .single(kind), action: action, isEnabled: isEnabled, note: note))
    }
}

/// The macOS virtual key codes (kVK_*) the defaults need, and the shortcuts built from them.
enum DefaultKeys {
    static let t: UInt16 = 0x11
    static let n: UInt16 = 0x2D
    static let l: UInt16 = 0x25
    static let p: UInt16 = 0x23
    static let r: UInt16 = 0x0F
    static let equal: UInt16 = 0x18
    static let minus: UInt16 = 0x1B
    static let leftBracket: UInt16 = 0x21
    static let rightBracket: UInt16 = 0x1E
    static let grave: UInt16 = 0x32
    static let space: UInt16 = 0x31
    static let leftArrow: UInt16 = 0x7B
    static let rightArrow: UInt16 = 0x7C
    static let upArrow: UInt16 = 0x7E

    static let zoomIn = KeyCombo(keyCode: equal, command: true, label: "⌘+")
    static let zoomOut = KeyCombo(keyCode: minus, command: true, label: "⌘−")
    static let back = KeyCombo(keyCode: leftBracket, command: true, label: "⌘[")
    static let forward = KeyCombo(keyCode: rightBracket, command: true, label: "⌘]")
    static let previousTab = KeyCombo(keyCode: leftBracket, command: true, shift: true, label: "⇧⌘[")
    static let nextTab = KeyCombo(keyCode: rightBracket, command: true, shift: true, label: "⇧⌘]")
    static let newTab = KeyCombo(keyCode: t, command: true, label: "⌘T")
    static let newFolder = KeyCombo(keyCode: n, command: true, shift: true, label: "⇧⌘N")
    static let quickLook = KeyCombo(keyCode: space, label: "Space")
    static let goToDownloads = KeyCombo(keyCode: l, command: true, option: true, label: "⌥⌘L")
    static let enclosingFolder = KeyCombo(keyCode: upArrow, command: true, label: "⌘↑")
    static let commandPalette = KeyCombo(keyCode: p, command: true, shift: true, label: "⇧⌘P")
    static let toggleTerminal = KeyCombo(keyCode: grave, control: true, label: "⌃`")
    static let codeGoBack = KeyCombo(keyCode: minus, control: true, label: "⌃−")
    static let codeGoForward = KeyCombo(keyCode: minus, control: true, shift: true, label: "⌃⇧−")
    static let rotateCounterclockwise = KeyCombo(keyCode: r, command: true, label: "⌘R")
    static let rotateClockwise = KeyCombo(keyCode: r, command: true, option: true, label: "⌥⌘R")
    static let previousItem = KeyCombo(keyCode: leftArrow, label: "←")
    static let nextItem = KeyCombo(keyCode: rightArrow, label: "→")
}
