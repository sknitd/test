import XCTest
@testable import WidgetForgeKit

final class SecurityTests: XCTestCase {
    func testHostAllowlistMatching() {
        XCTAssertTrue(PermissionChecker.hostAllowed("api.github.com", allowlist: ["api.github.com"]))
        XCTAssertTrue(PermissionChecker.hostAllowed("API.GitHub.com", allowlist: ["api.github.com"]))
        XCTAssertTrue(PermissionChecker.hostAllowed("api.github.com", allowlist: ["*.github.com"]))
        XCTAssertFalse(PermissionChecker.hostAllowed("github.com", allowlist: ["*.github.com"]))
        XCTAssertFalse(PermissionChecker.hostAllowed("evilgithub.com", allowlist: ["*.github.com", "github.com"]))
        XCTAssertFalse(PermissionChecker.hostAllowed("api.github.com.evil.io", allowlist: ["api.github.com"]))
        XCTAssertFalse(PermissionChecker.hostAllowed("anything.com", allowlist: []))
        XCTAssertFalse(PermissionChecker.hostAllowed("printer.local", allowlist: ["*.local"]), "wildcards never cover local hosts")
        XCTAssertTrue(PermissionChecker.isLocal("127.0.0.1"))
        XCTAssertTrue(PermissionChecker.isLocal("192.168.1.20"))
        XCTAssertTrue(PermissionChecker.isLocal("172.20.0.4"))
        XCTAssertFalse(PermissionChecker.isLocal("172.40.0.4"))
        XCTAssertFalse(PermissionChecker.isLocal("example.com"))
    }

    func testManifestSetOperations() {
        let requested = PermissionManifest(network: ["a.com", "b.com"], systemMetrics: true, clipboard: true)
        let granted = PermissionManifest(network: ["a.com"], systemMetrics: true)
        let effective = requested.intersection(granted)
        XCTAssertEqual(effective.network, ["a.com"])
        XCTAssertTrue(effective.systemMetrics)
        XCTAssertFalse(effective.clipboard)
        let missing = PermissionChecker.missing(required: requested, granted: granted)
        XCTAssertEqual(missing.network, ["b.com"])
        XCTAssertTrue(missing.clipboard)
        XCTAssertFalse(missing.systemMetrics)
    }

    func testInstancePermissionsAndRevocation() {
        let store = WidgetStore(db: InMemoryDocumentStore())
        let imported = store.create(from: TemplateLibrary.customScript, granted: PermissionManifest.none, origin: .imported)
        XCTAssertFalse(imported.scriptEnabled, "imported scripts are off by default")
        XCTAssertTrue(imported.effectivePermissions.isEmpty)
        store.update(imported.id) { $0.granted = $0.definition.permissions; $0.scriptTrusted = true }
        XCTAssertTrue(store.widget(imported.id)!.scriptEnabled)
        store.update(imported.id) { $0.granted.scripting = false }
        XCTAssertFalse(store.widget(imported.id)!.scriptEnabled, "revoking takes effect immediately")
    }

    func testRequiredPermissionsAreDerivedFromContent() {
        let definition = WidgetDefinition(
            name: "Mixed", size: WidgetSize(200, 200),
            root: .column([
                .button("Open", action: .openURL("https://apple.com")),
                .button("Run", action: .runShortcut("Focus")),
                WidgetNode(.clipboard), WidgetNode(.web, props: ["url": "https://news.example.com/top"]),
            ]),
            dataSources: [.metric("cpu"), DataSourceConfig(id: "api", kind: .rest, url: "https://api.example.com/v1?x={{settings.q}}"),
                          DataSourceConfig(id: "f", kind: .jsonFile, fileID: "file-1")],
            script: "WidgetForge.defineWidget({render(){return {type:'text'}}})")
        let required = PermissionChecker.required(for: definition)
        XCTAssertEqual(required.network, ["api.example.com"])
        XCTAssertEqual(required.webContent, ["news.example.com"])
        XCTAssertEqual(required.files, ["file-1"])
        XCTAssertTrue(required.systemMetrics && required.openURLs && required.shortcuts && required.clipboard && required.scripting)
        XCTAssertFalse(required.calendar || required.launchApps || required.mediaControl)
    }

    func testValidSchemaPasses() throws {
        let json = try JSONValue.encode(TemplateLibrary.cpuMonitor)
        let report = SchemaValidator.validate(definition: json)
        XCTAssertTrue(report.isValid, report.errors.joined(separator: "; "))
        XCTAssertTrue(report.warnings.isEmpty, report.warnings.joined(separator: "; "))
    }

