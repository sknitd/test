import Foundation
import MFCore

/// Import and export of profiles and full backups.
///
/// Files are JSON envelopes: `{"format": "magicforge-profiles" | "magicforge-backup", "version": 1, …}`.
/// Importing is always two steps — `preview` (parse, validate, list untrusted scripts; changes
/// nothing) and `apply`. Script approvals never travel in files: exports omit them and imports
/// ignore them.
public enum ProfileTransfer {
    public static let profilesFormat = "magicforge-profiles"
    public static let backupFormat = "magicforge-backup"
    public static let currentVersion = 1
    /// Larger files are rejected before parsing.
    public static let maxImportSize = 5 * 1024 * 1024

    // MARK: Export

    /// Exports the given profiles together with every workflow, radial menu and AI prompt they
    /// refer to (directly or through other workflows / menus). Pass `exportedAt: nil` for
    /// byte-for-byte reproducible output.
    public static func exportProfiles(_ ids: [UUID], from configuration: Configuration,
                                      exportedAt: Date? = Date()) throws -> Data {
        let wanted = Set(ids)
        let profiles = configuration.profiles.filter { wanted.contains($0.id) }
        guard !profiles.isEmpty else { throw ConfigurationError.invalid("There are no profiles to export.") }
        let references = ReferenceSet.reachable(from: profiles.flatMap(ActionTraversal.actions(in:)), in: configuration)
        let envelope = ProfilesEnvelope(
            format: profilesFormat, version: currentVersion, app: "MagicForge", exportedAt: timestamp(exportedAt),
            profiles: profiles,
            workflows: configuration.workflows.filter { references.workflows.contains($0.id) },
            radialMenus: configuration.radialMenus.filter { references.radialMenus.contains($0.id) },
            aiTemplates: configuration.ai.templates.filter { references.templates.contains($0.id) })
        return try ConfigurationJSON.encode(envelope)
    }

    /// Exports everything except script approvals (and the AI key, which is never in the
    /// configuration).
    public static func exportBackup(_ configuration: Configuration, exportedAt: Date? = Date()) throws -> Data {
        var copy = configuration
        copy.approvedScriptHashes = []
        return try ConfigurationJSON.encode(BackupEnvelope(format: backupFormat, version: currentVersion, app: "MagicForge",
                                                           exportedAt: timestamp(exportedAt), configuration: copy))
    }

    // MARK: Import

    /// Parses and validates an import file without changing anything.
    ///
    /// Profile files: every identifier is regenerated (references inside the file follow), names
    /// that already exist get an " (imported)" suffix, and AI prompts identical to existing ones
    /// are reused. New AI prompts travel in `fullConfiguration.ai.templates` with
    /// `isFullBackup == false`, because `ImportPreview` has no field for them.
    ///
    /// - Throws: `ConfigurationError` for anything that is not a supported MagicForge file.
    public static func preview(data: Data, current: Configuration) throws -> ImportPreview {
        guard !data.isEmpty else { throw ConfigurationError.invalid("The file is empty.") }
        guard data.count <= maxImportSize else {
            throw ConfigurationError.invalid("The file is larger than 5 MB, which is more than any MagicForge export.")
        }
        let object = try ConfigurationJSON.parseObject(data)
        guard let format = object["format"] as? String else {
            throw ConfigurationError.invalid("This is not a MagicForge export (no format marker).")
        }
        guard let version = try ConfigurationJSON.integer("version", in: object), version >= 1 else {
            throw ConfigurationError.invalid("The file has no valid format version.")
        }
        guard version <= currentVersion else { throw ConfigurationError.unsupportedSchema(version) }
        switch format {
        case profilesFormat: return try previewProfiles(object, current: current)
        case backupFormat: return try previewBackup(object, current: current)
        default: throw ConfigurationError.invalid("This is not a MagicForge export (unknown format).")
        }
    }

    /// Applies a previewed import and returns the validator's notes.
    ///
    /// Profile imports are added next to what exists. A full backup replaces the configuration;
    /// approvals are kept only for scripts whose text is identical to one already approved here.
    /// With `approveScripts` every script in the import is approved as well.
    @discardableResult
    public static func apply(preview: ImportPreview, to configuration: inout Configuration,
                             approveScripts: Bool) -> [String] {
        if preview.isFullBackup {
            guard var restored = preview.fullConfiguration else { return ["The backup contained no configuration."] }
            restored.approvedScriptHashes = []
            for script in ScriptTrust.scripts(in: restored) {
                let hash = ScriptTrust.hash(of: script)
                if approveScripts || configuration.approvedScriptHashes.contains(hash) {
                    restored.approvedScriptHashes.insert(hash)
                }
            }
            let notes = ConfigurationValidator.repair(&restored)
            configuration = restored
            return notes
        }
        var bundle = ImportBundle(profiles: preview.profiles, workflows: preview.workflows,
                                  radialMenus: preview.radialMenus, templates: importedTemplates(in: preview))
        // The preview may be stale by now; never overwrite anything that appeared since.
        if bundle.collides(with: configuration) { bundle.regenerateIdentifiers(reusing: [:]) }
        configuration.profiles += bundle.profiles
        configuration.workflows += bundle.workflows
        configuration.radialMenus += bundle.radialMenus
        configuration.ai.templates += bundle.templates
        if approveScripts {
            for script in bundle.scripts { ScriptTrust.approve(script, in: &configuration) }
        }
        return ConfigurationValidator.repair(&configuration)
    }

