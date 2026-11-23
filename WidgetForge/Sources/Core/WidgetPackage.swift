import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The on-disk format of a shared widget (`.wfwidget`): one JSON document, no executables, no secrets.
struct WidgetPackage: Codable, Sendable {
    static let formatName = "widgetforge.widget"
    static let fileExtension = "wfwidget"

    var format: String
    var version: Int
    var exportedAt: Date
    var definition: WidgetDefinition
    /// SHA-256 of the canonical definition JSON. Detects corruption; it is not a signature.
    var checksum: String?
}

struct ImportedWidget: Sendable {
    var definition: WidgetDefinition
    var report: ValidationReport
    /// Imported scripts are never trusted automatically.
    var hasScript: Bool
    var requestedPermissions: PermissionManifest
}

enum PackageError: Error, LocalizedError, Equatable {
    case tooLarge
    case notAPackage
    case unsupportedVersion(Int)
    case checksumMismatch
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "The file is larger than 1 MB"
        case .notAPackage: return "This is not a WidgetForge widget file"
        case .unsupportedVersion(let v): return "This widget was made with a newer format (version \(v))"
        case .checksumMismatch: return "The file is damaged (checksum mismatch)"
        case .invalid(let errors): return errors.joined(separator: "\n")
        }
    }
}

enum WidgetPackageCodec {
    static let maxBytes = 1_000_000

    static func checksum(_ definition: WidgetDefinition) -> String? {
        #if canImport(CryptoKit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(definition) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    /// Serialise a definition for sharing. Credentials, file bookmarks and user state never leave the app.
    static func export(_ definition: WidgetDefinition, now: Date = Date()) throws -> Data {
        let clean = SecretScrubber.scrub(definition)
        let package = WidgetPackage(format: WidgetPackage.formatName, version: WidgetDefinition.currentFormatVersion,
                                    exportedAt: now, definition: clean, checksum: checksum(clean))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    /// Parse and validate an untrusted package. Accepts either a full package or a bare definition.
    static func importPackage(_ data: Data) throws -> ImportedWidget {
        guard data.count <= maxBytes else { throw PackageError.tooLarge }
        guard let json = try? JSONValue.parse(data), let object = json.objectValue else { throw PackageError.notAPackage }

        var definitionJSON = json
        var expectedChecksum: String?
        if let format = object["format"]?.stringValue {
            guard format == WidgetPackage.formatName, let inner = object["definition"] else { throw PackageError.notAPackage }
            let version = object["version"]?.intValue ?? 1
            guard version <= WidgetDefinition.currentFormatVersion else { throw PackageError.unsupportedVersion(version) }
            definitionJSON = inner
            expectedChecksum = object["checksum"]?.stringValue
        } else if object["root"] == nil {
            throw PackageError.notAPackage
        }

        let report = SchemaValidator.validate(definition: definitionJSON)
        guard report.isValid else { throw PackageError.invalid(report.errors) }
        var definition: WidgetDefinition
        do { definition = try definitionJSON.decode(WidgetDefinition.self) }
        catch { throw PackageError.invalid([error.localizedDescription]) }
        if let expectedChecksum, let actual = checksum(definition), actual != expectedChecksum { throw PackageError.checksumMismatch }

        definition.id = UUID().uuidString
        definition = SecretScrubber.scrub(definition)
        return ImportedWidget(definition: definition, report: report, hasScript: definition.hasScript,
                              requestedPermissions: definition.permissions)
    }
}
