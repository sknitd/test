import SwiftUI
import MFCore
import MFEngine

/// Inline editor for one step; the kind of step decides which fields are shown.
@MainActor
struct WorkflowStepEditor: View {
    @Binding var step: WorkflowStep

    var body: some View {
        switch step {
        case .action:
            // Workflows cannot run other workflows, so that category is not offered here.
            ActionEditor(action: actionBinding, allowsWorkflows: false)
        case .delay:
            WorkflowDelayEditor(seconds: delayBinding)
        case .waitForApp:
            WorkflowWaitEditor(bundleID: waitBundleBinding, timeout: waitTimeoutBinding)
        case .conditional:
            WorkflowConditionEditor(condition: conditionBinding)
        case .notify:
            WorkflowNotifyEditor(title: notifyTitleBinding, message: notifyBodyBinding)
        }
    }

    private var actionBinding: Binding<Action> {
        Binding<Action>(
            get: {
                if case .action(let action) = step { return action }
                return Action.none
            },
            set: { newValue in step = .action(newValue) }
        )
    }

    private var delayBinding: Binding<Double> {
        Binding<Double>(
            get: {
                if case .delay(let seconds) = step { return seconds }
                return 0
            },
            set: { newValue in step = .delay(seconds: min(max(newValue, 0), 600)) }
        )
    }

    private var waitBundleBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .waitForApp(let bundleID, _) = step { return bundleID }
                return ""
            },
            set: { newValue in
                if case .waitForApp(_, let timeout) = step {
                    step = .waitForApp(bundleID: newValue, timeout: timeout)
                }
            }
        )
    }

    private var waitTimeoutBinding: Binding<Double> {
        Binding<Double>(
            get: {
                if case .waitForApp(_, let timeout) = step { return timeout }
                return 10
            },
            set: { newValue in
                if case .waitForApp(let bundleID, _) = step {
                    step = .waitForApp(bundleID: bundleID, timeout: min(max(newValue, 1), 600))
                }
            }
        )
    }

    private var conditionBinding: Binding<WorkflowCondition> {
        Binding<WorkflowCondition>(
            get: {
                if case .conditional(let condition, _, _) = step { return condition }
                return WorkflowCondition.frontmostAppIs(bundleID: "")
            },
            set: { newValue in
                // Only the condition changes; both branches are kept exactly as they are.
                if case .conditional(_, let then, let otherwise) = step {
                    step = .conditional(newValue, then: then, otherwise: otherwise)
                }
            }
        )
    }

    private var notifyTitleBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .notify(let title, _) = step { return title }
                return ""
            },
            set: { newValue in
                if case .notify(_, let body) = step {
                    step = .notify(title: newValue, body: body)
                }
            }
        )
    }

    private var notifyBodyBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .notify(_, let body) = step { return body }
                return ""
            },
            set: { newValue in
                if case .notify(let title, _) = step {
                    step = .notify(title: title, body: newValue)
                }
            }
        )
    }
}

@MainActor
struct WorkflowDelayEditor: View {
    @Binding var seconds: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Wait")
            TextField("Seconds", value: $seconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .labelsHidden()
                .accessibilityLabel(Text("Delay in seconds"))
            Stepper("seconds", value: $seconds, in: 0...600, step: 0.1)
        }
    }
}

@MainActor
struct WorkflowWaitEditor: View {
    @Binding var bundleID: String
    @Binding var timeout: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionAppPicker(title: "App", bundleID: $bundleID)
            Stepper(value: $timeout, in: 1...600, step: 1) {
                Text("Wait up to \(ActionText.numberString(timeout)) seconds for it to become frontmost")
            }
            Text("If the app is not frontmost in time, this step fails with a timeout.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct WorkflowNotifyEditor: View {
    @Binding var title: String
    @Binding var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Notification title"))
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $message, prompt: Text("Notification text"), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Text("Shown only when notifications are enabled in Settings and allowed in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Editor for a condition: kind, value and an optional NOT wrapper.
@MainActor
struct WorkflowConditionEditor: View {
    @Binding var condition: WorkflowCondition

    private var current: WorkflowConditionModel { WorkflowConditionModel(condition) }

    private var kind: Binding<WorkflowConditionModel.Kind> {
        Binding<WorkflowConditionModel.Kind>(
            get: { current.kind },
            set: { newValue in
                var edited: WorkflowConditionModel = current
                if edited.kind.usesBundleID != newValue.usesBundleID { edited.value = "" }
                edited.kind = newValue
                condition = edited.condition
            }
        )
    }

    private var value: Binding<String> {
        Binding<String>(
            get: { current.value },
            set: { newValue in
                var edited: WorkflowConditionModel = current
                edited.value = newValue
                condition = edited.condition
            }
        )
    }

    private var isNegated: Binding<Bool> {
        Binding<Bool>(
            get: { current.isNegated },
            set: { newValue in
                var edited: WorkflowConditionModel = current
                edited.isNegated = newValue
                condition = edited.condition
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Condition", selection: kind) {
                ForEach(WorkflowConditionModel.Kind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if current.kind.usesBundleID {
                ActionAppPicker(title: "App", bundleID: value)
            } else {
                TextField("Text", text: value, prompt: Text("Text to look for"))
                    .textFieldStyle(.roundedBorder)
                Text("The clipboard is read only at the moment this step runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Invert (NOT): run the “If true” branch when this is false", isOn: isNegated)
        }
    }
}
