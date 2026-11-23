import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MFCore
import MFEngine

// Internal helpers shared by the shell-owned screens (Dashboard, Profiles, Devices,
// Permissions, Settings). Everything is prefixed "Shell" to stay clear of the other UI agents.

enum ShellFormat {
    static let placeholder: String = "—"

    /// Measured duration in milliseconds, or "—" when nothing has been measured yet.
    static func milliseconds(_ seconds: TimeInterval, hasData: Bool) -> String {
        guard hasData, seconds > 0 else { return placeholder }
        return String(format: "%.2f ms", seconds * 1000)
    }

    static func count(_ value: Int) -> String { String(value) }

    static func battery(_ percent: Int?) -> String {
        guard let percent else { return "Not reported" }
        return "\(percent)%"
    }

    static func batterySymbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.0" }
        if percent >= 88 { return "battery.100" }
        if percent >= 63 { return "battery.75" }
        if percent >= 38 { return "battery.50" }
        if percent >= 13 { return "battery.25" }
        return "battery.0"
    }

    static func hexID(_ value: Int) -> String { String(format: "0x%04X", value) }

    static func surface(_ surface: SurfaceGeometry) -> String {
        String(format: "%.0f × %.0f mm", surface.widthMM, surface.heightMM)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", max(0, min(1, fraction)) * 100)
    }

    static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
}

extension PermissionStatus {
    var shellLabel: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .notDetermined: return "Not requested yet"
        case .notRequired: return "Not required"
        }
    }

    var shellStyle: MFStatusStyle {
        switch self {
        case .granted: return .good
        case .denied: return .bad
        case .notDetermined: return .warning
        case .notRequired: return .neutral
        }
    }
}

extension AdapterStatus.State {
    var shellLabel: String {
        switch self {
        case .stopped: return "Stopped"
        case .running: return "Running"
        case .unavailable: return "Unavailable"
        }
    }

    var shellStyle: MFStatusStyle {
        switch self {
        case .stopped: return .neutral
        case .running: return .good
        case .unavailable: return .bad
        }
    }

    var shellUnavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

enum ShellErrorText {
    static func describe(_ error: Error) -> String {
        if let configurationError = error as? ConfigurationError {
            switch configurationError {
            case .unreadable(let detail):
                return "The file could not be read. \(detail)"
            case .unsupportedSchema(let version):
                return "This file uses configuration format \(version), which this version of MagicForge cannot open."
            case .invalid(let detail):
                return "The file is not a valid MagicForge configuration. \(detail)"
            }
        }
        return error.localizedDescription
    }
}

/// Open / save panels. All calls are modal and must happen on the main actor.
@MainActor
enum ShellFilePanels {
    static func openFile(title: String, types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Returns the destination, or nil when the user cancelled.
    static func saveJSON(_ data: Data, suggestedName: String, title: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Lets the user pick an application bundle and reads its bundle identifier.
    static func chooseApplication() -> RunningApp? {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        return RunningApp(bundleID: bundleID, name: ShellAppLookup.displayName(at: url))
    }
}

@MainActor
enum ShellAppLookup {
    static func displayName(at url: URL) -> String {
        let name: String = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { return String(name.dropLast(4)) }
        return name
    }

    static func applicationURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = applicationURL(forBundleID: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func name(forBundleID bundleID: String) -> String? {
        guard let url = applicationURL(forBundleID: bundleID) else { return nil }
        return displayName(at: url)
    }

    /// Regular (Dock) apps that are running right now, sorted by name.
    static func runningApps() -> [RunningApp] {
        var seen = Set<String>()
        var result: [RunningApp] = []
        for application in NSWorkspace.shared.runningApplications {
            guard application.activationPolicy == .regular, let bundleID = application.bundleIdentifier else { continue }
            guard !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(RunningApp(bundleID: bundleID, name: application.localizedName ?? bundleID))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Application icon for a bundle identifier, or a generic symbol when it cannot be resolved.
@MainActor
struct ShellAppIcon: View {
    let bundleID: String
    var size: CGFloat = 18

    var body: some View {
        if let image = ShellAppLookup.icon(forBundleID: bundleID) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// Text field that edits a local draft and commits on Return or when focus leaves, so the
/// model is not mutated on every keystroke.
@MainActor
struct ShellCommitTextField: View {
    let title: String
    let value: String
    let onCommit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .focused($isFocused)
            .onSubmit { commit() }
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                draft = newValue
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        let trimmed: String = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = value
            return
        }
        guard trimmed != value else { return }
        onCommit(trimmed)
    }
}

/// 0…1 slider that commits when the drag ends (or immediately for keyboard changes).
@MainActor
struct ShellCommitSlider: View {
    let value: Double
    let accessibilityLabel: String
    let onCommit: (Double) -> Void

    @State private var draft: Double = 0.5
    @State private var isEditing: Bool = false

    var body: some View {
        Slider(value: $draft, in: 0...1, onEditingChanged: { editing in
            isEditing = editing
            if !editing { commit() }
        })
        .accessibilityLabel(accessibilityLabel)
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isEditing { draft = newValue }
        }
        .onChange(of: draft) { _, _ in
            if !isEditing { commit() }
        }
    }

    private func commit() {
        guard abs(draft - value) > 0.0005 else { return }
        onCommit(draft)
    }
}

/// The global pause switch ("Gestures enabled").
@MainActor
struct ShellPauseToggle: View {
    @Environment(AppModel.self) private var model
    var title: String = "Gestures enabled"

    var body: some View {
        Toggle(title, isOn: Binding<Bool>(
            get: { !model.isPaused },
            set: { enabled in model.setPaused(!enabled) }
        ))
        .toggleStyle(.switch)
        .help("Pause or resume all gesture actions")
    }
}

extension View {
    /// Presents `message` in an alert while it is non-nil.
    func shellErrorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding<Bool>(
                get: { message.wrappedValue != nil },
                set: { presented in
                    if !presented { message.wrappedValue = nil }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(message.wrappedValue ?? "")
            }
        )
    }
}
