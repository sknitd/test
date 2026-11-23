import SwiftUI
import MFCore
import MFEngine

/// Editor for AppleScript / shell / Shortcut actions including the trust panel.
@MainActor
struct ActionScriptEditor: View {
    @Binding var action: Action

    private var current: ScriptAction {
        if case .script(let value) = action { return value }
        return ScriptAction.shortcut(name: "")
    }

    private var choice: Binding<ScriptActionChoice> {
        Binding<ScriptActionChoice>(
            get: { ScriptActionChoice(current) },
            set: { newValue in
                if newValue != ScriptActionChoice(current) {
                    // The text is kept, but it is a different script now and needs its own approval.
                    action = .script(newValue.action(body: ScriptActionChoice.body(of: current)))
                }
            }
        )
    }

    private var bodyText: Binding<String> {
        Binding<String>(
            get: { ScriptActionChoice.body(of: current) },
            set: { newValue in action = .script(ScriptActionChoice(current).action(body: newValue)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: choice) {
                ForEach(ScriptActionChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text("Script kind"))
            editorField
            ActionScriptTrustPanel(script: current)
        }
    }

    @ViewBuilder
    private var editorField: some View {
        switch ScriptActionChoice(current) {
        case .shortcut:
            TextField("Shortcut name", text: bodyText, prompt: Text("Name exactly as shown in the Shortcuts app"))
                .textFieldStyle(.roundedBorder)
        case .appleScript:
            codeEditor(caption: "AppleScript source. Controlling other apps asks for Automation permission the first time.")
        case .shell:
            codeEditor(caption: "Runs with /bin/zsh as your user. There is no sandbox: only approve commands you understand.")
        }
    }

    private func codeEditor(caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: bodyText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel(Text("Script source"))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shows whether a script is approved on this Mac and lets the user approve or revoke it.
/// Approval is keyed by a hash of the script text, so any edit makes it untrusted again.
@MainActor
struct ActionScriptTrustPanel: View {
    let script: ScriptAction
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool {
        ScriptActionChoice.body(of: script).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let trusted: Bool = model.isTrusted(script)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(trusted ? Color.green : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(trusted ? "Approved on this Mac" : "Not approved — it will not run")
                    .font(.callout.weight(.medium))
                Text("Approval covers exactly this text. Any edit, even one character, requires approving again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if trusted {
                Button("Revoke") { model.revokeApproval(script) }
            } else {
                Button("Approve This Script") { model.approve(script) }
                    .disabled(isEmpty)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
