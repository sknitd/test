import XCTest
@testable import MFCore

final class GestureCatalogTests: XCTestCase {
    func testEveryGestureHasNamesSymbolAndSummary() {
        for kind in GestureKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind)")
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind)")
            XCTAssertFalse(kind.summary.isEmpty, "\(kind)")
            XCTAssertTrue(kind.summary.hasSuffix("."), "\(kind) summary should be a sentence")
            XCTAssertFalse(kind.summary.contains("\n"), "\(kind) summary must be one line")
        }
    }

    func testGestureDisplayNamesAreUnique() {
        let names = GestureKind.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testSymbolNamesLookLikeSFSymbols() {
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "."))
        var symbols = GestureKind.allCases.map(\.symbolName) + GestureKind.Category.allCases.map(\.symbolName)
        symbols += ActionCategory.allCases.map(\.symbolName) + ActionCatalog.templates.map(\.symbolName)
        symbols += PermissionKind.allCases.map(\.symbolName)
        for symbol in symbols {
            XCTAssertTrue(symbol.unicodeScalars.allSatisfy(allowed.contains), symbol)
            XCTAssertFalse(symbol.hasPrefix(".") || symbol.hasSuffix(".") || symbol.contains(".."), symbol)
        }
    }

    func testCategoriesHaveMetadata() {
        for category in GestureKind.Category.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.symbolName.isEmpty)
            XCTAssertFalse(category.summary.isEmpty)
        }
    }

    func testDirections() {
        XCTAssertEqual(GestureKind.twoFingerSwipeLeft.direction, .left)
        XCTAssertEqual(GestureKind.threeFingerSwipeRight.direction, .right)
        XCTAssertEqual(GestureKind.holdThenSwipeUp.direction, .up)
        XCTAssertEqual(GestureKind.chordScrollDown.direction, .down)
        XCTAssertNil(GestureKind.oneFingerTap.direction)
        XCTAssertNil(GestureKind.pinchIn.direction)
        XCTAssertNil(GestureKind.leftEdgeSwipe.direction)
        for kind in GestureKind.allCases {
            let raw = kind.rawValue
            let expected: GestureKind.Direction?
            if raw.hasSuffix("Left"), kind.category != .zones { expected = .left }
            else if raw.hasSuffix("Right"), kind.category != .zones { expected = .right }
            else if raw.hasSuffix("Up") { expected = .up }
            else if raw.hasSuffix("Down") { expected = .down }
            else { expected = nil }
            XCTAssertEqual(kind.direction, expected, raw)
        }
    }

    func testTriggerDisplayNames() {
        XCTAssertEqual(GestureTrigger.single(.pinchIn).displayName, "Pinch In")
        XCTAssertEqual(GestureTrigger.sequence([.twoFingerTap, .pinchOut]).displayName, "Two-Finger Tap → Pinch Out")
        XCTAssertFalse(GestureTrigger.sequence([]).displayName.isEmpty)
    }
}

final class KeyCodeTests: XCTestCase {
    func testVirtualKeyCodesMatchCarbonConstants() {
        let expected: [(UInt16, UInt16)] = [
            (KeyCodes.a, 0x00), (KeyCodes.s, 0x01), (KeyCodes.d, 0x02), (KeyCodes.f, 0x03), (KeyCodes.h, 0x04),
            (KeyCodes.g, 0x05), (KeyCodes.z, 0x06), (KeyCodes.x, 0x07), (KeyCodes.c, 0x08), (KeyCodes.v, 0x09),
            (KeyCodes.b, 0x0B), (KeyCodes.q, 0x0C), (KeyCodes.w, 0x0D), (KeyCodes.e, 0x0E), (KeyCodes.r, 0x0F),
            (KeyCodes.y, 0x10), (KeyCodes.t, 0x11), (KeyCodes.one, 0x12), (KeyCodes.two, 0x13), (KeyCodes.three, 0x14),
            (KeyCodes.four, 0x15), (KeyCodes.six, 0x16), (KeyCodes.five, 0x17), (KeyCodes.equal, 0x18),
            (KeyCodes.nine, 0x19), (KeyCodes.seven, 0x1A), (KeyCodes.minus, 0x1B), (KeyCodes.eight, 0x1C),
            (KeyCodes.zero, 0x1D), (KeyCodes.rightBracket, 0x1E), (KeyCodes.o, 0x1F), (KeyCodes.u, 0x20),
            (KeyCodes.leftBracket, 0x21), (KeyCodes.i, 0x22), (KeyCodes.p, 0x23), (KeyCodes.returnKey, 0x24),
            (KeyCodes.l, 0x25), (KeyCodes.j, 0x26), (KeyCodes.quote, 0x27), (KeyCodes.k, 0x28),
            (KeyCodes.semicolon, 0x29), (KeyCodes.backslash, 0x2A), (KeyCodes.comma, 0x2B), (KeyCodes.slash, 0x2C),
            (KeyCodes.n, 0x2D), (KeyCodes.m, 0x2E), (KeyCodes.period, 0x2F), (KeyCodes.tab, 0x30),
            (KeyCodes.space, 0x31), (KeyCodes.grave, 0x32), (KeyCodes.delete, 0x33), (KeyCodes.escape, 0x35),
            (KeyCodes.f1, 0x7A), (KeyCodes.f2, 0x78), (KeyCodes.f3, 0x63), (KeyCodes.f4, 0x76), (KeyCodes.f5, 0x60),
            (KeyCodes.f6, 0x61), (KeyCodes.f7, 0x62), (KeyCodes.f8, 0x64), (KeyCodes.f9, 0x65), (KeyCodes.f10, 0x6D),
            (KeyCodes.f11, 0x67), (KeyCodes.f12, 0x6F), (KeyCodes.leftArrow, 0x7B), (KeyCodes.rightArrow, 0x7C),
            (KeyCodes.downArrow, 0x7D), (KeyCodes.upArrow, 0x7E), (KeyCodes.home, 0x73), (KeyCodes.end, 0x77),
            (KeyCodes.pageUp, 0x74), (KeyCodes.pageDown, 0x79), (KeyCodes.forwardDelete, 0x75),
        ]
        for (actual, value) in expected { XCTAssertEqual(actual, value) }
        XCTAssertEqual(Set(expected.map(\.0)).count, expected.count, "key codes must be distinct")
    }

