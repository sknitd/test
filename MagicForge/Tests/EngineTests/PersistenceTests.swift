import XCTest
import MFCore
import MFUtilities
import MFProfiles
@testable import MFEngine

final class PersistenceTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mf-engine-tests-\(UUID().uuidString)")
    }

    @MainActor func testFirstLaunchUsesDefaultsAndSavesThem() async {
        let harness = Harness(configuration: nil)
        XCTAssertFalse(harness.model.isRunning)
        harness.model.start()
        XCTAssertTrue(harness.model.isRunning)
        XCTAssertEqual(harness.model.configuration, DefaultConfiguration.make())
        XCTAssertEqual(harness.memoryStore.stored, DefaultConfiguration.make())
        XCTAssertNil(harness.model.persistenceError)
        XCTAssertEqual(harness.model.permissions[.accessibility], .granted)
        XCTAssertEqual(harness.model.devices, [TestConfig.mouse])
        harness.model.stop()
    }

    @MainActor func testUpdateIsSynchronousAndSavedAfterDebounce() async {
        let harness = Harness()
        harness.model.start()
        let savesBefore = harness.memoryStore.saveCount
        harness.model.update { $0.settings.animationsEnabled = false }
        harness.model.update { $0.recognizer.holdMinDuration = 0.7 }
        XCTAssertFalse(harness.model.configuration.settings.animationsEnabled)
        XCTAssertEqual(harness.memoryStore.saveCount, savesBefore, "saving is debounced")
        await harness.wait("debounced save") { harness.memoryStore.saveCount == savesBefore + 1 }
        XCTAssertEqual(harness.memoryStore.stored?.recognizer.holdMinDuration, 0.7)

        // A change that changes nothing does not save.
        harness.model.update { $0.settings.animationsEnabled = false }
        await harness.settle(0.15)
        XCTAssertEqual(harness.memoryStore.saveCount, savesBefore + 1)
        harness.model.stop()
    }

    @MainActor func testSaveNowFlushesAndStopSaves() async {
        let harness = Harness()
        harness.model.start()
        harness.model.update { $0.settings.showMenuBarIcon = false }
        harness.model.saveNow()
        XCTAssertEqual(harness.memoryStore.stored?.settings.showMenuBarIcon, false)
        let saves = harness.memoryStore.saveCount
        harness.model.saveNow()
        XCTAssertEqual(harness.memoryStore.saveCount, saves, "nothing pending, nothing written")

        harness.model.update { $0.settings.startMinimized = true }
        harness.model.stop()
        XCTAssertEqual(harness.memoryStore.stored?.settings.startMinimized, true)
    }

    @MainActor func testUpdateRepairsInvalidValues() async {
        let harness = Harness()
        harness.model.start()
        harness.model.update { $0.profiles.removeAll() }
        XCTAssertNotNil(harness.model.configuration.globalProfile, "the validator restores a global profile")
        harness.model.stop()
    }

    @MainActor func testChangesBeforeStartNeverReplaceTheStoredConfiguration() async {
        let stored = TestConfig.base()
        let harness = Harness(configuration: stored)
        harness.model.update { $0.settings.animationsEnabled = false }
        await harness.settle(0.15)
        harness.model.saveNow()
        XCTAssertEqual(harness.memoryStore.saveCount, 0)
        XCTAssertEqual(harness.memoryStore.stored, stored)
        harness.model.start()
        var expected = stored
        ConfigurationValidator.repair(&expected)
        XCTAssertEqual(harness.model.configuration, expected, "the stored configuration wins over pre-start edits")
        XCTAssertEqual(harness.memoryStore.saveCount, 0)
        harness.model.stop()
    }

    @MainActor func testConfigurationSurvivesRelaunchWithFileStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Harness(configuration: nil, store: JSONConfigurationStore(directory: directory))
        first.model.start()
        let script = ScriptAction.shell(command: "true")
        let created = first.model.addProfile(name: "Photos", bundleIdentifiers: ["com.example.photos"])
        first.model.update { $0.recognizer.swipeMinDistanceMM = 20 }
        first.model.approve(script)
        first.model.setCalibration(DeviceCalibration(), forDevice: TestConfig.mouse.id)
        first.model.stop()

        let second = Harness(configuration: nil, store: JSONConfigurationStore(directory: directory))
        second.model.start()
        XCTAssertNil(second.model.persistenceError)
        XCTAssertEqual(second.model.configuration, first.model.configuration)
        XCTAssertTrue(second.model.configuration.profiles.contains { $0.id == created.id && $0.name == "Photos" })
        XCTAssertEqual(second.model.configuration.recognizer.swipeMinDistanceMM, 20)
        XCTAssertTrue(second.model.isTrusted(script))
        second.model.stop()
    }

    @MainActor func testCorruptStoreFallsBackToDefaultsWithoutOverwriting() async {
        let store = MemoryStore()
        store.loadError = ConfigurationError.unreadable("The file is damaged.")
        let harness = Harness(store: store)
        harness.model.start()
        XCTAssertTrue(harness.model.isRunning)
        XCTAssertEqual(harness.model.configuration, DefaultConfiguration.make())
        XCTAssertNotNil(harness.model.persistenceError)
        XCTAssertTrue(harness.model.activityLog.contains { $0.level == .error })
        await harness.settle(0.15)
        XCTAssertEqual(store.saveCount, 0, "nothing is written until the user changes something")

        harness.model.update { $0.settings.animationsEnabled = false }
        harness.model.saveNow()
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertNil(harness.model.persistenceError)
        harness.model.stop()
    }

    @MainActor func testCorruptFileIsKeptAndBackupIsRestored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONConfigurationStore(directory: directory)
        var good = DefaultConfiguration.make()
        good.settings.animationsEnabled = false
        try store.save(good)
        try store.save(good) // the second save rolls the first into the backup slot
        try Data("{ this is not json".utf8).write(to: store.fileURL)

        let harness = Harness(configuration: nil, store: store)
        harness.model.start()
        XCTAssertNotNil(harness.model.persistenceError)
        XCTAssertEqual(harness.model.configuration.settings.animationsEnabled, false, "restored from the backup")
        XCTAssertEqual(store.corruptFiles().count, 1, "the damaged file is kept")
        harness.model.stop()
    }

    @MainActor func testNewerSchemaIsNeverOverwritten() async {
        let store = MemoryStore()
        store.loadError = ConfigurationError.unsupportedSchema(99)
        let harness = Harness(store: store)
        harness.model.start()
        harness.model.update { $0.settings.animationsEnabled = false }
        harness.model.saveNow()
        harness.model.stop()
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertNotNil(harness.model.persistenceError)
    }

    @MainActor func testSaveFailureIsReported() async {
        let harness = Harness()
        harness.model.start()
        harness.memoryStore.saveError = ConfigurationError.unreadable("Disk full.")
        harness.model.update { $0.settings.animationsEnabled = false }
        harness.model.saveNow()
        XCTAssertNotNil(harness.model.persistenceError)
        XCTAssertTrue(harness.model.activityLog.contains { $0.level == .error })

        harness.memoryStore.saveError = nil
        harness.model.saveNow()
        XCTAssertNil(harness.model.persistenceError)
        XCTAssertEqual(harness.memoryStore.stored?.settings.animationsEnabled, false)
        harness.model.stop()
    }

    @MainActor func testResetToDefaults() async {
        let harness = Harness()
        harness.model.start()
        harness.model.setProfileOverride(harness.model.configuration.profiles[1].id)
        harness.model.resetToDefaults()
        XCTAssertEqual(harness.model.configuration, DefaultConfiguration.make())
        XCTAssertNil(harness.model.profileOverrideID)
        XCTAssertEqual(harness.model.activeProfileID, DefaultConfiguration.make().globalProfileID)
        harness.model.stop()
    }

    @MainActor func testExportImportThroughTheModel() async throws {
        let script = ScriptAction.appleScript(source: "beep")
        let source = Harness()
        source.model.start()
        let editorID = source.model.configuration.profiles[1].id
        source.model.update { configuration in
            configuration.profiles[1].bindings.append(
                GestureBinding(trigger: .single(.threeFingerTap), action: .script(script)))
        }
        source.model.approve(script)
        let exported = try source.model.exportProfiles([editorID])
        let backup = try source.model.exportBackup()
        source.model.stop()

        let target = Harness(configuration: TestConfig.with([]))
        target.model.start()
        let preview = try target.model.previewImport(exported)
        XCTAssertFalse(preview.isFullBackup)
        XCTAssertEqual(preview.profiles.count, 1)
        XCTAssertEqual(preview.untrustedScripts, [script], "approvals never travel in files")
        XCTAssertEqual(target.model.configuration.profiles.count, 1, "a preview changes nothing")

        target.model.applyImport(preview, approveScripts: false)
        XCTAssertEqual(target.model.configuration.profiles.count, 2)
        XCTAssertFalse(target.model.isTrusted(script))
        XCTAssertEqual(target.model.untrustedScripts(), [script])

        let again = try target.model.previewImport(exported)
        target.model.applyImport(again, approveScripts: true)
        XCTAssertEqual(target.model.configuration.profiles.count, 3)
        XCTAssertTrue(target.model.isTrusted(script))

        let restore = try target.model.previewImport(backup)
        XCTAssertTrue(restore.isFullBackup)
        target.model.applyImport(restore, approveScripts: false)
        XCTAssertEqual(target.model.configuration.profiles.map(\.name), ["Global", "Editor"])
        XCTAssertTrue(target.model.isTrusted(script), "a script already approved on this Mac stays approved")

        XCTAssertThrowsError(try target.model.previewImport(Data("nonsense".utf8)))
        XCTAssertThrowsError(try target.model.exportProfiles([UUID()]))
        target.model.stop()
    }

    @MainActor func testProfileImportBringsItsAIPrompts() async throws {
        let template = PromptTemplate(name: "Summarize", userPrompt: "Summarize: {{input}}")
        let source = Harness(configuration: TestConfig.with([
            GestureBinding(trigger: .single(.twoFingerTap), action: .ai(templateID: template.id)),
        ]) { $0.ai.templates = [template] })
        source.model.start()
        let exported = try source.model.exportProfiles([source.model.configuration.globalProfileID])
        source.model.stop()

        let target = Harness(configuration: TestConfig.with([]))
        target.model.start()
        let preview = try target.model.previewImport(exported)
        target.model.applyImport(preview, approveScripts: false)
        XCTAssertEqual(target.model.configuration.ai.templates.map(\.name), ["Summarize"])
        XCTAssertFalse(target.model.configuration.ai.isEnabled, "importing never switches AI on")
        let imported = target.model.configuration.profiles.last
        let templateID = target.model.configuration.ai.templates.first?.id
        XCTAssertEqual(imported?.bindings.first?.action, templateID.map { .ai(templateID: $0) })
        target.model.stop()
    }

    @MainActor func testDuplicateProfile() async {
        let harness = Harness()
        harness.model.start()
        let original = harness.model.configuration.profiles[1]
        let copy = harness.model.duplicateProfile(original.id)
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy?.id, original.id)
        XCTAssertEqual(copy?.bindings.map(\.action), original.bindings.map(\.action))
        XCTAssertNotEqual(copy?.bindings.first?.id, original.bindings.first?.id)
        XCTAssertNil(harness.model.duplicateProfile(UUID()))
        harness.model.stop()
    }
}

extension Configuration {
    func with(_ mutate: (inout Configuration) -> Void) -> Configuration {
        var copy = self
        mutate(&copy)
        return copy
    }
}
