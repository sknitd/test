import SwiftUI
import MFCore
import MFEngine

/// One list of steps (the top level, or one branch of a condition) drawn as connected cards.
/// Recursion goes through nominal view types: list → card → (branch) list.
@MainActor
struct WorkflowStepListView: View {
    let workflowID: UUID
    let listPath: WorkflowStepListPath
    @Binding var selection: WorkflowStepPath?
    @Environment(AppModel.self) private var model

    private var steps: [WorkflowStep] {
        guard let workflow = WorkflowEditing.workflow(workflowID, in: model) else { return [] }
        return WorkflowStepTree.steps(at: listPath, in: workflow.steps) ?? []
    }

    var body: some View {
        let current: [WorkflowStep] = steps
        VStack(alignment: .leading, spacing: 0) {
            if current.isEmpty {
                Text(listPath.depth == 0 ? "No steps yet. Add the first one below." : "No steps in this branch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            ForEach(current.indices, id: \.self) { index in
                WorkflowStepCard(workflowID: workflowID, path: listPath.step(index), step: current[index],
                                 selection: $selection)
                WorkflowStepConnector()
            }
            WorkflowAddStepMenu(allowsCondition: listPath.depth < WorkflowStepTree.maximumConditionalDepth,
                                onAdd: { kind in add(kind) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add(_ kind: WorkflowStepKind) {
        var inserted: WorkflowStepPath?
        let target: WorkflowStepListPath = listPath
        WorkflowEditing.update(workflowID, in: model) { workflow in
            inserted = WorkflowStepTree.insertStep(kind.newStep, in: target, root: &workflow.steps)
        }
        if let path = inserted { selection = path }
    }
}

/// The short vertical line that links two step cards.
@MainActor
struct WorkflowStepConnector: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 2, height: 12)
            .padding(.leading, 21)
            .accessibilityHidden(true)
    }
}

@MainActor
struct WorkflowAddStepMenu: View {
    let allowsCondition: Bool
    let onAdd: (WorkflowStepKind) -> Void

    var body: some View {
        Menu {
            ForEach(WorkflowStepKind.allCases) { kind in
                Button(action: { onAdd(kind) }) {
                    Label(kind.title, systemImage: kind.symbolName)
                }
                .disabled(kind == .conditional && !allowsCondition)
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .fixedSize()
        .help("Add a step at the end of this list")
    }
}

/// One step: summary row with reorder / delete controls, the inline editor when selected and,
/// for conditions, the two nested branch lists.
@MainActor
struct WorkflowStepCard: View {
    let workflowID: UUID
    let path: WorkflowStepPath
    let step: WorkflowStep
    @Binding var selection: WorkflowStepPath?
    @Environment(AppModel.self) private var model

    private var isSelected: Bool { selection == path }

    private var rootSteps: [WorkflowStep] {
        WorkflowEditing.workflow(workflowID, in: model)?.steps ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isSelected {
                Divider()
                WorkflowStepEditor(step: WorkflowEditing.stepBinding(workflowID: workflowID, path: path,
                                                                     fallback: step, model: model))
            }
            if case .conditional = step {
                WorkflowBranchesView(workflowID: workflowID, path: path, selection: $selection)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { toggleSelection() }) {
                WorkflowStepSummary(number: path.index + 1, step: step)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isSelected ? "Collapses the editor" : "Opens the editor"))
            Spacer(minLength: 4)
            WorkflowStepControls(canMoveUp: WorkflowStepTree.canMoveStep(at: path, by: -1, in: rootSteps),
                                 canMoveDown: WorkflowStepTree.canMoveStep(at: path, by: 1, in: rootSteps),
                                 onMove: { offset in move(by: offset) },
                                 onDelete: { delete() })
        }
    }

    private func toggleSelection() {
        selection = isSelected ? nil : path
    }

    private func move(by offset: Int) {
        var moved: WorkflowStepPath?
        let source: WorkflowStepPath = path
        WorkflowEditing.update(workflowID, in: model) { workflow in
            moved = WorkflowStepTree.moveStep(at: source, by: offset, in: &workflow.steps)
        }
        // Paths are positional, so any open editor may now point at a different step: follow the
        // moved step when it was the selected one, otherwise close the editor.
        if let destination = moved {
            selection = isSelected ? destination : nil
        }
    }

    private func delete() {
        let target: WorkflowStepPath = path
        selection = nil
        WorkflowEditing.update(workflowID, in: model) { workflow in
            _ = WorkflowStepTree.removeStep(at: target, in: &workflow.steps)
        }
    }
}

@MainActor
struct WorkflowStepSummary: View {
    let number: Int
    let step: WorkflowStep
    @Environment(AppModel.self) private var model

    var body: some View {
        let configuration: Configuration = model.configuration
        let title: String = WorkflowText.title(of: step, in: configuration) { ActionAppNames.displayName(for: $0) }
        let subtitle: String? = WorkflowText.subtitle(of: step, in: configuration) { ActionAppNames.displayName(for: $0) }
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.18)))
                .accessibilityLabel(Text("Step \(number)"))
            Image(systemName: WorkflowText.symbolName(of: step))
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

@MainActor
struct WorkflowStepControls: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { onMove(-1) }) {
                Image(systemName: "arrow.up")
            }
            .disabled(!canMoveUp)
            .accessibilityLabel(Text("Move step up"))
            .help("Move up")
            Button(action: { onMove(1) }) {
                Image(systemName: "arrow.down")
            }
            .disabled(!canMoveDown)
            .accessibilityLabel(Text("Move step down"))
            .help("Move down")
            Button(action: { onDelete() }) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(Text("Delete step"))
            .help("Delete this step")
        }
        .buttonStyle(.borderless)
    }
}

/// The "then" and "otherwise" lists of a condition step.
@MainActor
struct WorkflowBranchesView: View {
    let workflowID: UUID
    let path: WorkflowStepPath
    @Binding var selection: WorkflowStepPath?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            branch(title: "If true", symbolName: "checkmark.circle", branch: .then)
            branch(title: "Otherwise", symbolName: "xmark.circle", branch: .otherwise)
        }
        .padding(.leading, 14)
    }

    private func branch(title: String, symbolName: String, branch: WorkflowStepBranch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            WorkflowStepListView(workflowID: workflowID, listPath: path.branch(branch), selection: $selection)
        }
    }
}