    func testInvalidSchemasAreRejected() {
        func errors(_ json: JSONValue) -> [String] { SchemaValidator.validate(definition: json).errors }
        XCTAssertFalse(errors("just a string").isEmpty)
        XCTAssertFalse(errors(["root": ["type": "text"]]).isEmpty, "missing name")
        XCTAssertFalse(errors(["name": "X"]).isEmpty, "missing root")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "iframe"]]).isEmpty, "unknown component")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "size": ["width": 5, "height": 99999]]).isEmpty)
        XCTAssertFalse(errors(["name": "X", "root": ["type": "button", "action": ["type": "exec", "cmd": "ls"]]]).isEmpty, "unknown action")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "web", "url": "file:///etc/passwd"]]).isEmpty, "file: scheme")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "image", "url": "javascript:alert(1)"]]).isEmpty)
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "dataSources": [["id": "a", "kind": "shell"]]]).isEmpty)
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "dataSources": [["id": "a", "kind": "rest", "url": "https://{{settings.host}}/x"]]]).isEmpty, "templated host")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "dataSources": [["id": "a", "kind": "rest", "url": "https://user:pw@example.com/"]]]).isEmpty)
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "dataSources": [
            ["id": "a", "kind": "rest", "url": "https://example.com/", "headers": ["Authorization": "Bearer abc123"]]]]).isEmpty, "inline credential")
        XCTAssertFalse(errors(["name": "X", "root": ["type": "text"], "dataSources": [
            ["id": "a", "kind": "time"], ["id": "a", "kind": "time"]]]).isEmpty, "duplicate ids")
    }

    func testDepthAndSizeLimits() {
        var deep: JSONValue = ["type": "text", "value": "leaf"]
        for _ in 0..<20 { deep = ["type": "column", "children": [deep]] }
        XCTAssertFalse(SchemaValidator.validate(definition: ["name": "Deep", "root": deep]).isValid)

        let wide: JSONValue = ["type": "column", "children": .array(Array(repeating: ["type": "text", "value": "x"], count: 500))]
        XCTAssertFalse(SchemaValidator.validate(definition: ["name": "Wide", "root": wide]).isValid)

        let long: JSONValue = ["type": "text", "value": .string(String(repeating: "a", count: 30_000))]
        XCTAssertFalse(SchemaValidator.validate(definition: ["name": "Long", "root": long]).isValid)
    }

    func testUndeclaredCapabilitiesProduceWarning() {
        let json: JSONValue = ["name": "Sneaky", "root": ["type": "text", "value": "{{api.x}}"],
                               "dataSources": [["id": "api", "kind": "rest", "url": "https://tracker.example.net/ping"]]]
        let report = SchemaValidator.validate(definition: json)
        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.warnings.contains { $0.contains("tracker.example.net") })
    }

    func testExportNeverContainsSecretsOrState() throws {
        var definition = TemplateLibrary.stocks
        definition.dataSources.append(DataSourceConfig(id: "private", kind: .rest, url: "https://api.example.com/v1?api_key=LIVE-KEY-123&q=1",
                                                       headers: ["Authorization": "Bearer LIVE-TOKEN-456", "Accept": "application/json"]))
        definition.dataSources.append(DataSourceConfig(id: "file", kind: .jsonFile, fileID: "bookmark-9"))
        definition.settings["apiToken"] = "LIVE-SETTING-789"
        definition.permissions.files = ["bookmark-9"]
        let text = String(decoding: try WidgetPackageCodec.export(definition), as: UTF8.self)
        for leaked in ["LIVE-KEY-123", "LIVE-TOKEN-456", "LIVE-SETTING-789", "bookmark-9"] {
            XCTAssertFalse(text.contains(leaked), "\(leaked) leaked into the export")
        }
        XCTAssertTrue(text.contains("{{secret:AUTHORIZATION}}"))
        XCTAssertTrue(text.contains("{{secret:API_KEY}}"))
        XCTAssertTrue(text.contains("q=1"))
        XCTAssertTrue(text.contains("{{secret:FINNHUB_API_KEY}}"), "existing placeholders are kept")
    }

    func testPackageRoundTrip() throws {
        let data = try WidgetPackageCodec.export(TemplateLibrary.weather)
        let imported = try WidgetPackageCodec.importPackage(data)
        XCTAssertEqual(imported.definition.name, "Weather")
        XCTAssertEqual(imported.definition.root, TemplateLibrary.weather.root)
        XCTAssertEqual(imported.requestedPermissions.network, ["api.open-meteo.com"])
        XCTAssertNotEqual(imported.definition.id, TemplateLibrary.weather.id)
        XCTAssertFalse(imported.hasScript)
        XCTAssertTrue(try WidgetPackageCodec.importPackage(try WidgetPackageCodec.export(TemplateLibrary.customScript)).hasScript)
    }

    func testImportRejectsBadPackages() throws {
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data("not json".utf8))) { XCTAssertEqual($0 as? PackageError, .notAPackage) }
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data("{\"hello\":1}".utf8))) { XCTAssertEqual($0 as? PackageError, .notAPackage) }
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data(count: WidgetPackageCodec.maxBytes + 1))) { XCTAssertEqual($0 as? PackageError, .tooLarge) }
        let future = "{\"format\":\"widgetforge.widget\",\"version\":99,\"definition\":{\"name\":\"X\",\"root\":{\"type\":\"text\"}}}"
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data(future.utf8))) { XCTAssertEqual($0 as? PackageError, .unsupportedVersion(99)) }
        let invalid = "{\"name\":\"X\",\"root\":{\"type\":\"nope\"}}"
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data(invalid.utf8))) {
            guard case .invalid = $0 as? PackageError else { return XCTFail("expected .invalid, got \($0)") }
        }
        #if canImport(CryptoKit)
        var text = String(decoding: try WidgetPackageCodec.export(TemplateLibrary.notes), as: UTF8.self)
        text = text.replacingOccurrences(of: "Write something…", with: "Tampered")
        XCTAssertThrowsError(try WidgetPackageCodec.importPackage(Data(text.utf8))) { XCTAssertEqual($0 as? PackageError, .checksumMismatch) }
        #endif
    }

    func testBareDefinitionImports() throws {
        let bare = "{\"name\":\"Bare\",\"root\":{\"type\":\"column\",\"children\":[{\"type\":\"text\",\"value\":\"Hi\"}]}}"
        let imported = try WidgetPackageCodec.importPackage(Data(bare.utf8))
        XCTAssertEqual(imported.definition.name, "Bare")
        XCTAssertEqual(imported.definition.size, WidgetSize(320, 200))
        XCTAssertTrue(imported.requestedPermissions.isEmpty)
    }
}

