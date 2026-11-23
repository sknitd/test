import SwiftUI
import MFCore
import MFEngine

/// Lists every script referenced by the configuration with its trust status.
@MainActor
struct ActionScriptsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let references: [ActionScriptReference] = ActionUsage.scripts(in: model.configuration)
        let untrustedCount: Int = model.untrustedScripts().count
        MFCard("Scripts in Your Configuration", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 10) {
                header(total: references.count, untrusted: untrustedCount)
                if !references.isEmpty {
                    Divider()
                    ForEach(references) { reference in
                        ActionScriptRow(reference: reference)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func header(total: Int, untrusted: Int) -> some View {
        if total == 0 {
            Text("No AppleScript, shell or Shortcut actions are configured. Scripts only ever run after you approve their exact text on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                if untrusted == 0 {
                    MFStatusBadge("All approved", style: .good)
                } else {
                    MFStatusBadge("\(untrusted) not approved", style: .warning)
                }
                Text("Unapproved scripts never run. Imported profiles always arrive unapproved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct ActionScriptRow: View {
    let reference: ActionScriptReference
    @Environment(AppModel.self) private var model
    @State private var isExpanded: Bool = false

    private var kind: ScriptActionChoice { ScriptActionChoice(reference.script) }
    private var text: String { ScriptActionChoice.body(of: reference.script) }

    var body: some View {
        let trusted: Bool = model.isTrusted(reference.script)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: kind.symbolName)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryLine)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                    Text(usageLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                MFStatusBadge(trusted ? "Approved" : "Not approved", style: trusted ? .good : .warning)
                Button(isExpanded ? "Hide" : "Show") { isExpanded.toggle() }
                    .controlSize(.small)
                if trusted {
                    Button("Revoke") { model.revokeApproval(reference.script) }
                        .controlSize(.small)
                } else {
                    Button("Approve") { model.approve(reference.script) }
                        .controlSize(.small)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if isExpanded {
                ScrollView {
                    Text(text.isEmpty ? "(empty)" : text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
    }

    private var summaryLine: String {
        let line: String = ActionText.firstLine(text, limit: 60)
        return "\(kind.title): \(line.isEmpty ? "(empty)" : line)"
    }

    private var usageLine: String {
        let places: [String] = reference.locations.map { location in "\(location.container) · \(location.detail)" }
        return "Used by " + places.joined(separator: ", ")
    }
}
