import SwiftUI
import MFCore
import MFEngine

/// Result of the last manual run of a workflow in the builder (memory only).
enum WorkflowRunOutcome: Equatable {
    case succeeded(Date)
    case failed(String, Date)
}

/// Mutations of workflows, all funnelled through `AppModel.update`.
@MainActor
enum WorkflowEditing {
    static func workflow(_ id: UUID, in model: AppModel) -> Workflow? {
        model.configuration.workflows.first(where: { $0.id == id })
    }

    static func update(_ id: UUID, in model: AppModel, _ body: (inout Workflow) -> Void) {
        model.update { configuration in
            guard let index = configuration.workflows.firstIndex(where: { $0.id == id }) else { return }
            body(&configuration.workflows[index])
        }
    }

    @discardableResult
    static func add(_ workflow: Workflow, to model: AppModel) -> UUID {
        model.update { configuration in
            configuration.workflows.append(workflow)
        }
        return workflow.id
    }

    static func addEmpty(to model: AppModel) -> UUID {
        let names: [String] = model.configuration.workflows.map { $0.name }
        let workflow = Workflow(name: WorkflowText.uniqueName("New Workflow", existing: names))
        return add(workflow, to: model)
    }

    static func addExample(to model: AppModel) -> UUID {
        let names: [String] = model.configuration.workflows.map { $0.name }
        let workflow: Workflow = WorkflowExamples.sample(name: WorkflowText.uniqueName("Open VS Code Palette", existing: names))
        return add(workflow, to: model)
    }

    static func duplicate(_ id: UUID, in model: AppModel) -> UUID? {
        guard let original = workflow(id, in: model) else { return nil }
        let names: [String] = model.configuration.workflows.map { $0.name }
        let copy = Workflow(id: UUID(), name: WorkflowText.uniqueName(original.name + " Copy", existing: names),
                            symbolName: original.symbolName, steps: original.steps, timeout: original.timeout,
                            continueOnError: original.continueOnError)
        return add(copy, to: model)
    }

    static func delete(_ id: UUID, in model: AppModel) {
        model.update { configuration in
            configuration.workflows.removeAll(where: { $0.id == id })
        }
    }

    static func stepBinding(workflowID: UUID, path: WorkflowStepPath, fallback: WorkflowStep, model: AppModel) -> Binding<WorkflowStep> {
        Binding<WorkflowStep>(
            get: {
                guard let workflow = WorkflowEditing.workflow(workflowID, in: model),
                      let step = WorkflowStepTree.step(at: path, in: workflow.steps) else { return fallback }
                return step
            },
            set: { newValue in
                WorkflowEditing.update(workflowID, in: model) { workflow in
                    _ = WorkflowStepTree.replaceStep(at: path, with: newValue, in: &workflow.steps)
                }
            }
        )
    }
}
