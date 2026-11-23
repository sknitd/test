import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var store: JSONConfigurationStore!

    override func setUp() {
        directory = Fixtures.temporaryDirectory()
        store = JSONConfigurationStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func richConfiguration() -> Configuration {
        var configuration = DefaultConfiguration.make()
        let script = ScriptAction.shell(command: "echo hi")
        configuration.profiles[1].bindings.append(
            GestureBinding(trigger: .sequence([.twoFingerTap, .threeFingerTap]), action: .script(script),
                           sensitivity: 0.7, duration: 0.4, priority: 3, note: "sequence"))
        ScriptTrust.approve(script, in: &configuration)
        var calibration = DeviceCalibration()
        calibration.calibratedAt = Date()
        calibration.typicalTapSize = 0.73
        configuration.calibrations["device-1"] = calibration
        configuration.recognizer.setTuning(GestureTuning(sensitivity: 0.8, duration: 0.3), for: .oneFingerHold)
        configuration.recognizer.swipeMinDistanceMM = 17.25
        configuration.settings.gesturesPaused = true
        configuration.profiles[2].scroll = ScrollSettings()
        configuration.radialMenus[0].hotKey = KeyCombo(keyCode: 0x31, option: true, label: "⌥Space")
        configuration.workflows[0].steps.append(
            .conditional(.not(.frontmostAppIs(bundleID: "com.apple.finder")),
                         then: [.notify(title: "Done", body: "ok")], otherwise: [.delay(seconds: 0.25)]))
        return configuration
    }

    func testLoadReturnsNilWhenNothingWasSaved() throws {
        XCTAssertNil(try store.load())
        XCTAssertNil(try store.loadBackup())
        XCTAssertEqual(store.location, directory.appendingPathComponent("configuration.json"))
    }

    func testRoundTripPreservesEverything() throws {
        let configuration = richConfiguration()
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
        // A second store on the same directory sees the same data.
        XCTAssertEqual(try JSONConfigurationStore(directory: directory).load(), configuration)
    }

    func testFileIsPrettyPrintedWithSortedKeys() throws {
        try store.save(DefaultConfiguration.make())
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"))
        let ai = try XCTUnwrap(text.range(of: "\n  \"ai\""))
        let profiles = try XCTUnwrap(text.range(of: "\n  \"profiles\""))
        let schema = try XCTUnwrap(text.range(of: "\n  \"schemaVersion\""))
        XCTAssertTrue(ai.lowerBound < profiles.lowerBound && profiles.lowerBound < schema.lowerBound)
    }

    func testSaveLeavesOnlyTheExpectedFiles() throws {
        try store.save(DefaultConfiguration.make())
        try store.save(richConfiguration())
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names, ["configuration.backup.json", "configuration.json"])
    }

    func testBackupHoldsThePreviousVersion() throws {
        let first = DefaultConfiguration.make()
        var second = first
        second.settings.gesturesPaused = true
        var third = second
        third.settings.launchAtLogin = true
        try store.save(first)
        XCTAssertNil(try store.loadBackup())
        try store.save(second)
        XCTAssertEqual(try store.loadBackup(), first)
        try store.save(third)
        XCTAssertEqual(try store.loadBackup(), second)
        XCTAssertEqual(try store.load(), third)
    }

    func testCorruptFileIsPreservedAndReported() throws {
        let good = DefaultConfiguration.make()
        try store.save(good)
        try store.save(good)
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: store.fileURL)

        assertThrowsConfigurationError(try store.load()) { error in
            guard case .unreadable(let message) = error else { return XCTFail("Expected unreadable, got \(error)") }
            XCTAssertTrue(message.contains("configuration.corrupt-"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let preserved = store.corruptFiles()
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(preserved.first)), garbage)
        // The backup survives and the store works again afterwards.
        XCTAssertEqual(try store.loadBackup(), good)
        XCTAssertNil(try store.load())
        try store.save(good)
        XCTAssertEqual(try store.load(), good)
    }

    func testTwoCorruptFilesInTheSameSecondAreBothKept() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for text in ["garbage one", "garbage two"] {
            try Data(text.utf8).write(to: store.fileURL)
            XCTAssertThrowsError(try store.load())
        }
        XCTAssertEqual(store.corruptFiles().count, 2)
    }

    func testCorruptFileNeverReplacesAGoodBackup() throws {
        let first = DefaultConfiguration.make()
        var second = first
        second.settings.gesturesPaused = true
        try store.save(first)
        try store.save(second)
        try Data("[1, 2, 3]".utf8).write(to: store.fileURL)
        try store.save(second)
        XCTAssertEqual(try store.loadBackup(), first)
        XCTAssertEqual(try store.load(), second)
    }

    func testWrongTypesAreTreatedAsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [Any] = [
            ["schemaVersion": 1, "profiles": 5],
            ["schemaVersion": "one"],
            ["schemaVersion": 1, "profiles": [["name": 12]]],
            ["schemaVersion": 1, "settings": ["gesturesPaused": "yes"]],
            ["schemaVersion": 1, "profiles": [["name": "X", "bindings": [["trigger": ["single": ["_0": "noSuchGesture"]]]]]]],
        ]
        for object in cases {
            try Fixtures.json(object).write(to: store.fileURL)
            assertThrowsConfigurationError(try store.load()) { error in
                guard case .unreadable = error else { return XCTFail("Expected unreadable, got \(error)") }
            }
        }
        XCTAssertEqual(store.corruptFiles().count, cases.count)
    }

    func testPartialFileFallsBackToDefaults() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial: [String: Any] = [
            "schemaVersion": 1,
            "profiles": [[
                "name": "Only A Name",
                "bundleIdentifiers": ["com.example.app"],
                "bindings": [
                    ["trigger": ["single": ["_0": "centerTap"]]],
                    ["trigger": ["single": ["_0": "twoFingerTap"]], "action": ["system": ["_0": "launchpad"]], "sensitivity": 0.9],
                    ["note": "has no trigger and is skipped"],
                ],
                "scroll": ["isEnabled": true],
            ]],
            "workflows": [["name": "Bare"]],
            "radialMenus": [["name": "Menu", "items": [["title": "One", "children": [["title": "Nested"]]]],
                             "theme": ["diameter": 300]]],
            "ai": ["templates": [["name": "Prompt"]]],
            "settings": ["gesturesPaused": true],
            "recognizer": ["holdMinDuration": 0.7, "tuning": ["centerTap": [String: Any]()]],
            "calibrations": ["dev": ["typicalTapSize": 0.9]],
        ]
        try Fixtures.json(partial).write(to: store.fileURL)
        let loaded = try XCTUnwrap(try store.load())

        XCTAssertNotNil(loaded.globalProfile, "a global profile is always present")
        let profile = try XCTUnwrap(loaded.profiles.first { $0.name == "Only A Name" })
        XCTAssertTrue(profile.isEnabled)
        XCTAssertTrue(profile.inheritsGlobal)
        XCTAssertEqual(profile.bindings.count, 2)
        XCTAssertEqual(profile.bindings[0].action, Action.none)
        XCTAssertEqual(profile.bindings[0].sensitivity, 0.5)
        XCTAssertTrue(profile.bindings[0].isEnabled)
        XCTAssertEqual(profile.bindings[1].action, .system(.launchpad))
        XCTAssertEqual(profile.bindings[1].sensitivity, 0.9)
        XCTAssertEqual(profile.scroll?.isEnabled, true)
        XCTAssertEqual(profile.scroll?.verticalMultiplier, 1.0)
        XCTAssertEqual(loaded.workflows.first?.timeout, 30)
        XCTAssertEqual(loaded.radialMenus.first?.theme.diameter, 300)
        XCTAssertEqual(loaded.radialMenus.first?.theme.showLabels, true)
        XCTAssertEqual(loaded.radialMenus.first?.items.first?.children.first?.title, "Nested")
        XCTAssertEqual(loaded.ai.templates.first?.userPrompt, "{{input}}")
        XCTAssertFalse(loaded.ai.isEnabled)
        XCTAssertTrue(loaded.settings.gesturesPaused)
        XCTAssertTrue(loaded.settings.notificationsEnabled)
        XCTAssertEqual(loaded.recognizer.holdMinDuration, 0.7)
        XCTAssertEqual(loaded.recognizer.tapMaxDuration, RecognizerConfig().tapMaxDuration)
        XCTAssertEqual(loaded.recognizer.tuning(for: .centerTap), GestureTuning())
        XCTAssertEqual(loaded.calibrations["dev"]?.typicalTapSize, 0.9)
        XCTAssertEqual(loaded.calibrations["dev"]?.surface, .magicMouse)
        XCTAssertTrue(store.corruptFiles().isEmpty)
    }

    func testEmptyObjectLoadsAsAUsableConfiguration() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: store.fileURL)
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertNotNil(loaded.globalProfile)
        XCTAssertEqual(loaded.schemaVersion, Configuration.currentSchemaVersion)
        XCTAssertTrue(ConfigurationValidator.issues(in: loaded).isEmpty)
    }

    func testNewerSchemaIsRejectedAndLeftUntouched() throws {
        var configuration = DefaultConfiguration.make()
        configuration.schemaVersion = Configuration.currentSchemaVersion + 98
        try store.save(configuration)
        let before = try Data(contentsOf: store.fileURL)
        assertThrowsConfigurationError(try store.load()) { error in
            XCTAssertEqual(error, .unsupportedSchema(Configuration.currentSchemaVersion + 98))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        XCTAssertTrue(store.corruptFiles().isEmpty)
    }

    func testConcurrentSavesAndLoadsStayConsistent() throws {
        let base = DefaultConfiguration.make()
        try store.save(base)
        let failures = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                if index % 2 == 0 {
                    var copy = base
                    copy.recognizer.swipeMinDistanceMM = 10 + Double(index % 7)
                    try self.store.save(copy)
                } else if try self.store.load() == nil {
                    failures.increment()
                }
            } catch {
                failures.increment()
            }
        }
        XCTAssertEqual(failures.value, 0)
        XCTAssertNotNil(try store.load())
        XCTAssertTrue(store.corruptFiles().isEmpty)
    }

    func testDefaultDirectoryIsNamedAfterTheApp() {
        XCTAssertEqual(JSONConfigurationStore.defaultDirectory.lastPathComponent, "MagicForge")
        XCTAssertTrue(JSONConfigurationStore.defaultDirectory.path.hasPrefix("/"))
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
