import Foundation
import MFCore

/// The sample profile files shipped in `Resources/SampleProfiles`, produced by the real exporter
/// so they always match the current format.
public enum SampleProfiles {
    public struct Sample: Sendable, Equatable {
        public let fileName: String
        public let title: String
        public let data: Data
    }

    /// Deterministic: the same bytes on every call.
    public static func all() throws -> [Sample] {
        var configuration = DefaultConfiguration.make()
        let windows = DefaultProfiles.windowManagement()
        configuration.profiles.append(windows)
        func ids(_ bundleIDs: [String]) -> [UUID] {
            configuration.profiles.filter { !Set($0.bundleIdentifiers).isDisjoint(with: bundleIDs) }.map(\.id)
        }
        let groups: [(String, String, [UUID])] = [
            ("Browser.json", "Browser (Safari and Chrome)",
             ids([DefaultConfiguration.safariBundleID, DefaultConfiguration.chromeBundleID])),
            ("Finder.json", "Finder", ids([DefaultConfiguration.finderBundleID])),
            ("VSCode.json", "Visual Studio Code", ids([DefaultConfiguration.vsCodeBundleID])),
            ("Photos.json", "Photos", ids([DefaultConfiguration.photosBundleID])),
            ("WindowManagement.json", "Window Management", [windows.id]),
        ]
        return try groups.map { fileName, title, profileIDs in
            Sample(fileName: fileName, title: title,
                   data: try ProfileTransfer.exportProfiles(profileIDs, from: configuration, exportedAt: nil))
        }
    }
}
