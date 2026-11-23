import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class ValidatorTests: XCTestCase {
    func testValidConfigurationIsUntouched() {
        var configuration = DefaultConfiguration.make()
        let before = configuration
        XCTAssertEqual(ConfigurationValidator.repair(&configuration), [])
        XCTAssertEqual(configuration, before)
    }

    func testRepairIsIdempotent() {
        var configuration = messyConfiguration()
        XCTAssertFalse(ConfigurationValidator.repair(&configuration).isEmpty)
        let repaired = configuration
        // Only warnings about dangling references may remain, and nothing changes any more.
        let second = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(configuration, repaired)
        XCTAssertTrue(second.allSatisfy { $0.contains("no longer exists") || $0.contains("both apply to") }, "\(second)")
    }

    func testMissingGlobalProfileIsRecreated() {
        var configuration = Configuration()
        configuration.profiles = [Profile(name: "Safari", bundleIdentifiers: ["com.apple.Safari"])]
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(notes.count, 1)
        let global = try? XCTUnwrap(configuration.globalProfile)
        XCTAssertEqual(global?.name, "Global")
        XCTAssertEqual(global?.bundleIdentifiers, [])
        XCTAssertNotNil(global?.scroll)
        XCTAssertFalse(global?.bindings.isEmpty ?? true)
        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertEqual(ConfigurationValidator.repair(&configuration), [], "recreated defaults reference nothing missing")
    }

    func testProfileNamedGlobalIsAdopted() {
        var configuration = Configuration()
        let orphan = Profile(name: " global ", bindings: [Fixtures.binding(.pinchIn)], scroll: ScrollSettings())
        configuration.profiles = [Profile(name: "Other"), orphan]
        ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(configuration.globalProfileID, orphan.id)
        XCTAssertEqual(configuration.profiles.count, 2)
    }

    func testGlobalProfileInvariants() {
        var configuration = Fixtures.configuration()
        configuration.profiles[0].bundleIdentifiers = ["com.example"]
        configuration.profiles[0].isEnabled = false
        configuration.profiles[0].scroll = nil
        configuration.profiles[0].name = "  "
        XCTAssertEqual(ConfigurationValidator.repair(&configuration).count, 3)
        let global = configuration.profiles[0]
        XCTAssertEqual(global.bundleIdentifiers, [])
        XCTAssertTrue(global.isEnabled)
        XCTAssertEqual(global.scroll, ScrollSettings())
        XCTAssertEqual(global.name, "Global")
    }

    func testDuplicateIdentifiersBecomeUnique() {
        let sharedProfile = UUID(), sharedBinding = UUID(), sharedWorkflow = UUID(), sharedMenu = UUID()
        let sharedItem = UUID(), sharedTemplate = UUID()
        var configuration = Fixtures.configuration(profiles: [
            Profile(id: sharedProfile, name: "A", bundleIdentifiers: ["a"],
                    bindings: [GestureBinding(id: sharedBinding, trigger: .single(.pinchIn), action: .none)]),
            Profile(id: sharedProfile, name: "B", bundleIdentifiers: ["b"],
                    bindings: [GestureBinding(id: sharedBinding, trigger: .single(.pinchOut), action: .none)]),
        ])
        configuration.profiles.append(Profile(id: configuration.globalProfileID, name: "Impostor"))
        configuration.workflows = [Workflow(id: sharedWorkflow, name: "W1"), Workflow(id: sharedWorkflow, name: "W2")]
        configuration.radialMenus = [
            RadialMenu(id: sharedMenu, name: "M1", items: [RadialMenuItem(id: sharedItem, title: "x")]),
            RadialMenu(id: sharedMenu, name: "M2", items: [RadialMenuItem(id: sharedItem, title: "y",
                                                                         children: [RadialMenuItem(id: sharedItem, title: "z")])]),
        ]
        configuration.ai.templates = [PromptTemplate(id: sharedTemplate, name: "T1"), PromptTemplate(id: sharedTemplate, name: "T2")]
        ConfigurationValidator.repair(&configuration)

        XCTAssertEqual(Set(configuration.profiles.map(\.id)).count, 4)
        XCTAssertEqual(configuration.globalProfile?.name, "Global", "the first holder keeps the global id")
        XCTAssertEqual(configuration.profiles[1].id, sharedProfile)
        XCTAssertEqual(Set(configuration.profiles.flatMap { $0.bindings.map(\.id) }).count, 2)
        XCTAssertEqual(Set(configuration.workflows.map(\.id)).count, 2)
        XCTAssertEqual(configuration.workflows[0].id, sharedWorkflow)
        XCTAssertEqual(Set(configuration.radialMenus.map(\.id)).count, 2)
        let itemIDs = configuration.radialMenus.flatMap { ActionTraversal.allItems(in: $0.items).map(\.id) }
        XCTAssertEqual(Set(itemIDs).count, 3)
        XCTAssertEqual(Set(configuration.ai.templates.map(\.id)).count, 2)
        XCTAssertEqual(ConfigurationValidator.issues(in: configuration), [])
    }

    func testBundleIdentifiersAreTidied() {
        var configuration = Fixtures.configuration(profiles: [
            Profile(name: "A", bundleIdentifiers: ["  com.example.one ", "", "com.example.ONE", "com.example.two\n", "   "]),
            Profile(name: "B", bundleIdentifiers: ["com.example.two"]),
            Profile(name: "C", bundleIdentifiers: ["com.example.two"], isEnabled: false),
        ])
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(configuration.profiles[1].bundleIdentifiers, ["com.example.one", "com.example.two"])
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains { $0.contains("both apply to com.example.two") })
        XCTAssertEqual(configuration.profiles[2].bundleIdentifiers, ["com.example.two"], "overlaps are reported, not removed")
    }

    func testBindingValuesAreClamped() {
        var configuration = Fixtures.configuration(global: [
            Fixtures.binding(.pinchIn, priority: 1_000_000, sensitivity: 4, duration: -3),
            Fixtures.binding(.pinchOut, priority: -1_000_000, sensitivity: -.infinity, duration: 99),
            Fixtures.binding(.twoFingerTap, sensitivity: .nan, duration: .nan),
            Fixtures.binding(.threeFingerTap, sensitivity: 0, duration: 0.4),
        ])
        ConfigurationValidator.repair(&configuration)
        let bindings = configuration.profiles[0].bindings
        XCTAssertEqual(bindings.map(\.sensitivity), [1, 0.5, 0.5, 0])
        XCTAssertEqual(bindings.map(\.duration), [0.05, 5, nil, 0.4])
        XCTAssertEqual(bindings.map(\.priority), [1000, -1000, 0, 0])
    }

    func testSequencesAreLimitedToTwoToFourGestures() {
        let kinds: [GestureKind] = [.pinchIn, .pinchOut, .twoFingerTap, .threeFingerTap, .centerTap, .twoFingerHold]
        var configuration = Fixtures.configuration(global: [
            GestureBinding(trigger: .sequence([]), action: .system(.mute)),
            GestureBinding(trigger: .sequence([.pinchIn]), action: .system(.mute)),
            GestureBinding(trigger: .sequence(Array(kinds.prefix(2))), action: .system(.mute)),
            GestureBinding(trigger: .sequence(Array(kinds.prefix(4))), action: .system(.mute)),
            GestureBinding(trigger: .sequence(kinds), action: .system(.mute)),
        ])
        XCTAssertEqual(ConfigurationValidator.repair(&configuration).count, 3)
        XCTAssertEqual(configuration.profiles[0].bindings.map(\.trigger), [
            .single(.pinchIn), .sequence(Array(kinds.prefix(2))), .sequence(Array(kinds.prefix(4))),
            .sequence(Array(kinds.prefix(4))),
        ])
    }

    func testScrollWorkflowAndAINumbersAreClamped() {
        var scroll = ScrollSettings()
        scroll.verticalMultiplier = 0; scroll.horizontalMultiplier = 500; scroll.acceleration = 7
        scroll.smoothing = -1; scroll.horizontalDeadZone = .nan
        var configuration = Fixtures.configuration(profiles: [Profile(name: "A", bundleIdentifiers: ["a"], scroll: scroll)])
        configuration.workflows = [
            Workflow(name: "Zero", steps: [
                .delay(seconds: -5), .delay(seconds: 10_000), .waitForApp(bundleID: "a", timeout: 0),
                .conditional(.appIsRunning(bundleID: "a"), then: [.waitForApp(bundleID: "a", timeout: 9_999)],
                             otherwise: [.delay(seconds: .infinity)]),
            ], timeout: 0),
            Workflow(name: "Huge", timeout: 86_400),
            Workflow(name: "Fine", steps: [.delay(seconds: 0), .delay(seconds: 600)], timeout: 600),
        ]
        configuration.ai.timeout = -1
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(notes.count, 4, "\(notes)")

        let repairedScroll = configuration.profiles[1].scroll
        XCTAssertEqual(repairedScroll?.verticalMultiplier, 0.1)
        XCTAssertEqual(repairedScroll?.horizontalMultiplier, 10)
        XCTAssertEqual(repairedScroll?.acceleration, 1)
        XCTAssertEqual(repairedScroll?.smoothing, 0)
        XCTAssertEqual(repairedScroll?.horizontalDeadZone, 0)
        XCTAssertEqual(configuration.workflows.map(\.timeout), [30, 600, 600])
        XCTAssertEqual(configuration.workflows[0].steps, [
            .delay(seconds: 0), .delay(seconds: 600), .waitForApp(bundleID: "a", timeout: 10),
            .conditional(.appIsRunning(bundleID: "a"), then: [.waitForApp(bundleID: "a", timeout: 600)],
                         otherwise: [.delay(seconds: 0)]),
        ])
        XCTAssertEqual(configuration.ai.timeout, 30)
    }

    func testRecognizerAndCalibrationAreClamped() {
        var configuration = Fixtures.configuration()
        configuration.recognizer.tapMaxDuration = 0
        configuration.recognizer.holdMinDuration = 60
        configuration.recognizer.directionToleranceDegrees = 90
        configuration.recognizer.swipeMinDistanceMM = .nan
        configuration.recognizer.minimumConfidence = 1.5
        configuration.recognizer.globalSensitivity = -2
        configuration.recognizer.cooldown = -1
        configuration.recognizer.tuning = ["pinchIn": GestureTuning(sensitivity: 9, duration: 100),
                                           "centerTap": GestureTuning(sensitivity: 0.4)]
        var calibration = DeviceCalibration()
        calibration.surface = SurfaceGeometry(widthMM: 0, heightMM: 5_000)
        calibration.typicalTapSize = -1
        calibration.typicalSwipeDistanceMM = .infinity
        configuration.calibrations["device"] = calibration
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(notes.count, 2)

        let recognizer = configuration.recognizer
        XCTAssertEqual(recognizer.tapMaxDuration, 0.05)
        XCTAssertEqual(recognizer.holdMinDuration, 3)
        XCTAssertEqual(recognizer.directionToleranceDegrees, 45)
        XCTAssertEqual(recognizer.swipeMinDistanceMM, RecognizerConfig().swipeMinDistanceMM)
        XCTAssertEqual(recognizer.minimumConfidence, 0.99)
        XCTAssertEqual(recognizer.globalSensitivity, 0)
        XCTAssertEqual(recognizer.cooldown, 0)
        XCTAssertEqual(recognizer.tuning(for: .pinchIn), GestureTuning(sensitivity: 1, duration: 5))
        XCTAssertEqual(recognizer.tuning(for: .centerTap), GestureTuning(sensitivity: 0.4))
        XCTAssertEqual(configuration.calibrations["device"]?.surface, SurfaceGeometry(widthMM: 10, heightMM: 300))
        XCTAssertEqual(configuration.calibrations["device"]?.typicalTapSize, 0.05)
        XCTAssertEqual(configuration.calibrations["device"]?.typicalSwipeDistanceMM, DeviceCalibration().typicalSwipeDistanceMM)

        var untouched = Configuration()
        untouched.recognizer = RecognizerConfig()
        untouched.profiles = [Profile(id: untouched.globalProfileID, name: "Global", scroll: ScrollSettings())]
        XCTAssertEqual(ConfigurationValidator.repair(&untouched), [], "defaults sit inside the safe ranges")
    }

    func testRadialMenuLimits() {
        func chain(_ depth: Int) -> RadialMenuItem {
            RadialMenuItem(title: "level \(depth)", children: depth > 1 ? [chain(depth - 1)] : [])
        }
        func wide() -> [RadialMenuItem] { (0..<20).map { RadialMenuItem(title: "item \($0)") } }
        var menu = RadialMenu(name: "Big", items: [chain(6), RadialMenuItem(title: "wide", children: wide())] + wide())
        menu.theme.diameter = 5
        menu.theme.accentHex = "red"
        var configuration = Fixtures.configuration()
        configuration.radialMenus = [menu]
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(notes.count, 4, "\(notes)")

        let repaired = configuration.radialMenus[0]
        XCTAssertEqual(repaired.items.count, ConfigurationValidator.maxRadialItemsPerRing)
        XCTAssertEqual(repaired.items[1].children.count, ConfigurationValidator.maxRadialItemsPerRing)
        func depth(_ items: [RadialMenuItem]) -> Int { items.isEmpty ? 0 : 1 + (items.map { depth($0.children) }.max() ?? 0) }
        XCTAssertEqual(depth(repaired.items), ConfigurationValidator.maxRadialDepth)
        XCTAssertEqual(repaired.theme.diameter, 160)
        XCTAssertEqual(repaired.theme.accentHex, "")

        var fine = Fixtures.configuration()
        var themed = RadialMenu(name: "Themed", items: [chain(3)])
        themed.theme.accentHex = "#0A84ff"
        fine.radialMenus = [themed]
        XCTAssertEqual(ConfigurationValidator.repair(&fine), [])
    }

    func testDanglingReferencesAreReportedButKept() {
        let missingWorkflow = UUID(), missingMenu = UUID(), missingTemplate = UUID()
        var configuration = Fixtures.configuration(global: [
            Fixtures.binding(.pinchIn, .workflow(id: missingWorkflow)),
            Fixtures.binding(.pinchOut, .ai(templateID: missingTemplate)),
        ])
        configuration.workflows = [Workflow(name: "Flow", steps: [
            .conditional(.clipboardContains("x"), then: [.action(.radialMenu(id: missingMenu))], otherwise: []),
        ])]
        configuration.radialMenus = [RadialMenu(name: "Menu", items: [
            RadialMenuItem(title: "Parent", children: [RadialMenuItem(title: "Child", action: .workflow(id: missingWorkflow))]),
            RadialMenuItem(title: "Valid", action: .workflow(id: configuration.workflows[0].id)),
        ])]
        let before = configuration
        let notes = ConfigurationValidator.repair(&configuration)
        XCTAssertEqual(configuration, before, "data is kept")
        XCTAssertEqual(notes.count, 4, "\(notes)")
        XCTAssertTrue(notes.contains { $0.contains("Pinch in") && $0.contains("a workflow") })
        XCTAssertTrue(notes.contains { $0.contains("Pinch out") && $0.contains("an AI prompt") })
        XCTAssertTrue(notes.contains { $0.contains("Workflow “Flow”") && $0.contains("a radial menu") })
        XCTAssertTrue(notes.contains { $0.contains("“Child”") })
        XCTAssertEqual(ConfigurationValidator.issues(in: configuration), notes)
    }

    func testInvalidApprovalsAndSchemaVersion() {
        var configuration = Fixtures.configuration()
        let valid = ScriptTrust.hash(of: .shell(command: "ok"))
        configuration.approvedScriptHashes = [valid, "abc", valid.uppercased(), String(repeating: "g", count: 64)]
        configuration.schemaVersion = 0
        XCTAssertEqual(ConfigurationValidator.repair(&configuration).count, 2)
        XCTAssertEqual(configuration.approvedScriptHashes, [valid])
        XCTAssertEqual(configuration.schemaVersion, Configuration.currentSchemaVersion)
    }

    private func messyConfiguration() -> Configuration {
        var configuration = Configuration()
        let shared = UUID()
        configuration.profiles = [
            Profile(id: shared, name: "", bundleIdentifiers: [" a ", "a"],
                    bindings: [Fixtures.binding(.pinchIn, .workflow(id: UUID()), sensitivity: 5)]),
            Profile(id: shared, name: "Twin", bundleIdentifiers: ["a"],
                    bindings: [GestureBinding(trigger: .sequence([.pinchIn]), action: .none)]),
        ]
        configuration.workflows = [Workflow(name: "", timeout: -1)]
        configuration.recognizer.sequenceWindow = 100
        configuration.schemaVersion = -4
        return configuration
    }
}
