import SwiftUI
import MFCore
import MFEngine

enum AITemplateRunStatus: Equatable {
    case idle
    case running
    case succeeded(String)
    case failed(String)
}

/// Create, edit, delete and run prompt templates.
@MainActor
struct AITemplatesCard: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?
    @State private var pendingDeleteID: UUID?

    private var templates: [PromptTemplate] { model.configuration.ai.templates }

    private var effectiveSelection: UUID? {
        if let id = selectedID, templates.contains(where: { $0.id == id }) { return id }
        return templates.first?.id
    }

    var body: some View {
        MFCard("Prompt Templates", systemImage: "text.badge.star") {
            HStack(alignment: .top, spacing: 16) {
                list
                    .frame(width: 220)
                Divider()
                editor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("Delete Template", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            if templates.isEmpty {
                Text("No templates yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(templates) { template in
                AITemplateRow(template: template, isSelected: template.id == effectiveSelection,
                              onSelect: { selectedID = template.id })
            }
            Divider()
            HStack(spacing: 6) {
                Button(action: { addTemplate() }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add template"))
                .help("Add a prompt template")
                Button(action: { if let id = effectiveSelection { duplicate(id) } }) {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(effectiveSelection == nil)
                .accessibilityLabel(Text("Duplicate template"))
                .help("Duplicate the selected template")
                Button(action: { pendingDeleteID = effectiveSelection }) {
                    Image(systemName: "trash")
                }
                .disabled(effectiveSelection == nil)
                .accessibilityLabel(Text("Delete template"))
                .help("Delete the selected template")
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let id = effectiveSelection {
            AITemplateEditor(templateID: id)
                .id(id)
        } else {
            Text("Add a template to describe what the AI should do with your text, for example “Summarize” or “Fix grammar”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addTemplate() {
        let name: String = AIText.uniqueName("New Prompt", existing: templates.map { $0.name })
        let template = PromptTemplate(name: name, systemPrompt: "", userPrompt: "{{input}}", input: .selectedText)
        model.update { configuration in
            configuration.ai.templates.append(template)
        }
        selectedID = template.id
    }

    private func duplicate(_ id: UUID) {
        guard let original = templates.first(where: { $0.id == id }) else { return }
        let name: String = AIText.uniqueName(original.name + " Copy", existing: templates.map { $0.name })
        let copy = PromptTemplate(id: UUID(), name: name, systemPrompt: original.systemPrompt,
                                  userPrompt: original.userPrompt, input: original.input)
        model.update { configuration in
            configuration.ai.templates.append(copy)
        }
        selectedID = copy.id
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingDeleteID != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteID = nil }
            }
        )
    }

    private var deleteTitle: String {
        guard let id = pendingDeleteID, let template = templates.first(where: { $0.id == id }) else { return "Delete template?" }
        return "Delete “\(template.name)”?"
    }

    private var deleteMessage: String {
        guard let id = pendingDeleteID else { return "" }
        let uses: Int = ActionUsage.locations(of: .ai(templateID: id), in: model.configuration).count
        if uses == 0 { return "This cannot be undone." }
        return "It is used in \(uses) place\(uses == 1 ? "" : "s"), which will stop working. This cannot be undone."
    }

    private func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        model.update { configuration in
            configuration.ai.templates.removeAll(where: { $0.id == id })
        }
    }
}

@MainActor
struct AITemplateRow: View {
    let template: PromptTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: { onSelect() }) {
            HStack(spacing: 8) {
                Image(systemName: template.input == .clipboard ? "doc.on.clipboard" : "text.cursor")
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(template.name.isEmpty ? "Untitled" : template.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Fields of one template plus "Run Template Now".
@MainActor
struct AITemplateEditor: View {
    let templateID: UUID
    @Environment(AppModel.self) private var model
    @State private var runStatus: AITemplateRunStatus = .idle

    private func binding<Value>(_ keyPath: WritableKeyPath<PromptTemplate, Value>, fallback: Value) -> Binding<Value> {
        let id: UUID = templateID
        return Binding<Value>(
            get: { model.configuration.ai.templates.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                model.update { configuration in
                    guard let index = configuration.ai.templates.firstIndex(where: { $0.id == id }) else { return }
                    configuration.ai.templates[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var userPrompt: String {
        model.configuration.ai.templates.first(where: { $0.id == templateID })?.userPrompt ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: binding(\.name, fallback: ""), prompt: Text("Template name"))
                .textFieldStyle(.roundedBorder)
            Picker("Text to use", selection: binding(\.input, fallback: AIInputSource.selectedText)) {
                ForEach(AIInputSource.allCases, id: \.self) { source in
                    Text(AIText.inputSourceTitle(source)).tag(source)
                }
            }
            .pickerStyle(.segmented)
            promptField(title: "System prompt (optional)", text: binding(\.systemPrompt, fallback: ""), height: 60)
            promptField(title: "User prompt", text: binding(\.userPrompt, fallback: ""), height: 90)
            if userPrompt.contains("{{input}}") {
                Text("{{input}} is replaced with the selected text or clipboard when the template runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This prompt does not contain {{input}}, so your selected text or clipboard will not be included.")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            runRow
        }
    }

    private func promptField(title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: height, maxHeight: height * 2.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel(Text(title))
        }
    }

    private var runRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: { run() }) {
                    Label("Run Template Now", systemImage: "play.fill")
                }
                .disabled(runStatus == .running)
                if runStatus == .running {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            Text("Runs for real against the service. “Selected text” is read from the frontmost app, which is MagicForge while you click this button, so use “Clipboard” to test from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            runResult
        }
    }

    @ViewBuilder
    private var runResult: some View {
        switch runStatus {
        case .idle, .running:
            EmptyView()
        case .succeeded(let text):
            ScrollView(.vertical) {
                Text(text.isEmpty ? "(empty reply)" : text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func run() {
        let id: UUID = templateID
        runStatus = .running
        Task {
            let result: Result<String, AIError> = await model.runAITemplate(id)
            switch result {
            case .success(let text): runStatus = .succeeded(text)
            case .failure(let error): runStatus = .failed(AIText.describe(error))
            }
        }
    }
}
