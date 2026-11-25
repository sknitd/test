import Foundation

/// A complete, portable copy of a WidgetForge setup: widgets with their state and placement, saved layouts,
/// profiles, automations, the personal library and app settings. Secrets and file bookmarks are never included.
struct BackupArchive: Codable, Sendable {
    static let formatName = "widgetforge.backup"
    static let currentVersion = 1
    static let fileExtension = "wfbackup"

    var format: String = BackupArchive.formatName
    var version: Int = BackupArchive.currentVersion
    var createdAt: Date = Date()
    var widgets: [WidgetInstance] = []
    var layouts: [SavedLayout] = []
    var profiles: [Profile] = []
    var activeProfileID: String?
    var rules: [AutomationRule] = []
    var library: [WidgetDefinition] = []
    /// App settings as opaque JSON, so the core does not depend on the app's settings type.
    var settings: JSONValue?
}

enum BackupError: Error, LocalizedError, Equatable {
    case tooLarge
    case notABackup
    case unsupportedVersion(Int)
    case invalidWidget(String, [String])

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "The backup file is larger than 25 MB"
        case .notABackup: return "This is not a WidgetForge backup"
        case .unsupportedVersion(let v): return "This backup was made by a newer version of WidgetForge (format \(v))"
        case .invalidWidget(let name, let errors): return "The backup contains an invalid widget “\(name)”: " + errors.joined(separator: "; ")
        }
    }
}

enum BackupCodec {
    static let maxBytes = 25_000_000

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Serialise a backup. Credentials are scrubbed from every definition exactly as for a shared widget;
    /// unlike a shared widget, a backup keeps your widget state (notes, to-dos) because it is your own copy.
    static func encode(_ archive: BackupArchive) throws -> Data {
        var clean = archive
        clean.format = BackupArchive.formatName
        clean.version = BackupArchive.currentVersion
        for i in clean.widgets.indices {
            clean.widgets[i].definition = SecretScrubber.scrub(clean.widgets[i].definition)
            clean.widgets[i].granted.files = []
        }
        clean.library = clean.library.map(SecretScrubber.scrub)
        return try encoder.encode(clean)
    }

    /// Parse and validate a backup file. A backup is a file like any other, so it is not trusted blindly:
    /// every definition is schema-validated, and scripts come back **untrusted** and must be re-enabled by hand.
    static func decode(_ data: Data) throws -> BackupArchive {
        guard data.count <= maxBytes else { throw BackupError.tooLarge }
        guard let json = try? JSONValue.parse(data), json["format"]?.stringValue == BackupArchive.formatName else { throw BackupError.notABackup }
        let version = json["version"]?.intValue ?? 1
        guard version <= BackupArchive.currentVersion else { throw BackupError.unsupportedVersion(version) }
        for definition in (json["widgets"]?.arrayValue ?? []).compactMap({ $0["definition"] }) + (json["library"]?.arrayValue ?? []) {
            let report = SchemaValidator.validate(definition: definition)
            guard report.isValid else { throw BackupError.invalidWidget(definition["name"]?.stringValue ?? "?", report.errors) }
        }
        var archive: BackupArchive
        do { archive = try decoder.decode(BackupArchive.self, from: data) }
        catch { throw BackupError.notABackup }
        for i in archive.widgets.indices {
            archive.widgets[i].definition = SecretScrubber.scrub(archive.widgets[i].definition)
            archive.widgets[i].scriptTrusted = false
            archive.widgets[i].granted.scripting = false
            archive.widgets[i].granted.files = []
            // A backup can only restore permissions the widget's own manifest asks for.
            archive.widgets[i].granted = archive.widgets[i].granted.intersection(archive.widgets[i].definition.permissions)
        }
        archive.library = archive.library.map(SecretScrubber.scrub)
        // Drop references to things that are not in the archive.
        let ids = Set(archive.widgets.map(\.id))
        for i in archive.profiles.indices {
            archive.profiles[i].widgetIDs = archive.profiles[i].widgetIDs.filter { ids.contains($0) }
            archive.profiles[i].placements = archive.profiles[i].placements.filter { ids.contains($0.key) }
        }
        if let active = archive.activeProfileID, !archive.profiles.contains(where: { $0.id == active }) { archive.activeProfileID = nil }
        return archive
    }
}

extension ProfileManager {
    func replaceAll(_ newProfiles: [Profile], activeID: String?) {
        for profile in profiles { delete(profile.id) }
        for profile in newProfiles { upsert(profile) }
        activate(activeID)
    }
}

/// Commands accepted through the `widgetforge://` URL scheme, for use from Shortcuts, scripts and launchers.
///
/// Any app or web page can open a URL, so the set is deliberately small: nothing here can install arbitrary
/// content, read data or change permissions. Commands that add a widget or run an automation are marked
/// `needsConfirmation`, and the app asks the user before acting on them.
enum DeepLinkCommand: Equatable, Sendable {
    case showWidgets, hideWidgets, toggleWidgets
    case editMode(Bool)
    case pauseUpdates(Bool)
    case profile(String?)            // name or id; nil = All Widgets
    case theme(String)
    case tidy(TileMode)
    case open(String)                // section
    case commandCenter
    case runAutomation(String)       // rule name or id
    case addTemplate(String)         // built-in template name

    var needsConfirmation: Bool {
        switch self {
        case .runAutomation, .addTemplate: return true
        default: return false
        }
    }

    static let scheme = "widgetforge"

    static func parse(_ url: URL) -> DeepLinkCommand? {
        guard url.scheme?.lowercased() == scheme, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // Accept both widgetforge://show and widgetforge:show.
        let command = (components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name.lowercased()] = item.value ?? "" }
        func flag(default fallback: Bool) -> Bool {
            guard let raw = query["on"]?.lowercased() else { return fallback }
            return ["1", "true", "yes", "on"].contains(raw)
        }
        func text(_ key: String) -> String? {
            guard let value = query[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty, value.count <= 120 else { return nil }
            return value
        }
        switch command {
        case "show": return .showWidgets
        case "hide": return .hideWidgets
        case "toggle": return .toggleWidgets
        case "edit": return .editMode(flag(default: true))
        case "pause": return .pauseUpdates(flag(default: true))
        case "resume": return .pauseUpdates(false)
        case "profile": return .profile(text("name") ?? text("id"))
        case "theme": return text("name").map { .theme($0) }
        case "tidy": return TileMode(rawValue: query["edge"]?.lowercased() ?? "left").map { .tidy($0) }
        case "open": return text("section").map { .open($0.lowercased()) }
        case "command-center", "commands": return .commandCenter
        case "run": return (text("name") ?? text("id")).map { .runAutomation($0) }
        case "add": return text("template").map { .addTemplate($0) }
        default: return nil
        }
    }
}
