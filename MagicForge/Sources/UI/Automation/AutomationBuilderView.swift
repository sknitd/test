import SwiftUI
import MFCore
import MFEngine

/// Visual workflow builder: a list of workflows and an editor for the selected one.
@MainActor
public struct AutomationBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation
    @State private var selectedWorkflowID: UUID?
    @State private var selectedStep: WorkflowStepPath?
    @State private var outcomes: [UUID: WorkflowRunOutcome] = [:]
    @State private var pendingDeleteID: UUID?

    public init() {}

    /// The selected workflow, falling back to the first one when the selection no longer exists.
    private var effectiveSelection: UUID? {
        let workflows: [Workflow] = model.configuration.workflows
        if let id = selectedWorkflowID, workflows.contains(where: { $0.id == id }) { return id }
        return workflows.first?.id
    }

    public var body: some View {
        MFPage("Automation Builder", subtitle: "Chain actions, waits and conditions into workflows that a gesture or radial menu can run.") {
            HStack(alignment: .top, spacing: 16) {
                WorkflowListPane(selectedID: effectiveSelection,
                                 onSelect: { id in select(id) },
                                 onAdd: { select(WorkflowEditing.addEmpty(to: model)) },
                                 onAddExample: { select(WorkflowEditing.addExample(to: model)) },
                                 onDuplicate: { id in select(WorkflowEditing.duplicate(id, in: model)) },
                                 onDelete: { id in pendingDeleteID = id })
                    .frame(width: 250)
                detail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("Delete Workflow", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = effectiveSelection {
            WorkflowDetailView(workflowID: id, selectedStep: $selectedStep, outcomes: $outcomes)
                .id(id)
        } else {
            MFEmptyState(systemImage: "arrow.triangle.branch", title: "No Workflows Yet",
                         message: "Create a workflow with the + button, or start from the example to see how steps fit together.")
        }
    }

    private func select(_ id: UUID?) {
        selectedStep = nil
        selectedWorkflowID = id
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
        guard let id = pendingDeleteID, let workflow = WorkflowEditing.workflow(id, in: model) else { return "Delete workflow?" }
        return "Delete “\(workflow.name)”?"
    }

    private var deleteMessage: String {
        guard let id = pendingDeleteID else { return "" }
        let uses: Int = ActionUsage.locations(of: .workflow(id: id), in: model.configuration).count
        if uses == 0 { return "This cannot be undone." }
        return "It is used in \(uses) place\(uses == 1 ? "" : "s"). Those gestures or menu items will stop working. This cannot be undone."
    }

    private func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        selectedStep = nil
        outcomes[id] = nil
        WorkflowEditing.delete(id, in: model)
    }
}

/// Master list of workflows with add / duplicate / delete controls.
@MainActor
struct WorkflowListPane: View {
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let onAddExample: () -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Workflows", systemImage: "list.bullet") {
            VStack(alignment: .leading, spacing: 8) {
                rows
                Divider()
                controls
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let workflows: [Workflow] = model.configuration.workflows
        if workflows.isEmpty {
            Text("None yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(workflows) { workflow in
                    WorkflowListRow(workflow: workflow, isSelected: workflow.id == selectedID,
                                    isRunning: model.runningWorkflows.contains(where: { $0.workflowID == workflow.id }),
                                    onSelect: { onSelect(workflow.id) })
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Menu {
                Button("New Empty Workflow") { onAdd() }
                Button("New from Example") { onAddExample() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text("Add workflow"))
            .help("Add a workflow")
            Button(action: { if let id = selectedID { onDuplicate(id) } }) {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .disabled(selectedID == nil)
            .accessibilityLabel(Text("Duplicate workflow"))
            .help("Duplicate the selected workflow")
            Button(action: { if let id = selectedID { onDelete(id) } }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(selectedID == nil)
            .accessibilityLabel(Text("Delete workflow"))
            .help("Delete the selected workflow")
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct WorkflowListRow: View {
    let workflow: Workflow
    let isSelected: Bool
    let isRunning: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: { onSelect() }) {
            HStack(spacing: 8) {
                Image(systemName: workflow.symbolName)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.name.isEmpty ? "Untitled" : workflow.name)
                        .lineLimit(1)
                    Text(stepCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Running"))
                }
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

    private var stepCountText: String {
        let count: Int = WorkflowStepTree.count(workflow.steps)
        return count == 1 ? "1 step" : "\(count) steps"
    }
}
