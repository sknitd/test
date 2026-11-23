import Foundation
import MFCore
import MFUtilities

/// File-based configuration store.
///
/// Layout inside `directory`:
/// - `configuration.json` — pretty-printed, key-sorted JSON of `Configuration`.
/// - `configuration.backup.json` — the previous readable `configuration.json` (one rolling copy).
/// - `configuration.corrupt-<UTC timestamp>.json` — an unreadable file set aside by `load()`.
///
/// Writes are atomic (temporary file in the same directory, then rename), so a crash never
/// leaves a half-written configuration. All methods may be called from any thread.
public final class JSONConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    public static let fileName = "configuration.json"
    public static let backupFileName = "configuration.backup.json"

    public let directory: URL
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let log = Log("store")

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/MagicForge` on macOS; `$XDG_CONFIG_HOME/MagicForge`
    /// (default `~/.config/MagicForge`) elsewhere.
    public static var defaultDirectory: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MagicForge", isDirectory: true)
        #else
        if let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], configHome.hasPrefix("/") {
            return URL(fileURLWithPath: configHome, isDirectory: true).appendingPathComponent("MagicForge", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("MagicForge", isDirectory: true)
        #endif
    }

    public var location: URL? { fileURL }
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    public var backupURL: URL { directory.appendingPathComponent(Self.backupFileName) }

    // MARK: ConfigurationStoring

    /// Returns nil when nothing has been saved yet. The result has passed
    /// `ConfigurationValidator.repair`, so its invariants hold even for partial or hand-edited files.
    ///
    /// - Throws: `ConfigurationError.unsupportedSchema` for a file written by a newer version (the
    ///   file is left untouched), or `ConfigurationError.unreadable` for corrupt content (the file
    ///   is moved aside as `configuration.corrupt-<timestamp>.json`; see `loadBackup()`).
    public func load() throws -> Configuration? {
        lock.lock(); defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigurationError.unreadable("The configuration file could not be read: \(error.localizedDescription)")
        }
        do {
            return try Self.decode(data)
        } catch ConfigurationError.unsupportedSchema(let version) {
            throw ConfigurationError.unsupportedSchema(version)
        } catch {
            let reason = Self.reason(for: error)
            let preserved = preserveCorruptFile()
            log.error("Configuration unreadable (\(reason)); preserved as \(preserved?.lastPathComponent ?? "nothing")")
            var message = "The configuration file is damaged. \(reason)"
            if let preserved { message += " It was kept as \(preserved.lastPathComponent)." }
            if fileManager.fileExists(atPath: backupURL.path) { message += " A backup of the previous version is available." }
            throw ConfigurationError.unreadable(message)
        }
    }

    public func save(_ configuration: Configuration) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try ConfigurationJSON.encode(configuration)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ConfigurationError.unreadable("The configuration folder could not be created: \(error.localizedDescription)")
        }
        rollBackup()
        do {
            try writeAtomically(data, to: fileURL)
        } catch {
            throw ConfigurationError.unreadable("The configuration could not be saved: \(error.localizedDescription)")
        }
    }

    // MARK: Backup

    /// The rolling backup, or nil when there is none. Throws like `load()` but never moves files.
    public func loadBackup() throws -> Configuration? {
        lock.lock(); defer { lock.unlock() }
        guard fileManager.fileExists(atPath: backupURL.path) else { return nil }
        guard let data = try? Data(contentsOf: backupURL) else {
            throw ConfigurationError.unreadable("The backup file could not be read.")
        }
        do {
            return try Self.decode(data)
        } catch ConfigurationError.unsupportedSchema(let version) {
            throw ConfigurationError.unsupportedSchema(version)
        } catch {
            throw ConfigurationError.unreadable("The backup file is damaged. \(Self.reason(for: error))")
        }
    }

    /// Files set aside by `load()` because they could not be read, oldest first.
    public func corruptFiles() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("configuration.corrupt-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Internals

    private static func decode(_ data: Data) throws -> Configuration {
        var configuration = try ConfigurationJSON.decodeConfiguration(from: ConfigurationJSON.parseObject(data))
        let repairs = ConfigurationValidator.repair(&configuration)
        if !repairs.isEmpty { Log("store").notice("Configuration loaded with \(repairs.count) repair(s) or warning(s)") }
        return configuration
    }

    private static func reason(for error: Error) -> String {
        switch error {
        case ConfigurationError.unreadable(let text), ConfigurationError.invalid(let text): return text
        default: return "It could not be decoded."
        }
    }

    /// Copies the current file to the backup slot, but only when it is still readable, so the
    /// backup always holds the last good version.
    private func rollBackup() {
        guard let existing = try? Data(contentsOf: fileURL), !existing.isEmpty else { return }
        guard let object = try? ConfigurationJSON.parseObject(existing),
              (try? ConfigurationJSON.decodeConfiguration(from: object)) != nil else {
            log.notice("Existing configuration is unreadable; keeping the older backup")
            return
        }
        do {
            try writeAtomically(existing, to: backupURL)
        } catch {
            log.error("Could not update the configuration backup: \(error.localizedDescription)")
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        // `.atomic` writes a temporary file next to the destination and renames it into place.
        try data.write(to: url, options: .atomic)
        // The configuration can contain script sources and prompt templates: owner-only access.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func preserveCorruptFile() -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let target = directory.appendingPathComponent("configuration.corrupt-\(stamp)\(suffix).json")
            if fileManager.fileExists(atPath: target.path) { continue }
            do {
                try fileManager.moveItem(at: fileURL, to: target)
                return target
            } catch {
                log.error("Could not set the damaged configuration aside: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
}
