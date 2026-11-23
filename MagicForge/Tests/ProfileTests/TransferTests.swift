import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class TransferTests: XCTestCase {
    private let direct = ScriptAction.shell(command: "direct")
    private let nested = ScriptAction.appleScript(source: "nested in workflow")
    private let inMenu = ScriptAction.shortcut(name: "in submenu")

    /// A source configuration whose "App" profile reaches a workflow, a menu and an AI prompt.
    private func source() -> (Configuration, Profile) {
        let template = PromptTemplate(name: "Translate", systemPrompt: "sys", userPrompt: "{{input}}")
        let inner = Workflow(name: "Inner", steps: [
            .conditional(.clipboardContains("x"), then: [.action(.script(nested))], otherwise: [.delay(seconds: 1)]),
        ])
        let outer = Workflow(name: "Outer", steps: [.action(.workflow(id: inner.id)), .action(.ai(templateID: template.id))])
        let menu = RadialMenu(name: "Tools", items: [
            RadialMenuItem(title: "Sub", children: [RadialMenuItem(title: "Script", action: .script(inMenu))]),
            RadialMenuItem(title: "Flow", action: .workflow(id: outer.id)),
        ], hotKey: KeyCombo(keyCode: 0x31, control: true, label: "⌃Space"))
        let unused = Workflow(name: "Unused", steps: [.action(.script(.shell(command: "never exported")))])
        let profile = Profile(name: "App", bundleIdentifiers: ["com.example.app"], bindings: [
            Fixtures.binding(.twoFingerTap, .script(direct)),
            Fixtures.binding(.threeFingerTap, .radialMenu(id: menu.id)),
            Fixtures.binding(.pinchIn, .workflow(id: outer.id)),
            Fixtures.binding(.pinchOut, .keyboard(KeyCombo(keyCode: 0x18, command: true, label: "⌘+"))),
        ])
        var configuration = Fixtures.configuration(global: [Fixtures.binding(.centerTap)],
                                                   profiles: [profile, Profile(name: "Other", bundleIdentifiers: ["o"])])
        configuration.workflows = [inner, outer, unused]
        configuration.radialMenus = [menu]
        configuration.ai.templates = [template, PromptTemplate(name: "Unused prompt")]
        return (configuration, profile)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testExportContainsOnlyWhatTheProfilesReference() throws {
        var (configuration, profile) = source()
        ScriptTrust.approve(direct, in: &configuration)
        let data = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        let envelope = try object(data)
        XCTAssertEqual(envelope["format"] as? String, "magicforge-profiles")
        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertNotNil(envelope["exportedAt"] as? String)
        XCTAssertEqual((envelope["profiles"] as? [Any])?.count, 1)
        XCTAssertEqual((envelope["workflows"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Inner", "Outer"])
        XCTAssertEqual((envelope["radialMenus"] as? [Any])?.count, 1)
        XCTAssertEqual((envelope["aiTemplates"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Translate"])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("approvedScriptHashes"))
        XCTAssertFalse(text.contains(ScriptTrust.hash(of: direct)))
        XCTAssertFalse(text.contains("never exported"))

        assertThrowsConfigurationError(try ProfileTransfer.exportProfiles([UUID()], from: configuration))
        XCTAssertEqual(try ProfileTransfer.exportProfiles([profile.id], from: configuration, exportedAt: nil),
                       try ProfileTransfer.exportProfiles([profile.id], from: configuration, exportedAt: nil))
    }

    func testImportRegeneratesIdentifiersAndRemapsReferences() throws {
        let (configuration, profile) = source()
        let data = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        // Import into the very configuration it came from: nothing may be overwritten.
        let preview = try ProfileTransfer.preview(data: data, current: configuration)
        XCTAssertFalse(preview.isFullBackup)
        XCTAssertEqual(preview.profiles.count, 1)
        XCTAssertEqual(preview.workflows.count, 2)
        XCTAssertEqual(preview.radialMenus.count, 1)

        let imported = preview.profiles[0]
        XCTAssertEqual(imported.name, "App (imported)")
        XCTAssertEqual(imported.bundleIdentifiers, ["com.example.app"])
        XCTAssertEqual(preview.workflows.map(\.name), ["Inner (imported)", "Outer (imported)"])
        XCTAssertEqual(preview.radialMenus[0].name, "Tools (imported)")
        XCTAssertNil(preview.radialMenus[0].hotKey, "an imported menu must not steal a shortcut that is in use")
        XCTAssertTrue(preview.warnings.contains { $0.contains("“App (imported)”") })
        XCTAssertTrue(preview.warnings.contains { $0.contains("both apply to com.example.app") })

        // Every identifier is new …
        var oldIDs: Set<UUID> = [profile.id]
        oldIDs.formUnion(profile.bindings.map(\.id))
        oldIDs.formUnion(configuration.workflows.map(\.id))
        oldIDs.formUnion(configuration.radialMenus.map(\.id))
        oldIDs.formUnion(configuration.radialMenus.flatMap { ActionTraversal.allItems(in: $0.items).map(\.id) })
        var newIDs: [UUID] = [imported.id]
        newIDs += imported.bindings.map(\.id)
        newIDs += preview.workflows.map(\.id)
        newIDs += preview.radialMenus.map(\.id)
        newIDs += ActionTraversal.allItems(in: preview.radialMenus[0].items).map(\.id)
        XCTAssertTrue(oldIDs.isDisjoint(with: newIDs))
        XCTAssertEqual(Set(newIDs).count, newIDs.count)

        // … and references follow the new identifiers.
        let inner = preview.workflows[0], outer = preview.workflows[1], menu = preview.radialMenus[0]
        XCTAssertEqual(imported.bindings.map(\.action), [
            .script(direct), .radialMenu(id: menu.id), .workflow(id: outer.id), profile.bindings[3].action,
        ])
        XCTAssertEqual(menu.items[1].action, .workflow(id: outer.id))
        XCTAssertEqual(menu.items[0].children[0].action, .script(inMenu))
        // The identical AI prompt is reused instead of duplicated.
        XCTAssertEqual(outer.steps, [.action(.workflow(id: inner.id)), .action(.ai(templateID: configuration.ai.templates[0].id))])
        XCTAssertTrue(ProfileTransfer.importedTemplates(in: preview).isEmpty)
        XCTAssertNil(preview.fullConfiguration)

        var target = configuration
        ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false)
        XCTAssertEqual(target.profiles.count, configuration.profiles.count + 1)
        XCTAssertEqual(Array(target.profiles.prefix(configuration.profiles.count)), configuration.profiles)
        XCTAssertEqual(Array(target.workflows.prefix(3)), configuration.workflows)
        XCTAssertEqual(target.workflows.count, 5)
        XCTAssertEqual(target.radialMenus.count, 2)
        XCTAssertEqual(target.ai.templates, configuration.ai.templates)
        XCTAssertFalse(ConfigurationValidator.issues(in: target).contains { $0.contains("no longer exists") })
    }

    func testImportIntoFreshConfigurationCarriesNewPrompts() throws {
        let (configuration, profile) = source()
        let data = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        var target = DefaultConfiguration.make()
        let preview = try ProfileTransfer.preview(data: data, current: target)
        XCTAssertEqual(preview.profiles[0].name, "App")
        XCTAssertFalse(preview.isFullBackup)
        let prompts = ProfileTransfer.importedTemplates(in: preview)
        XCTAssertEqual(prompts.map(\.name), ["Translate"])
        XCTAssertNotEqual(prompts[0].id, configuration.ai.templates[0].id)
        XCTAssertEqual(preview.workflows[1].steps.last, .action(.ai(templateID: prompts[0].id)))
        XCTAssertNotNil(preview.radialMenus[0].hotKey)

        let before = target
        XCTAssertEqual(ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false), [])
        XCTAssertEqual(target.ai.templates.count, before.ai.templates.count + 1)
        XCTAssertEqual(target.approvedScriptHashes, [])
        XCTAssertFalse(target.ai.isEnabled, "importing never switches AI on")
        XCTAssertEqual(target.settings, before.settings)
        let resolved = ProfileResolver.resolve(configuration: target, frontmostBundleID: "com.example.app")
        XCTAssertEqual(resolved.profileName, "App")
    }

    func testApplyingTheSamePreviewTwiceNeverOverwrites() throws {
        let (configuration, profile) = source()
        let data = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        var target = DefaultConfiguration.make()
        let preview = try ProfileTransfer.preview(data: data, current: target)
        ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false)
        let once = target
        ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false)
        XCTAssertEqual(target.profiles.count, once.profiles.count + 1)
        XCTAssertEqual(Array(target.profiles.prefix(once.profiles.count)), once.profiles)
        XCTAssertEqual(Set(target.profiles.map(\.id)).count, target.profiles.count)
        XCTAssertEqual(Set(target.workflows.map(\.id)).count, target.workflows.count)
        // The second copy still points at its own workflow, not the first copy's.
        let second = try XCTUnwrap(target.profiles.last)
        guard case .workflow(let id) = second.bindings[2].action else { return XCTFail("expected a workflow binding") }
        XCTAssertEqual(target.workflows.last?.id, id)
    }

    func testUntrustedScriptsIncludeNestedOnes() throws {
        let (configuration, profile) = source()
        let data = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        var target = DefaultConfiguration.make()
        ScriptTrust.approve(direct, in: &target)

        let preview = try ProfileTransfer.preview(data: data, current: target)
        XCTAssertEqual(Set(preview.untrustedScripts), [nested, inMenu], "the already approved script is not listed")
        XCTAssertTrue(preview.warnings.contains { $0.contains("2 script action(s)") })

        var declined = target
        ProfileTransfer.apply(preview: preview, to: &declined, approveScripts: false)
        XCTAssertEqual(declined.approvedScriptHashes, target.approvedScriptHashes)
        XCTAssertEqual(Set(ScriptTrust.untrustedScripts(in: declined)), [nested, inMenu])

        var approved = target
        ProfileTransfer.apply(preview: preview, to: &approved, approveScripts: true)
        XCTAssertTrue(ScriptTrust.untrustedScripts(in: approved).isEmpty)
        XCTAssertEqual(approved.approvedScriptHashes.count, 3)
    }

    func testApprovalsInAFileAreIgnored() throws {
        let (configuration, profile) = source()
        var envelope = try object(try ProfileTransfer.exportProfiles([profile.id], from: configuration))
        envelope["approvedScriptHashes"] = [ScriptTrust.hash(of: direct), ScriptTrust.hash(of: nested)]
        var target = DefaultConfiguration.make()
        let preview = try ProfileTransfer.preview(data: Fixtures.json(envelope), current: target)
        XCTAssertEqual(preview.untrustedScripts.count, 3)
        ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false)
        XCTAssertTrue(target.approvedScriptHashes.isEmpty)
    }

    func testBackupRoundTripKeepsApprovalsOnlyForIdenticalScripts() throws {
        var (original, _) = source()
        ScriptTrust.approve(direct, in: &original)
        ScriptTrust.approve(nested, in: &original)
        original.settings.gesturesPaused = true
        original.calibrations["device"] = DeviceCalibration()
        let data = try ProfileTransfer.exportBackup(original)
        let envelope = try object(data)
        XCTAssertEqual(envelope["format"] as? String, "magicforge-backup")
        XCTAssertEqual(((envelope["configuration"] as? [String: Any])?["approvedScriptHashes"] as? [Any])?.count, 0)

        // This Mac approved `direct` and something unrelated.
        var current = DefaultConfiguration.make()
        let unrelated = ScriptAction.shell(command: "unrelated")
        ScriptTrust.approve(direct, in: &current)
        ScriptTrust.approve(unrelated, in: &current)

        let preview = try ProfileTransfer.preview(data: data, current: current)
        XCTAssertTrue(preview.isFullBackup)
        XCTAssertEqual(preview.profiles, original.profiles)
        XCTAssertEqual(preview.fullConfiguration?.approvedScriptHashes, [])
        XCTAssertEqual(Set(preview.untrustedScripts), [nested, inMenu, .shell(command: "never exported")])
        XCTAssertTrue(preview.warnings[0].contains("replaces"))

        var restored = current
        ProfileTransfer.apply(preview: preview, to: &restored, approveScripts: false)
        var expected = original
        expected.approvedScriptHashes = [ScriptTrust.hash(of: direct)]
        XCTAssertEqual(restored, expected, "ids are kept, approvals survive only for identical scripts")

        var trusting = current
        ProfileTransfer.apply(preview: preview, to: &trusting, approveScripts: true)
        XCTAssertTrue(ScriptTrust.untrustedScripts(in: trusting).isEmpty)
        XCTAssertFalse(ScriptTrust.isTrusted(unrelated, in: trusting))
    }

    func testBackupWithInjectedApprovalsOrNewerSchema() throws {
        let (original, _) = source()
        var envelope = try object(try ProfileTransfer.exportBackup(original))
        var payload = try XCTUnwrap(envelope["configuration"] as? [String: Any])
        payload["approvedScriptHashes"] = [ScriptTrust.hash(of: direct)]
        envelope["configuration"] = payload
        var target = DefaultConfiguration.make()
        let preview = try ProfileTransfer.preview(data: Fixtures.json(envelope), current: target)
        ProfileTransfer.apply(preview: preview, to: &target, approveScripts: false)
        XCTAssertTrue(target.approvedScriptHashes.isEmpty)

        payload["schemaVersion"] = 7
        envelope["configuration"] = payload
        assertThrowsConfigurationError(try ProfileTransfer.preview(data: Fixtures.json(envelope), current: target)) {
            XCTAssertEqual($0, .unsupportedSchema(7))
        }
    }

    func testPartialProfileFileIsCompletedAndRepaired() throws {
        let file: [String: Any] = [
            "format": "magicforge-profiles", "version": 1,
            "profiles": [[
                "name": "Minimal",
                "bindings": [
                    ["trigger": ["single": ["_0": "pinchIn"]], "sensitivity": 40],
                    ["action": ["none": [String: Any]()]],
                    ["trigger": ["single": ["_0": "pinchOut"]], "action": ["workflow": ["id": UUID().uuidString]]],
                ],
            ]],
        ]
        let preview = try ProfileTransfer.preview(data: Fixtures.json(file), current: DefaultConfiguration.make())
        XCTAssertEqual(preview.profiles[0].bindings.count, 2)
        XCTAssertEqual(preview.profiles[0].bindings[0].sensitivity, 1)
        XCTAssertTrue(preview.warnings.contains { $0.contains("without a trigger") })
        XCTAssertTrue(preview.warnings.contains { $0.contains("out-of-range") })
        XCTAssertTrue(preview.warnings.contains { $0.contains("a workflow that no longer exists") })
    }

    func testInvalidInputsThrowInsteadOfCrashing() throws {
        let current = DefaultConfiguration.make()
        let (configuration, profile) = source()
        let valid = try object(try ProfileTransfer.exportProfiles([profile.id], from: configuration))
        func altered(_ change: (inout [String: Any]) -> Void) -> Data {
            var copy = valid
            change(&copy)
            return Fixtures.json(copy)
        }
        var random = [UInt8](repeating: 0, count: 4096)
        for index in random.indices { random[index] = UInt8((index &* 131 &+ 17) % 256) }

        let inputs: [(String, Data)] = [
            ("empty", Data()),
            ("garbage text", Data("not json at all".utf8)),
            ("binary", Data(random)),
            ("truncated", Data(Fixtures.json(valid).prefix(200))),
            ("array", Data("[1,2,3]".utf8)),
            ("string", Data("\"magicforge-profiles\"".utf8)),
            ("no format", altered { $0["format"] = nil }),
            ("wrong format", altered { $0["format"] = "other-app-export" }),
            ("format wrong type", altered { $0["format"] = 1 }),
            ("no version", altered { $0["version"] = nil }),
            ("version wrong type", altered { $0["version"] = "1" }),
            ("version zero", altered { $0["version"] = 0 }),
            ("version fraction", altered { $0["version"] = 1.5 }),
            ("no profiles", altered { $0["profiles"] = [Any]() }),
            ("profiles wrong type", altered { $0["profiles"] = "none" }),
            ("profile wrong type", altered { $0["profiles"] = [42] }),
            ("workflows wrong type", altered { $0["workflows"] = ["a": 1] }),
            ("bad field type", altered { $0["profiles"] = [["name": "X", "isEnabled": "maybe"]] }),
            ("bad id", altered { $0["profiles"] = [["name": "X", "id": "not-a-uuid"]] }),
            ("unknown gesture", altered { $0["profiles"] = [["name": "X", "bindings": [["trigger": ["single": ["_0": "wiggle"]]]]]] }),
            ("unknown action", altered { $0["profiles"] = [["name": "X", "bindings": [["trigger": ["single": ["_0": "pinchIn"]],
                                                                                         "action": ["explode": [String: Any]()]]]]] }),
            ("backup without configuration", Fixtures.json(["format": "magicforge-backup", "version": 1])),
            ("backup configuration wrong type", Fixtures.json(["format": "magicforge-backup", "version": 1, "configuration": [1]])),
        ]
        for (name, data) in inputs {
            do {
                _ = try ProfileTransfer.preview(data: data, current: current)
                XCTFail("\(name): expected an error")
            } catch is ConfigurationError {
                // expected
            } catch {
                XCTFail("\(name): expected ConfigurationError, got \(error)")
            }
        }
        assertThrowsConfigurationError(try ProfileTransfer.preview(data: altered { $0["version"] = 2 }, current: current)) {
            XCTAssertEqual($0, .unsupportedSchema(2))
        }
    }

    func testOversizedFileIsRejectedBeforeParsing() throws {
        let (configuration, profile) = source()
        var padded = try ProfileTransfer.exportProfiles([profile.id], from: configuration)
        padded.append(Data(repeating: 0x20, count: ProfileTransfer.maxImportSize + 1 - padded.count))
        XCTAssertEqual(padded.count, ProfileTransfer.maxImportSize + 1)
        assertThrowsConfigurationError(try ProfileTransfer.preview(data: padded, current: configuration)) { error in
            guard case .invalid(let message) = error else { return XCTFail("Expected invalid, got \(error)") }
            XCTAssertTrue(message.contains("5 MB"))
        }
        // Trailing whitespace up to the limit is still fine.
        XCTAssertNoThrow(try ProfileTransfer.preview(data: padded.dropLast(), current: configuration))
    }

    func testDeeplyNestedMenuDoesNotCrashAndIsFlattened() throws {
        var item: [String: Any] = ["title": "leaf"]
        for level in 0..<40 { item = ["title": "level \(level)", "children": [item]] }
        let file: [String: Any] = [
            "format": "magicforge-profiles", "version": 1,
            "profiles": [["name": "P"]],
            "radialMenus": [["name": "Deep", "items": [item]]],
        ]
        let preview = try ProfileTransfer.preview(data: Fixtures.json(file), current: DefaultConfiguration.make())
        func depth(_ items: [RadialMenuItem]) -> Int { items.isEmpty ? 0 : 1 + (items.map { depth($0.children) }.max() ?? 0) }
        XCTAssertEqual(depth(preview.radialMenus[0].items), ConfigurationValidator.maxRadialDepth)
    }
}
