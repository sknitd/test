import SwiftUI
import MFCore
import MFEngine

/// Editor for the bundle identifiers a profile activates for.
@MainActor
struct ProfilesAppsCard: View {
    let profile: Profile

    @Environment(AppModel.self) private var model
    @State private var manualBundleID: String = ""
    @State private var runningApps: [RunningApp] = []
    @State private var errorMessage: String?

    var body: some View {
        MFCard("Applications", systemImage: "app.badge") {
            if profile.bundleIdentifiers.isEmpty {
                Text("No applications. This is a manual profile: it is only used when you pick it with “Use This Profile Now” or from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(profile.bundleIdentifiers, id: \.self) { bundleID in
                    ProfilesBundleRow(bundleID: bundleID, onRemove: { remove(bundleID) })
                }
            }
            Divider()
            HStack {
                Menu("Add Running App") {
                    ForEach(runningApps) { app in
                        Button(app.name) { add(app.bundleID) }
                            .disabled(profile.bundleIdentifiers.contains(app.bundleID))
                    }
                }
                .fixedSize()
                Button("Choose Application…") { chooseApplication() }
            }
            HStack {
                TextField("Bundle identifier, e.g. com.apple.Safari", text: $manualBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addManual() }
                Button("Add") { addManual() }
                    .disabled(trimmedManualID.isEmpty)
            }
        }
        .onAppear { runningApps = ShellAppLookup.runningApps() }
        .shellErrorAlert("Applications", message: $errorMessage)
    }

    private var trimmedManualID: String {
        manualBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addManual() {
        let bundleID: String = trimmedManualID
        guard !bundleID.isEmpty else { return }
        add(bundleID)
        manualBundleID = ""
    }

    private func chooseApplication() {
        guard let app = ShellFilePanels.chooseApplication() else {
            return
        }
        add(app.bundleID)
    }

    private func add(_ bundleID: String) {
        guard !profile.bundleIdentifiers.contains(bundleID) else {
            errorMessage = "“\(bundleID)” is already in this profile."
            return
        }
        let id: UUID = profile.id
        model.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
            configuration.profiles[index].bundleIdentifiers.append(bundleID)
        }
    }

    private func remove(_ bundleID: String) {
        let id: UUID = profile.id
        model.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
            configuration.profiles[index].bundleIdentifiers.removeAll { $0 == bundleID }
        }
    }
}

@MainActor
struct ProfilesBundleRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ShellAppIcon(bundleID: bundleID, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(ShellAppLookup.name(forBundleID: bundleID) ?? "Not installed on this Mac")
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this application from the profile")
            .accessibilityLabel("Remove \(bundleID)")
        }
        .font(.callout)
    }
}