    func testKeyNames() {
        XCTAssertEqual(KeyCodes.letters.map(KeyCodeNames.name(for:)).joined(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        XCTAssertEqual(KeyCodes.digits.map(KeyCodeNames.name(for:)).joined(), "0123456789")
        XCTAssertEqual(KeyCodeNames.name(for: KeyCodes.f12), "F12")
        XCTAssertEqual(KeyCodeNames.name(for: KeyCodes.space), "Space")
        XCTAssertEqual(KeyCodeNames.name(for: KeyCodes.leftBracket), "[")
        XCTAssertEqual(KeyCodeNames.name(for: 0x0A), "Key 0x0A")
        XCTAssertEqual(KeyCodeNames.name(for: 0x1FF), "Key 0x1FF")
        XCTAssertFalse(KeyCodeNames.isKnown(0x0A))
    }

    func testDisplayString() {
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.k, command: true, option: true, control: true, shift: true).displayString,
                       "⌃⌥⇧⌘K")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.t, command: true).displayString, "⌘T")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.t, command: true, shift: true).displayString, "⇧⌘T")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.tab, control: true, shift: true).displayString, "⌃⇧⇥")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.leftBracket, command: true).displayString, "⌘[")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.escape).displayString, "⎋")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.space, option: true).displayString, "⌥Space")
        // The label is never used for the derived string.
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.a, command: true, label: "custom").displayString, "⌘A")
        // Fn is implicit for function / arrow keys and explicit elsewhere.
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.f5, function: true).displayString, "F5")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.leftArrow, command: true, function: true).displayString, "⌘←")
        XCTAssertEqual(KeyCombo(keyCode: KeyCodes.f, control: true, function: true).displayString, "fn⌃F")
    }
}

