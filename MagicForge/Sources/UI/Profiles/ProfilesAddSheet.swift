import SwiftUI
import MFCore

/// Sheet for creating a profile: a name plus optional applications.
@MainActor
struct ProfilesAddSheet: View {
    let onCreate: (String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var apps: [RunningApp] = []
    @State private var runningApps: [RunningApp] = []
    @State private var noticeMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Profile")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Applications")
                .font(.subheadline)
                .fontWeight(.medium)
            appList
            HStack {
                Menu("Add Running App") {
                    ForEach(runningApps) { app in
                        Button(app.name) { add(app) }
                    }
                }
                .fixedSize()
                Button("Choose Application…") { chooseApplication() }
                Spacer()
            }
            if let noticeMessage {
                Text(noticeMessage)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
            Text("Leave the list empty for a manual profile that you switch to yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { runningApps = ShellAppLookup.runningApps() }
    }

    @ViewBuilder private var appList: some View {
        if apps.isEmpty {
            Text("No applications selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(apps) { app in
                    ProfilesBundleRow(bundleID: app.bundleID, onRemove: { remove(app) })
                }
            }
        }
    }

    /// Typed name, or the first application's name when the field is empty.
    private var resolvedName: String {
        let typed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return apps.first?.name ?? ""
    }

    private func add(_ app: RunningApp) {
        guard !apps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        apps.append(app)
        noticeMessage = nil
    }

    private func remove(_ app: RunningApp) {
        apps.removeAll { $0.bundleID == app.bundleID }
    }

    private func chooseApplication() {
        if let app = ShellFilePanels.chooseApplication() {
            add(app)
        } else {
            noticeMessage = "No application was added. Bundles without a bundle identifier cannot be used."
        }
    }

    private func create() {
        let finalName: String = resolvedName
        guard !finalName.isEmpty else { return }
        onCreate(finalName, apps.map(\.bundleID))
        dismiss()
    }
}
