import SwiftUI
import MFCore
import MFEngine

/// Editor for one workflow: settings, run controls, validation and the step tree.
@MainActor
struct WorkflowDetailView: View {
    let workflowID: UUID
    @Binding var selectedStep: WorkflowStepPath?
    @Binding var outcomes: [UUID: WorkflowRunOutcome]
    @Environment(AppModel.self) private var model

    var body: some View {
        if let workflow = WorkflowEditing.workflow(workflowID, in: model) {
            VStack(alignment: .leading, spacing: 16) {
                WorkflowSettingsCard(workflow: workflow)
                WorkflowRunCard(workflow: workflow, outcomes: $outcomes)
                MFCard("Steps", systemImage: "list.number") {
                    WorkflowStepListView(workflowID: workflowID, listPath: WorkflowStepListPath.root,
                                         selection: $selectedStep)
                }
                WorkflowActivityCard()
            }
        } else {
            MFEmptyState(systemImage: "questionmark.folder", title: "Workflow Not Found",
                         message: "This workflow was deleted. Pick another one from the list.")
        }
    }
}

/// Name, symbol, timeout and error handling of a workflow.
@MainActor
struct WorkflowSettingsCard: View {
    let workflow: Workflow
    @Environment(AppModel.self) private var model

    private var name: Binding<String> {
        let id: UUID = workflow.id
        return Binding<String>(
            get: { WorkflowEditing.workflow(id, in: model)?.name ?? "" },
            set: { newValue in WorkflowEditing.update(id, in: model) { $0.name = newValue } }
        )
    }

    private var symbolName: Binding<String> {
        let id: UUID = workflow.id
        return Binding<String>(
            get: { WorkflowEditing.workflow(id, in: model)?.symbolName ?? "" },
            set: { newValue in WorkflowEditing.update(id, in: model) { $0.symbolName = newValue } }
        )
    }

    private var timeout: Binding<Double> {
        let id: UUID = workflow.id
        return Binding<Double>(
            get: { WorkflowEditing.workflow(id, in: model)?.timeout ?? 30 },
            set: { newValue in WorkflowEditing.update(id, in: model) { $0.timeout = newValue } }
        )
    }

    private var continueOnError: Binding<Bool> {
        let id: UUID = workflow.id
        return Binding<Bool>(
            get: { WorkflowEditing.workflow(id, in: model)?.continueOnError ?? false },
            set: { newValue in WorkflowEditing.update(id, in: model) { $0.continueOnError = newValue } }
        )
    }

    var body: some View {
        MFCard("Workflow", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Name")
                    TextField("Name", text: name, prompt: Text("Workflow name"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(Text("Workflow name"))
                }
                ActionSymbolField(title: "Symbol", symbolName: symbolName)
                Stepper(value: timeout, in: 1...600, step: 1) {
                    Text("Give up after \(ActionText.numberString(workflow.timeout)) seconds")
                }
                Toggle("Continue with the next step when a step fails", isOn: continueOnError)
            }
        }
    }
}

/// Run / cancel controls, validation issues and the outcome of the last manual run.
@MainActor
struct WorkflowRunCard: View {
    let workflow: Workflow
    @Binding var outcomes: [UUID: WorkflowRunOutcome]
    @Environment(AppModel.self) private var model

    private var runs: [RunningWorkflow] {
        model.runningWorkflows.filter { $0.workflowID == workflow.id }
    }

    var body: some View {
        let issues: [String] = model.validationIssues(for: workflow)
        MFCard("Run", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 10) {
                controls(hasIssues: !issues.isEmpty)
                ForEach(runs) { run in
                    WorkflowRunningRow(run: run)
                }
                outcomeView
                if !issues.isEmpty {
                    Divider()
                    WorkflowIssueList(issues: issues)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controls(hasIssues: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: { run() }) {
                Label("Run Workflow", systemImage: "play.fill")
            }
            .disabled(workflow.steps.isEmpty || !runs.isEmpty)
            .help("Runs the workflow now, for real")
            if !model.runningWorkflows.isEmpty {
                Button(action: { model.cancelAllWorkflows() }) {
                    Label("Cancel All Running Workflows", systemImage: "stop.fill")
                }
                .help("Stops every workflow that is currently running")
            }
            if hasIssues {
                MFStatusBadge("Has problems", style: .warning)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var outcomeView: some View {
        if let outcome = outcomes[workflow.id], runs.isEmpty {
            switch outcome {
            case .succeeded(let date):
                Label("Finished successfully at \(Self.timeText(date))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.callout)
            case .failed(let message, let date):
                Label("Failed at \(Self.timeText(date)): \(message)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private static func timeText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
    }

    private func run() {
        let id: UUID = workflow.id
        outcomes[id] = nil
        let outcomesBinding: Binding<[UUID: WorkflowRunOutcome]> = $outcomes
        Task {
            let result: Result<Void, ActionError> = await model.run(.workflow(id: id), source: .manualTest)
            switch result {
            case .success:
                outcomesBinding.wrappedValue[id] = .succeeded(Date())
            case .failure(let error):
                outcomesBinding.wrappedValue[id] = .failed(ActionText.describe(error), Date())
            }
        }
    }
}

@MainActor
struct WorkflowRunningRow: View {
    let run: RunningWorkflow

    private var progressText: String {
        run.progress.isEmpty ? "Running…" : "Running step " + run.progress
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(progressText)
                .font(.callout)
            Text("started \(DateFormatter.localizedString(from: run.startedAt, dateStyle: .none, timeStyle: .medium))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct WorkflowIssueList: View {
    let issues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(issues.indices, id: \.self) { index in
                Label(issues[index], systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The newest engine activity entries, so run results and failures are visible in context.
@MainActor
struct WorkflowActivityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries: [ActivityEntry] = Array(model.activityLog.prefix(6))
        MFCard("Recent Activity", systemImage: "clock") {
            VStack(alignment: .leading, spacing: 4) {
                if entries.isEmpty {
                    Text("Nothing has run yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        WorkflowActivityRow(entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
struct WorkflowActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(DateFormatter.localizedString(from: entry.date, dateStyle: .none, timeStyle: .medium))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(entry.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch entry.level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: return Color.secondary
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
}
