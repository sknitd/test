import Foundation
import MFCore
import MFUtilities

/// Applications installed in the standard locations, for the UI's app picker.
public enum InstalledApps {
    private static let cache = Locked<[RunningApp]?>(nil)

    /// All installed apps with a bundle identifier, sorted by name. Scanned once, then cached.
    public static func all() -> [RunningApp] {
        if let cached = cache.current { return cached }
        let scanned = scan()
        cache.withLock { $0 = scanned }
        return scanned
    }

    /// Drops the cache and scans again (e.g. from a "Refresh" button).
    @discardableResult
    public static func refresh() -> [RunningApp] {
        let scanned = scan()
        cache.withLock { $0 = scanned }
        return scanned
    }

    private static func scan() -> [RunningApp] {
        let home = NSHomeDirectory()
        // One level of each folder, plus its "Utilities" subfolder.
        var folders: [String] = []
        for root in ["/Applications", "/System/Applications", home + "/Applications"] {
            folders.append(root)
            folders.append(root + "/Utilities")
        }

        var byBundleID: [String: RunningApp] = [:]
        let fileManager = FileManager.default
        for folder in folders {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                add(appAt: folder + "/" + name, to: &byBundleID)
            }
        }
        // Finder lives outside the application folders but is a common profile target.
        add(appAt: "/System/Library/CoreServices/Finder.app", to: &byBundleID)

        return byBundleID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func add(appAt path: String, to apps: inout [String: RunningApp]) {
        guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier, apps[bundleID] == nil else { return }
        apps[bundleID] = RunningApp(bundleID: bundleID, name: displayName(for: bundle, path: path))
    }

    private static func displayName(for bundle: Bundle, path: String) -> String {
        // Localized Finder name without the ".app" extension.
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        if !name.isEmpty { return name }
        if let fallback = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !fallback.isEmpty {
            return fallback
        }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