    /// AI prompts a profile import would add (empty for full backups: those are inside
    /// `fullConfiguration` like everything else).
    public static func importedTemplates(in preview: ImportPreview) -> [PromptTemplate] {
        preview.isFullBackup ? [] : (preview.fullConfiguration?.ai.templates ?? [])
    }

    // MARK: Internals

    private static func previewProfiles(_ object: [String: Any], current: Configuration) throws -> ImportPreview {
        var filler = LenientFiller()
        var bundle = ImportBundle(
            profiles: try decodeList(object["profiles"], "profiles", &filler) { $0.profile($1) },
            workflows: try decodeList(object["workflows"], "workflows", &filler) { $0.workflow($1) },
            radialMenus: try decodeList(object["radialMenus"], "radialMenus", &filler) { $0.radialMenu($1) },
            templates: try decodeList(object["aiTemplates"], "aiTemplates", &filler) { $0.promptTemplate($1) })
        guard !bundle.profiles.isEmpty else { throw ConfigurationError.invalid("The file contains no profiles.") }

        var warnings = filler.notes
        bundle.regenerateIdentifiers(reusing: bundle.templatesMatching(current.ai.templates))
        warnings += bundle.resolveNameCollisions(with: current)
        warnings += bundle.clearConflictingHotKeys(with: current)

        // Validate the import in the context it will live in, reporting only what it adds.
        let baseline = Set(ConfigurationValidator.issues(in: current))
        var combined = current
        combined.profiles += bundle.profiles
        combined.workflows += bundle.workflows
        combined.radialMenus += bundle.radialMenus
        combined.ai.templates += bundle.templates
        warnings += ConfigurationValidator.repair(&combined).filter { !baseline.contains($0) }
        bundle.profiles = Array(combined.profiles.suffix(bundle.profiles.count))
        bundle.workflows = Array(combined.workflows.suffix(bundle.workflows.count))
        bundle.radialMenus = Array(combined.radialMenus.suffix(bundle.radialMenus.count))
        bundle.templates = Array(combined.ai.templates.suffix(bundle.templates.count))

        let untrusted = bundle.scripts.filter { !ScriptTrust.isTrusted($0, in: current) }
        if !untrusted.isEmpty {
            warnings.append("\(untrusted.count) script action(s) in this file are not approved on this Mac. "
                            + "They will not run until you review and approve them.")
        }
        var carrier: Configuration?
        if !bundle.templates.isEmpty {
            var holder = Configuration()
            holder.ai.templates = bundle.templates
            carrier = holder
        }
        return ImportPreview(profiles: bundle.profiles, workflows: bundle.workflows, radialMenus: bundle.radialMenus,
                             untrustedScripts: untrusted, warnings: warnings, isFullBackup: false,
                             fullConfiguration: carrier)
    }

    private static func previewBackup(_ object: [String: Any], current: Configuration) throws -> ImportPreview {
        guard let payload = object["configuration"] as? [String: Any] else {
            throw ConfigurationError.invalid("The backup contains no configuration.")
        }
        var restored = try ConfigurationJSON.decodeConfiguration(from: payload)
        restored.approvedScriptHashes = []
        var warnings = ConfigurationValidator.repair(&restored)
        let untrusted = ScriptTrust.scripts(in: restored).filter { !ScriptTrust.isTrusted($0, in: current) }
        warnings.insert("Restoring this backup replaces all current profiles, workflows, menus and settings.", at: 0)
        if !untrusted.isEmpty {
            warnings.append("\(untrusted.count) script action(s) in this backup are not approved on this Mac. "
                            + "They will not run until you review and approve them.")
        }
        return ImportPreview(profiles: restored.profiles, workflows: restored.workflows, radialMenus: restored.radialMenus,
                             untrustedScripts: untrusted, warnings: warnings, isFullBackup: true,
                             fullConfiguration: restored)
    }

    private static func decodeList<T: Decodable>(_ value: Any?, _ key: String, _ filler: inout LenientFiller,
                                                 _ fill: (inout LenientFiller, [String: Any]) -> [String: Any]?) throws -> [T] {
        guard let value, !(value is NSNull) else { return [] }
        guard value is [Any] else { throw ConfigurationError.invalid("“\(key)” must be a list.") }
        guard let filled = filler.elements(value, fill) else { return [] }
        return try ConfigurationJSON.decode([T].self, from: filled)
    }

    private static func timestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct ProfilesEnvelope: Encodable {
    var format: String
    var version: Int
    var app: String
    var exportedAt: String?
    var profiles: [Profile]
    var workflows: [Workflow]
    var radialMenus: [RadialMenu]
    var aiTemplates: [PromptTemplate]
}

private struct BackupEnvelope: Encodable {
    var format: String
    var version: Int
    var app: String
    var exportedAt: String?
    var configuration: Configuration
}
