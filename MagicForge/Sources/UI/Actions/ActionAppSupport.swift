import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MFCore

/// App lookups for pickers and summaries, straight from AppKit (MFUI does not link MFActions).
@MainActor
enum ActionAppNames {
    private static var cache: [String: String] = [:]

    /// Localized app name for a bundle identifier, or the identifier itself when the app is not installed.
    static func displayName(for bundleID: String) -> String {
        if bundleID.isEmpty { return "" }
        if let cached = cache[bundleID] { return cached }
        var name: String = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let displayName: String = FileManager.default.displayName(atPath: url.path)
            name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        }
        cache[bundleID] = name
        return name
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        if bundleID.isEmpty { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Regular (Dock-visible) running apps, de-duplicated and sorted by name.
    static func runningApps() -> [RunningApp] {
        var seen: Set<String> = []
        var result: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(RunningApp(bundleID: bundleID, name: app.localizedName ?? bundleID))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick an application bundle. Returns nil when the panel was cancelled.
    static func chooseApplicationURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Choose"
        panel.message = "Choose an application"
        guard panel.runModal() == NSApplication.ModalResponse.OK else { return nil }
        return panel.url
    }

    /// Lets the user pick a file or folder. Returns its path with the home folder abbreviated to `~`.
    static func choosePath() -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        guard panel.runModal() == NSApplication.ModalResponse.OK, let url = panel.url else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// Bundle identifier field with a menu of running apps and a "Choose App…" panel.
@MainActor
struct ActionAppPicker: View {
    let title: String
    @Binding var bundleID: String
    @State private var chooseFailed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(title, text: $bundleID, prompt: Text("com.example.app"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(Text("\(title) bundle identifier"))
                appMenu
            }
            statusLine
        }
    }

    private var appMenu: some View {
        Menu {
            ForEach(ActionAppNames.runningApps()) { app in
                Button(app.name) {
                    chooseFailed = false
                    bundleID = app.bundleID
                }
            }
            Divider()
            Button("Choose App…") { chooseApp() }
        } label: {
            Label("Choose", systemImage: "app.dashed")
        }
        .fixedSize()
        .help("Pick a running app or choose one from disk")
    }

    @ViewBuilder
    private var statusLine: some View {
        if chooseFailed {
            Text("That item has no bundle identifier, so it cannot be used.")
                .font(.caption)
                .foregroundStyle(Color.red)
        } else if bundleID.isEmpty {
            Text("No app chosen yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if ActionAppNames.isInstalled(bundleID) {
            Text(ActionAppNames.displayName(for: bundleID))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No installed app has this identifier.")
                .font(.caption)
                .foregroundStyle(Color.orange)
        }
    }

    private func chooseApp() {
        guard let url = ActionAppNames.chooseApplicationURL() else { return }
        if let chosen = Bundle(url: url)?.bundleIdentifier, !chosen.isEmpty {
            chooseFailed = false
            bundleID = chosen
        } else {
            chooseFailed = true
        }
    }
}
