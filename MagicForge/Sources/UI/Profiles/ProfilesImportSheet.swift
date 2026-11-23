import SwiftUI
import AppKit
import MFCore

/// Shows exactly what an import file contains before anything is applied. Scripts are never
/// approved unless the user turns the (default off) approval switch on.
@MainActor
struct ProfilesImportSheet: View {
    let preview: ImportPreview
    let onApply: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var approveScripts: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preview.isFullBackup ? "Restore from Backup" : "Import Profiles")
                .font(.headline)
            if preview.isFullBackup {
                Label("This file is a full backup. Restoring it replaces your current profiles, workflows, radial menus and settings.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ProfilesImportContents(preview: preview)
                    ProfilesImportWarnings(warnings: preview.warnings)
                    ProfilesImportScripts(scripts: preview.untrustedScripts)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 6)
            }
            .frame(minHeight: 220, maxHeight: 380)
            if !preview.untrustedScripts.isEmpty {
                Toggle(isOn: $approveScripts) {
                    Text("Approve these \(preview.untrustedScripts.count) scripts to run on this Mac")
                }
                Text("Leave this off to import them untrusted: they will not run until you review and approve each one in Actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(preview.isFullBackup ? "Restore" : "Import") {
                    onApply(approveScripts && !preview.untrustedScripts.isEmpty)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private var isEmpty: Bool {
        !preview.isFullBackup && preview.profiles.isEmpty && preview.workflows.isEmpty && preview.radialMenus.isEmpty
    }
}

@MainActor
struct ProfilesImportContents: View {
    let preview: ImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            group(title: "Profiles (\(preview.profiles.count))", systemImage: "square.stack.3d.up",
                  lines: preview.profiles.map { profileLine($0) })
            group(title: "Workflows (\(preview.workflows.count))", systemImage: "arrow.triangle.branch",
                  lines: preview.workflows.map { "\($0.name) — \($0.steps.count) steps" })
            group(title: "Radial menus (\(preview.radialMenus.count))", systemImage: "circle.grid.cross",
                  lines: preview.radialMenus.map { "\($0.name) — \($0.items.count) items" })
        }
    }

    private func profileLine(_ profile: Profile) -> String {
        let apps: String = profile.bundleIdentifiers.isEmpty ? "no apps" : profile.bundleIdentifiers.joined(separator: ", ")
        return "\(profile.name) — \(profile.bindings.count) bindings, \(apps)"
    }

    private func group(title: String, systemImage: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.medium)
            if lines.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

@MainActor
struct ProfilesImportWarnings: View {
    let warnings: [String]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Warnings (\(warnings.count))", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ForEach(Array(warnings.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Lists the complete text of every script in the import that is not yet approved on this Mac.
@MainActor
struct ProfilesImportScripts: View {
    let scripts: [ScriptAction]

    var body: some View {
        if !scripts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scripts that are not approved on this Mac (\(scripts.count))", systemImage: "terminal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Scripts run with your user account's privileges. Read each one completely before approving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(scripts.enumerated()), id: \.offset) { item in
                    scriptBlock(item.element)
                }
            }
        }
    }

    private func scriptBlock(_ script: ScriptAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kindLabel(script))
                .font(.caption)
                .fontWeight(.semibold)
            Text(fullText(script))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }

    private func kindLabel(_ script: ScriptAction) -> String {
        switch script {
        case .appleScript: return "AppleScript"
        case .shell: return "Shell command"
        case .shortcut: return "Shortcut (runs the Shortcut with this name)"
        }
    }

    private func fullText(_ script: ScriptAction) -> String {
        switch script {
        case .appleScript(let source): return source
        case .shell(let command): return command
        case .shortcut(let name): return name
        }
    }
}
