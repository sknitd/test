import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class ScriptTrustTests: XCTestCase {
    private let vectors: [(String, String)] = [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        (String(repeating: "a", count: 55), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
        (String(repeating: "a", count: 56), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
        (String(repeating: "a", count: 63), "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
        (String(repeating: "a", count: 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
        (String(repeating: "a", count: 119), "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
        (String(repeating: "a", count: 120), "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"),
        (String(repeating: "a", count: 1_000_000), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"),
    ]

    func testPortableImplementationMatchesKnownVectors() {
        for (input, expected) in vectors {
            XCTAssertEqual(SHA256Pure.hexDigest(Data(input.utf8)), expected, "length \(input.utf8.count)")
        }
    }

    /// On Apple platforms this exercises CryptoKit, so both paths are pinned to the same vectors.
    func testPublicDigestMatchesKnownVectors() {
        for (input, expected) in vectors {
            XCTAssertEqual(ScriptTrust.sha256Hex(Data(input.utf8)), expected, "length \(input.utf8.count)")
        }
    }

    func testScriptHashCoversKindAndText() {
        XCTAssertEqual(ScriptTrust.hash(of: .shell(command: "echo hi")),
                       "568be606c3c9d9284bf2e507085d178dff52b5dfc671487fca1961c8796f165b")
        XCTAssertEqual(ScriptTrust.hash(of: .appleScript(source: "tell application \"Finder\" to activate — ü")),
                       "e1a4a1c1059b282871f9693ae8ad9896f153a7b2f0a2a1ecee6bbe981b204722")
        XCTAssertNotEqual(ScriptTrust.hash(of: .shell(command: "x")), ScriptTrust.hash(of: .shortcut(name: "x")))
        XCTAssertNotEqual(ScriptTrust.hash(of: .shell(command: "x")), ScriptTrust.hash(of: .shell(command: "x ")))
    }

    func testApproveAndRevoke() {
        var configuration = Fixtures.configuration()
        let script = ScriptAction.shell(command: "say hello")
        XCTAssertFalse(ScriptTrust.isTrusted(script, in: configuration))
        ScriptTrust.approve(script, in: &configuration)
        XCTAssertTrue(ScriptTrust.isTrusted(script, in: configuration))
        XCTAssertFalse(ScriptTrust.isTrusted(.shell(command: "say hello!"), in: configuration))
        XCTAssertTrue(ConfigurationValidator.issues(in: configuration).isEmpty, "approvals are valid digests")
        ScriptTrust.revoke(script, in: &configuration)
        XCTAssertFalse(ScriptTrust.isTrusted(script, in: configuration))
        XCTAssertTrue(configuration.approvedScriptHashes.isEmpty)
    }

    func testCollectsScriptsEverywhere() {
        let direct = ScriptAction.shell(command: "direct")
        let inStep = ScriptAction.appleScript(source: "step")
        let inBranch = ScriptAction.shortcut(name: "branch")
        let inElse = ScriptAction.shell(command: "else")
        let inSubmenu = ScriptAction.shell(command: "submenu")
        let unreferenced = ScriptAction.shell(command: "orphan")

        let nested = Workflow(name: "Nested", steps: [
            .action(.script(inStep)),
            .conditional(.clipboardContains("x"),
                         then: [.conditional(.appIsRunning(bundleID: "a"), then: [.action(.script(inBranch))], otherwise: [])],
                         otherwise: [.action(.script(inElse)), .action(.script(inStep))]),
        ])
        let orphan = Workflow(name: "Orphan", steps: [.action(.script(unreferenced))])
        let menu = RadialMenu(name: "Menu", items: [
            RadialMenuItem(title: "Sub", children: [
                RadialMenuItem(title: "Deep", children: [RadialMenuItem(title: "Leaf", action: .script(inSubmenu))]),
                RadialMenuItem(title: "Run workflow", action: .workflow(id: nested.id)),
            ]),
        ])
        let profile = Profile(name: "App", bundleIdentifiers: ["com.example"], bindings: [
            Fixtures.binding(.twoFingerTap, .script(direct)),
            Fixtures.binding(.threeFingerTap, .radialMenu(id: menu.id)),
            Fixtures.binding(.centerTap, .script(direct), enabled: false),
        ])
        var configuration = Fixtures.configuration(profiles: [profile])
        configuration.workflows = [nested, orphan]
        configuration.radialMenus = [menu]

        XCTAssertEqual(ScriptTrust.scripts(in: profile), [direct])
        XCTAssertEqual(ScriptTrust.scripts(in: nested), [inStep, inBranch, inElse])
        XCTAssertEqual(ScriptTrust.scripts(in: nested.steps), [inStep, inBranch, inElse])
        XCTAssertEqual(ScriptTrust.scripts(in: menu), [inSubmenu])
        XCTAssertEqual(Set(ScriptTrust.scripts(in: configuration)),
                       [direct, inStep, inBranch, inElse, inSubmenu, unreferenced])
        // Through the menu, and through the workflow the submenu starts.
        XCTAssertEqual(Set(ScriptTrust.scripts(in: profile, resolvingReferencesIn: configuration)),
                       [direct, inStep, inBranch, inElse, inSubmenu])
        XCTAssertEqual(Set(ScriptTrust.scripts(reachableFrom: .workflow(id: nested.id), in: configuration)),
                       [inStep, inBranch, inElse])
        XCTAssertEqual(ScriptTrust.scripts(reachableFrom: .script(direct), in: configuration), [direct])
        XCTAssertTrue(ScriptTrust.scripts(reachableFrom: .workflow(id: UUID()), in: configuration).isEmpty)

        ScriptTrust.approve(direct, in: &configuration)
        XCTAssertEqual(Set(ScriptTrust.untrustedScripts(in: configuration)),
                       [inStep, inBranch, inElse, inSubmenu, unreferenced])
        XCTAssertTrue(ScriptTrust.untrustedScripts(reachableFrom: .script(direct), in: configuration).isEmpty)
        XCTAssertEqual(ScriptTrust.untrustedScripts(reachableFrom: .radialMenu(id: menu.id), in: configuration).count, 4)
    }

    func testReferenceCyclesTerminate() {
        let firstID = UUID(), secondID = UUID(), menuID = UUID()
        let script = ScriptAction.shell(command: "loop")
        var configuration = Fixtures.configuration()
        configuration.workflows = [
            Workflow(id: firstID, name: "A", steps: [.action(.workflow(id: secondID))]),
            Workflow(id: secondID, name: "B", steps: [.action(.radialMenu(id: menuID)), .action(.script(script))]),
        ]
        configuration.radialMenus = [RadialMenu(id: menuID, name: "M", items: [
            RadialMenuItem(title: "Back", action: .workflow(id: firstID)),
        ])]
        XCTAssertEqual(ScriptTrust.scripts(reachableFrom: .workflow(id: firstID), in: configuration), [script])
    }
}