final class TemplateTests: XCTestCase {
    func testThereAreTwentyFiveUniqueTemplates() {
        XCTAssertEqual(TemplateLibrary.all.count, 25)
        XCTAssertEqual(Set(TemplateLibrary.all.map(\.name)).count, 25)
    }

    func testEveryTemplatePassesValidation() throws {
        for template in TemplateLibrary.all {
            let report = SchemaValidator.validate(definition: try JSONValue.encode(template))
            XCTAssertTrue(report.isValid, "\(template.name): \(report.errors.joined(separator: "; "))")
        }
    }

    func testTemplatesDeclareEverythingTheyUse() {
        for template in TemplateLibrary.all {
            let missing = PermissionChecker.missing(required: PermissionChecker.required(for: template), granted: template.permissions)
            XCTAssertTrue(missing.isEmpty, "\(template.name) uses undeclared permissions: \(missing.descriptions)")
        }
    }

    func testTemplatesSurviveCodableRoundTrip() throws {
        for template in TemplateLibrary.all {
            let decoded = try JSONDecoder().decode(WidgetDefinition.self, from: JSONEncoder().encode(template))
            XCTAssertEqual(decoded, template, template.name)
        }
    }

    func testNetworkTemplatesExplainTheirSetup() {
        for template in TemplateLibrary.all where template.dataSources.contains(where: { $0.kind.usesNetwork }) {
            XCTAssertFalse((template.setupInstructions ?? "").isEmpty, "\(template.name) needs setup instructions")
        }
        XCTAssertEqual(TemplateLibrary.stocks.dataSources[0].secretNames, ["FINNHUB_API_KEY"])
    }

    func testTemplatesShipNoSampleData() {
        // Stateful templates start empty; nothing pretends to be live.
        XCTAssertEqual(TemplateLibrary.notes.initialState["text"], "")
        XCTAssertEqual(TemplateLibrary.todo.initialState["items"], [])
        for template in TemplateLibrary.all {
            for source in template.dataSources { XCTAssertNil(source.value, "\(template.name) embeds static data") }
        }
    }
}

final class ExampleFilesTests: XCTestCase {
    func testShippedExampleWidgetFilesImportCleanly() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Templates")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == WidgetPackage.fileExtension }
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for file in files {
            let imported = try WidgetPackageCodec.importPackage(try Data(contentsOf: file))
            XCTAssertTrue(imported.report.isValid, file.lastPathComponent)
            let missing = PermissionChecker.missing(required: PermissionChecker.required(for: imported.definition), granted: imported.requestedPermissions)
            XCTAssertTrue(missing.isEmpty, "\(file.lastPathComponent) under-declares: \(missing.descriptions)")
        }
    }
}