final class ActionCatalogTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
    }

    func testSubActionNames() {
        for action in SystemAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty); XCTAssertFalse(action.symbolName.isEmpty)
        }
        XCTAssertEqual(Set(SystemAction.allCases.map(\.displayName)).count, SystemAction.allCases.count)
        for action in ControlAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty); XCTAssertFalse(action.symbolName.isEmpty)
        }
        for category in ActionCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty); XCTAssertFalse(category.symbolName.isEmpty)
            XCTAssertEqual(category.id, category.rawValue)
        }
        for kind in PermissionKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty); XCTAssertFalse(kind.summary.isEmpty)
        }
        XCTAssertEqual(WindowAction.resize(byFraction: 0.1).displayName, "Grow Window by 10%")
        XCTAssertEqual(WindowAction.resize(byFraction: -0.1).displayName, "Shrink Window by 10%")
        XCTAssertEqual(WindowAction.resize(byFraction: .nan).displayName, "Resize Window")
        XCTAssertEqual(AppAction.launch(bundleID: "").displayName, "Launch App")
        XCTAssertEqual(AppAction.launch(bundleID: "com.apple.Safari").displayName, "Launch com.apple.Safari")
        XCTAssertEqual(MouseAction.scroll(dx: 0, dy: -3).displayName, "Scroll Down")
        XCTAssertEqual(MouseAction.scroll(dx: 2, dy: 2).displayName, "Scroll")
    }

    func testActionNamesNeverRevealPrivateText() {
        let secret = "hunter2-secret-body"
        let actions: [Action] = [
            .text(.copyText(secret)), .text(.pasteText(secret)),
            .script(.appleScript(source: secret)), .script(.shell(command: secret)),
        ]
        for action in actions { XCTAssertFalse(action.displayName.contains(secret)) }
    }

    func testActionMetadata() {
        XCTAssertEqual(Action.none.displayName, "No Action")
        XCTAssertEqual(Action.keyboard(KeyCombo(keyCode: KeyCodes.t, command: true)).displayName, "Press ⌘T")
        XCTAssertEqual(Action.keyboard(KeyCombo(keyCode: KeyCodes.t, command: true, label: "New Tab")).displayName,
                       "Press New Tab")
        XCTAssertEqual(Action.system(.missionControl).category, .system)
        XCTAssertEqual(Action.workflow(id: UUID()).category, .workflow)
        XCTAssertEqual(Action.radialMenu(id: UUID()).category, .radialMenu)
        XCTAssertEqual(Action.ai(templateID: UUID()).category, .ai)
        XCTAssertEqual(Action.none.category, .control)
    }

    func testDisplayNameResolvesReferences() {
        var configuration = Configuration()
        let workflow = Workflow(name: "Morning")
        let menu = RadialMenu(name: "Quick")
        let template = PromptTemplate(name: "Summarize")
        configuration.workflows = [workflow]
        configuration.radialMenus = [menu]
        configuration.ai.templates = [template]
        XCTAssertEqual(Action.workflow(id: workflow.id).displayName(in: configuration), "Run Workflow “Morning”")
        XCTAssertEqual(Action.radialMenu(id: menu.id).displayName(in: configuration), "Show Radial Menu “Quick”")
        XCTAssertEqual(Action.ai(templateID: template.id).displayName(in: configuration), "AI: Summarize")
        XCTAssertTrue(Action.workflow(id: UUID()).displayName(in: configuration).contains("missing"))
        XCTAssertEqual(Action.system(.mute).displayName(in: configuration), "Mute")
    }

    func testTemplatesAreWellFormed() {
        let templates = ActionCatalog.templates
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count, "template ids must be unique")
        XCTAssertEqual(Set(templates.map(\.name)).count, templates.count, "template names must be unique")
        XCTAssertEqual(Set(templates.map(\.action)).count, templates.count, "template actions must be distinct")
        for template in templates {
            XCTAssertFalse(template.id.isEmpty)
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertFalse(template.symbolName.isEmpty)
            XCTAssertEqual(template.category, template.action.category, template.id)
            XCTAssertTrue(template.id.hasPrefix(template.category.rawValue + "."), template.id)
            XCTAssertFalse(template.action.displayName.isEmpty)
            XCTAssertEqual(ActionCatalog.template(id: template.id), template)
        }
    }

    func testTemplateLibraryIsComplete() {
        let actions = Set(ActionCatalog.templates.map(\.action))
        for action in SystemAction.allCases { XCTAssertTrue(actions.contains(.system(action)), "\(action)") }
        for action in ControlAction.allCases { XCTAssertTrue(actions.contains(.control(action)), "\(action)") }
        let windows: [WindowAction] = [.snapLeft, .snapRight, .snapTop, .snapBottom, .maximize, .center,
                                       .restorePreviousFrame, .moveToNextDisplay, .minimize, .close,
                                       .resize(byFraction: 0.1), .resize(byFraction: -0.1)]
        for action in windows { XCTAssertTrue(actions.contains(.window(action)), "\(action)") }
        let apps: [AppAction] = [.launch(bundleID: ""), .switchTo(bundleID: ""), .hideFrontmost, .quitFrontmost,
                                 .openURL(""), .openPath("")]
        for action in apps { XCTAssertTrue(actions.contains(.app(action)), "\(action)") }
        let mouse: [MouseAction] = [.leftClick, .rightClick, .middleClick, .doubleClick, .toggleDrag]
        for action in mouse { XCTAssertTrue(actions.contains(.mouse(action)), "\(action)") }
        let scripts: [ScriptAction] = [.appleScript(source: ""), .shell(command: ""), .shortcut(name: "")]
        for action in scripts { XCTAssertTrue(actions.contains(.script(action)), "\(action)") }
        for action in [TextAction.copy, .paste, .copyText(""), .pasteText("")] {
            XCTAssertTrue(actions.contains(.text(action)), "\(action)")
        }
        XCTAssertEqual(ActionCatalog.templates(in: .system).count, SystemAction.allCases.count)
        XCTAssertTrue(ActionCatalog.templates(in: .workflow).isEmpty)
        XCTAssertEqual(ActionCatalog.templates(in: .keyboard).count,
                       ActionCatalog.templates.filter { $0.id.hasPrefix("keyboard.") }.count)
    }

    func testKeyboardShortcutTemplates() throws {
        func combo(_ id: String) throws -> KeyCombo {
            let template = try XCTUnwrap(ActionCatalog.template(id: id), id)
            guard case .keyboard(let combo) = template.action else { XCTFail(id); throw CancellationError() }
            XCTAssertEqual(combo.label, combo.displayString)
            XCTAssertTrue(template.name.contains(combo.displayString))
            return combo
        }
        XCTAssertEqual(try combo("keyboard.back").displayString, "⌘[")
        XCTAssertEqual(try combo("keyboard.forward").displayString, "⌘]")
        XCTAssertEqual(try combo("keyboard.newTab").displayString, "⌘T")
        XCTAssertEqual(try combo("keyboard.closeTab").displayString, "⌘W")
        XCTAssertEqual(try combo("keyboard.reopenTab").displayString, "⇧⌘T")
        XCTAssertEqual(try combo("keyboard.nextTab").displayString, "⌃⇥")
        XCTAssertEqual(try combo("keyboard.previousTab").displayString, "⌃⇧⇥")
        XCTAssertEqual(try combo("keyboard.zoomIn").displayString, "⌘=")
        XCTAssertEqual(try combo("keyboard.zoomOut").displayString, "⌘-")
        XCTAssertEqual(try combo("keyboard.copy").displayString, "⌘C")
        XCTAssertEqual(try combo("keyboard.paste").displayString, "⌘V")
        XCTAssertEqual(try combo("keyboard.undo").displayString, "⌘Z")
        XCTAssertEqual(try combo("keyboard.redo").displayString, "⇧⌘Z")
    }

    func testEveryTemplateActionRoundTrips() throws {
        for template in ActionCatalog.templates { try roundTrip(template.action) }
        try roundTrip(ActionCatalog.templates.map(\.action))
    }

    func testNestedValuesRoundTrip() throws {
        let allActions = ActionCatalog.templates.map(\.action)
            + [.none, .workflow(id: UUID()), .radialMenu(id: UUID()), .ai(templateID: UUID()),
               .app(.openURL("https://example.com/a?b=c")), .text(.pasteText("line 1\nline 2 “quoted” 🙂")),
               .script(.shell(command: "echo \"hi\" && exit 0")), .window(.resize(byFraction: -0.25)),
               .keyboard(KeyCombo(keyCode: KeyCodes.k, command: true, option: true, control: true, shift: true,
                                  function: true, label: "⌃⌥⇧⌘K"))]
        let nested: [WorkflowStep] = [
            .delay(seconds: 0.25),
            .waitForApp(bundleID: "com.apple.Safari", timeout: 5),
            .notify(title: "Done", body: "All good"),
            .conditional(.not(.clipboardContains("http")), then: [.action(.text(.copy))],
                         otherwise: [.conditional(.appIsRunning(bundleID: "com.apple.finder"),
                                                  then: [.delay(seconds: 1)], otherwise: [])]),
        ]
        let workflow = Workflow(name: "Everything", steps: allActions.map(WorkflowStep.action) + nested
                                + [.conditional(.frontmostAppIs(bundleID: "com.apple.Safari"), then: nested, otherwise: nested)],
                                timeout: 45, continueOnError: true)
        try roundTrip(workflow)

        var theme = RadialMenuTheme()
        theme.accentHex = "#0A84FF"; theme.diameter = 320; theme.showLabels = false
        let leaves = allActions.enumerated().map { index, action in
            RadialMenuItem(title: "Item \(index)", symbolName: action.symbolName, action: action)
        }
        let menu = RadialMenu(name: "Big", items: [
            RadialMenuItem(title: "Group", children: [RadialMenuItem(title: "Sub", children: leaves)]),
            RadialMenuItem(title: "Leaf", action: .workflow(id: workflow.id)),
        ], theme: theme, hotKey: KeyCombo(keyCode: KeyCodes.space, option: true, label: "⌥Space"))
        try roundTrip(menu)

        let bindings = GestureKind.allCases.enumerated().map { index, kind in
            GestureBinding(trigger: index % 2 == 0 ? .single(kind) : .sequence([kind, .twoFingerTap]),
                           action: allActions[index % allActions.count], sensitivity: 0.7, duration: 0.4, priority: index)
        }
        var configuration = Configuration()
        let profile = Profile(name: "Global", bindings: bindings, scroll: ScrollSettings())
        configuration.profiles = [profile]
        configuration.globalProfileID = profile.id
        configuration.workflows = [workflow]
        configuration.radialMenus = [menu]
        configuration.ai.templates = [PromptTemplate(name: "Fix grammar", systemPrompt: "Be terse.")]
        configuration.approvedScriptHashes = ["abc"]
        try roundTrip(configuration)
    }
}
