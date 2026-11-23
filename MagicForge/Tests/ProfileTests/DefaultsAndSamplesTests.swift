import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class DefaultsTests: XCTestCase {
    private let configuration = DefaultConfiguration.make()

    func testDefaultsAreValidAndDeterministic() {
        XCTAssertEqual(ConfigurationValidator.issues(in: configuration), [])
        XCTAssertEqual(DefaultConfiguration.make(), configuration)
        XCTAssertEqual(configuration.schemaVersion, Configuration.currentSchemaVersion)
        XCTAssertEqual(configuration.globalProfile?.id, configuration.globalProfileID)
        XCTAssertEqual(configuration.globalProfile?.bundleIdentifiers, [])
    }

    func testDefaultsContainNoScriptsAndKeepAIOff() {
        XCTAssertTrue(ScriptTrust.scripts(in: configuration).isEmpty)
        XCTAssertTrue(ScriptTrust.scripts(in: DefaultProfiles.windowManagement()).isEmpty)
        XCTAssertTrue(configuration.approvedScriptHashes.isEmpty)
        XCTAssertFalse(configuration.ai.isEnabled)
        XCTAssertEqual(configuration.ai.baseURL, "")
        XCTAssertEqual(configuration.ai.templates.map(\.name), ["Summarize", "Fix Grammar", "Explain"])
        XCTAssertTrue(configuration.ai.templates.allSatisfy { $0.userPrompt.contains("{{input}}") })
        XCTAssertFalse(configuration.profiles.contains { profile in
            profile.bindings.contains { if case .ai = $0.action { return true } else { return false } }
        })
    }

    func testAppProfilesCoverTheExpectedApps() {
        let apps = configuration.profiles.filter { $0.id != configuration.globalProfileID }
        XCTAssertEqual(apps.map(\.bundleIdentifiers), [
            ["com.apple.Safari"], ["com.google.Chrome"], ["com.apple.finder"], ["com.microsoft.VSCode"], ["com.apple.Photos"],
        ])
        XCTAssertTrue(apps.allSatisfy { $0.isEnabled && $0.inheritsGlobal && !$0.bindings.isEmpty })
    }

    func testGestureKindsAreRawExceptTheDeclaredFallbacks() {
        let global = configuration.profiles[0]
        let fallback = global.bindings.filter { $0.trigger.kinds.contains { $0.requirement == .pointerEvents } }
        XCTAssertEqual(Set(fallback.flatMap { $0.trigger.kinds }), [.chordRightClick, .chordScrollUp, .chordScrollDown])
        XCTAssertTrue(fallback.allSatisfy { $0.note.contains("Fallback") })
        for profile in configuration.profiles.dropFirst() + [DefaultProfiles.windowManagement()] {
            XCTAssertTrue(profile.bindings.allSatisfy { $0.trigger.kinds.allSatisfy { $0.requirement == .rawContacts } },
                          profile.name)
        }
    }

    func testNothingEnabledOverlapsScrollingOrSystemGestures() {
        for profile in configuration.profiles {
            for binding in profile.bindings where binding.isEnabled {
                XCTAssertFalse(binding.trigger.kinds.contains { $0.overlapsNativeScrolling }, profile.name)
                XCTAssertFalse(binding.trigger.kinds.contains { $0 == .twoFingerSwipeLeft || $0 == .twoFingerSwipeRight })
            }
        }
        let sideways = configuration.profiles[0].bindings.filter {
            $0.trigger == .single(.twoFingerSwipeLeft) || $0.trigger == .single(.twoFingerSwipeRight)
        }
        XCTAssertEqual(sideways.count, 2)
        XCTAssertTrue(sideways.allSatisfy { !$0.isEnabled && $0.action == Action.none })
    }

    func testKeyboardShortcutsUseTheRightKeyCodes() {
        func combo(_ bundleID: String, _ kind: GestureKind) -> KeyCombo? {
            let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: bundleID)
            if case .keyboard(let combo)? = resolved.binding(for: kind)?.action { return combo }
            return nil
        }
        XCTAssertEqual(combo("com.apple.Safari", .holdThenSwipeLeft), KeyCombo(keyCode: 0x21, command: true, label: "⌘["))
        XCTAssertEqual(combo("com.google.Chrome", .holdThenSwipeRight), KeyCombo(keyCode: 0x1E, command: true, label: "⌘]"))
        XCTAssertEqual(combo("com.apple.finder", .cornerTapTopRight), KeyCombo(keyCode: 0x2D, command: true, shift: true, label: "⇧⌘N"))
        XCTAssertEqual(combo("com.apple.finder", .threeFingerTap), KeyCombo(keyCode: 0x31, label: "Space"))
        XCTAssertEqual(combo("com.apple.finder", .holdThenSwipeDown), KeyCombo(keyCode: 0x25, command: true, option: true, label: "⌥⌘L"))
        XCTAssertEqual(combo("com.microsoft.VSCode", .threeFingerTap), KeyCombo(keyCode: 0x23, command: true, shift: true, label: "⇧⌘P"))
        XCTAssertEqual(combo("com.microsoft.VSCode", .twoFingerSwipeDown), KeyCombo(keyCode: 0x32, control: true, label: "⌃`"))
        XCTAssertEqual(combo("com.apple.Photos", .rotateCounterclockwise), KeyCombo(keyCode: 0x0F, command: true, label: "⌘R"))
        XCTAssertEqual(combo("com.apple.Photos", .pinchOut), KeyCombo(keyCode: 0x18, command: true, label: "⌘+"))
        XCTAssertEqual(combo("com.example.unknown", .pinchIn), KeyCombo(keyCode: 0x1B, command: true, label: "⌘−"))
        XCTAssertEqual(combo("com.apple.Safari", .rotateClockwise), KeyCombo(keyCode: 0x1E, command: true, shift: true, label: "⇧⌘]"))
    }

    func testWorkflowAndRadialMenu() {
        XCTAssertEqual(configuration.workflows.count, 1)
        XCTAssertFalse(configuration.workflows[0].steps.isEmpty)
        XCTAssertEqual(configuration.radialMenus.count, 1)
        let menu = configuration.radialMenus[0]
        XCTAssertEqual(menu.items.count, 6)
        XCTAssertEqual(menu.items.filter { !$0.children.isEmpty }.count, 2)
        XCTAssertTrue(menu.items.contains { $0.action == .workflow(id: configuration.workflows[0].id) })
        XCTAssertTrue(configuration.profiles[0].bindings.contains { $0.action == .radialMenu(id: menu.id) })
        let itemIDs = ActionTraversal.allItems(in: menu.items).map(\.id)
        XCTAssertEqual(Set(itemIDs).count, itemIDs.count)
    }

    func testEveryIdentifierIsUnique() {
        let windows = DefaultProfiles.windowManagement()
        var ids: [UUID] = configuration.profiles.map(\.id)
        for profile in configuration.profiles + [windows] { ids += profile.bindings.map(\.id) }
        ids += configuration.workflows.map(\.id)
        ids += configuration.radialMenus.map(\.id)
        ids += configuration.ai.templates.map(\.id)
        ids.append(windows.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

final class SampleProfileTests: XCTestCase {
    /// `<repo>/Resources/SampleProfiles`, located relative to this source file.
    private var samplesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/SampleProfiles", isDirectory: true)
    }

    /// Set MF_WRITE_SAMPLES=1 to (re)generate the files from the exporter.
    func testSampleFilesMatchTheExporter() throws {
        let samples = try SampleProfiles.all()
        XCTAssertEqual(samples.map(\.fileName),
                       ["Browser.json", "Finder.json", "VSCode.json", "Photos.json", "WindowManagement.json"])
        if ProcessInfo.processInfo.environment["MF_WRITE_SAMPLES"] == "1" {
            try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
            for sample in samples {
                try sample.data.write(to: samplesDirectory.appendingPathComponent(sample.fileName), options: .atomic)
            }
        }
        for sample in samples {
            let onDisk = try Data(contentsOf: samplesDirectory.appendingPathComponent(sample.fileName))
            // Compared as JSON values: whitespace details of the encoder differ between platforms.
            let stored = try JSONSerialization.jsonObject(with: onDisk) as? NSDictionary
            let expected = try JSONSerialization.jsonObject(with: sample.data) as? NSDictionary
            XCTAssertNotNil(stored)
            XCTAssertEqual(stored, expected, "\(sample.fileName) is stale; run the tests with MF_WRITE_SAMPLES=1")
        }
    }

    func testEverySampleFileOnDiskImportsCleanly() throws {
        let files = try FileManager.default.contentsOfDirectory(at: samplesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 4)
        for file in files {
            let data = try Data(contentsOf: file)
            // Into an empty installation: nothing collides, nothing is untrusted.
            var empty = Fixtures.configuration()
            let preview = try ProfileTransfer.preview(data: data, current: empty)
            XCTAssertFalse(preview.isFullBackup, file.lastPathComponent)
            XCTAssertFalse(preview.profiles.isEmpty, file.lastPathComponent)
            XCTAssertTrue(preview.untrustedScripts.isEmpty, file.lastPathComponent)
            XCTAssertEqual(preview.warnings, [], file.lastPathComponent)
            XCTAssertTrue(preview.profiles.allSatisfy { !$0.bindings.isEmpty }, file.lastPathComponent)
            XCTAssertEqual(ProfileTransfer.apply(preview: preview, to: &empty, approveScripts: false), [])
            XCTAssertEqual(empty.profiles.count, 1 + preview.profiles.count)

            // Into the defaults: names collide, so copies are renamed and never overwrite.
            var defaults = DefaultConfiguration.make()
            let before = defaults
            let second = try ProfileTransfer.preview(data: data, current: defaults)
            ProfileTransfer.apply(preview: second, to: &defaults, approveScripts: false)
            XCTAssertEqual(Array(defaults.profiles.prefix(before.profiles.count)), before.profiles)
            XCTAssertEqual(Set(defaults.profiles.map { $0.name.lowercased() }).count, defaults.profiles.count)
        }
    }
}
