import Foundation
import MFCore

/// Hard limits enforced by `WorkflowValidator` and `WorkflowRunner`.
public enum WorkflowLimits {
    /// Longest single `.delay` step, seconds.
    public static let maxDelay: Double = 60
    /// Longest `.waitForApp` timeout, seconds.
    public static let maxWaitForAppTimeout: Double = 120
    /// Total number of steps, counting steps inside both branches of every conditional.
    public static let maxSteps = 200
    /// How many conditionals may be nested inside each other.
    public static let maxConditionalDepth = 4
    /// Depth of `.not` wrappers in one condition.
    public static let maxConditionDepth = 8
    /// Allowed whole-workflow timeout, seconds.
    public static let timeoutRange: ClosedRange<Double> = 1...600
    /// Workflows that may run at the same time.
    public static let maxConcurrentRuns = 4
    /// How often `.waitForApp` re-checks the frontmost app, seconds.
    public static let waitForAppPollInterval: Double = 0.1
}

/// Static checks for workflows. An empty result means the workflow may run.
public enum WorkflowValidator {
    /// Every problem with the workflow, including references to radial menus and AI prompt
    /// templates that do not exist in `configuration`. Messages are user-facing sentences.
    public static func issues(for workflow: Workflow, in configuration: Configuration) -> [String] {
        var issues = structuralIssues(for: workflow)
        let menuIDs = Set(configuration.radialMenus.map(\.id))
        let templateIDs = Set(configuration.ai.templates.map(\.id))
        visitActions(in: workflow.steps, prefix: "") { action, name in
            switch action {
            case .radialMenu(let id) where !menuIDs.contains(id):
                issues.append("\(name) opens a radial menu that no longer exists.")
            case .ai(let id) where !templateIDs.contains(id):
                issues.append("\(name) uses an AI prompt that no longer exists.")
            default:
                break
            }
        }
        return issues
    }

    /// Problems that can be found without a configuration. `WorkflowRunner` refuses to run a
    /// workflow for which this is not empty.
    public static func structuralIssues(for workflow: Workflow) -> [String] {
        var issues: [String] = []
        if workflow.steps.isEmpty { issues.append("The workflow has no steps.") }
        if !workflow.timeout.isFinite || !WorkflowLimits.timeoutRange.contains(workflow.timeout) {
            let range = WorkflowLimits.timeoutRange
            issues.append("The workflow timeout must be between \(format(range.lowerBound)) and \(format(range.upperBound)) seconds.")
        }
        let total = stepCount(workflow.steps)
        if total > WorkflowLimits.maxSteps {
            issues.append("The workflow has \(total) steps; the limit is \(WorkflowLimits.maxSteps).")
        }
        check(workflow.steps, prefix: "", conditionalDepth: 0, issues: &issues)
        return issues
    }

    /// Steps including those nested in conditionals (a conditional itself counts as one).
    public static func stepCount(_ steps: [WorkflowStep]) -> Int {
        steps.reduce(0) { total, step in
            if case .conditional(_, let then, let otherwise) = step {
                return total + 1 + stepCount(then) + stepCount(otherwise)
            }
            return total + 1
        }
    }

    /// True when any step (at any depth) runs another workflow.
    public static func containsNestedWorkflow(_ steps: [WorkflowStep]) -> Bool {
        var found = false
        visitActions(in: steps, prefix: "") { action, _ in
            if case .workflow = action { found = true }
        }
        return found
    }

    /// Every script action in the workflow, for trust checks before running or importing.
    public static func scripts(in workflow: Workflow) -> [ScriptAction] {
        var scripts: [ScriptAction] = []
        visitActions(in: workflow.steps, prefix: "") { action, _ in
            if let script = action.script { scripts.append(script) }
        }
        return scripts
    }

    // MARK: Internals

    /// "Step 3", or "Step 3 › Then 1" for steps inside conditionals.
    private static func name(_ prefix: String, _ index: Int) -> String {
        prefix.isEmpty ? "Step \(index + 1)" : "\(prefix) \(index + 1)"
    }

    private static func check(_ steps: [WorkflowStep], prefix: String, conditionalDepth: Int, issues: inout [String]) {
        for (index, step) in steps.enumerated() {
            let name = name(prefix, index)
            switch step {
            case .action(let action):
                if case .workflow = action {
                    issues.append("\(name) runs another workflow. Workflows cannot be nested.")
                }
            case .delay(let seconds):
                if !seconds.isFinite || seconds <= 0 {
                    issues.append("\(name) has a delay that is not a positive number of seconds.")
                } else if seconds > WorkflowLimits.maxDelay {
                    issues.append("\(name) waits \(format(seconds)) seconds; a single delay is limited to "
                        + "\(format(WorkflowLimits.maxDelay)) seconds.")
                }
            case .waitForApp(let bundleID, let timeout):
                if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(name) waits for an app but no app is chosen.")
                }
                if !timeout.isFinite || timeout <= 0 {
                    issues.append("\(name) has a wait timeout that is not a positive number of seconds.")
                } else if timeout > WorkflowLimits.maxWaitForAppTimeout {
                    issues.append("\(name) waits up to \(format(timeout)) seconds for an app; the limit is "
                        + "\(format(WorkflowLimits.maxWaitForAppTimeout)) seconds.")
                }
            case .conditional(let condition, let then, let otherwise):
                let depth = conditionalDepth + 1
                if depth > WorkflowLimits.maxConditionalDepth {
                    issues.append("\(name) nests conditions more than \(WorkflowLimits.maxConditionalDepth) levels deep.")
                    continue
                }
                checkCondition(condition, name: name, depth: 0, issues: &issues)
                if then.isEmpty && otherwise.isEmpty {
                    issues.append("\(name) is a condition with no steps in either branch.")
                }
                check(then, prefix: "\(name) › Then", conditionalDepth: depth, issues: &issues)
                check(otherwise, prefix: "\(name) › Otherwise", conditionalDepth: depth, issues: &issues)
            case .notify(let title, let body):
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(name) shows a notification with no text.")
                }
            }
        }
    }

    private static func checkCondition(_ condition: WorkflowCondition, name: String, depth: Int, issues: inout [String]) {
        switch condition {
        case .frontmostAppIs(let bundleID), .appIsRunning(let bundleID):
            if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(name) checks an app but no app is chosen.")
            }
        case .clipboardContains(let text):
            if text.isEmpty { issues.append("\(name) checks the clipboard for empty text.") }
        case .not(let inner):
            if depth + 1 > WorkflowLimits.maxConditionDepth {
                issues.append("\(name) has a condition that is negated too many times.")
            } else {
                checkCondition(inner, name: name, depth: depth + 1, issues: &issues)
            }
        }
    }

    /// Calls `body` for every action step at any depth (bounded so hostile input cannot recurse forever).
    private static func visitActions(in steps: [WorkflowStep], prefix: String, depth: Int = 0,
                                     _ body: (Action, String) -> Void) {
        guard depth <= 64 else { return }
        for (index, step) in steps.enumerated() {
            let name = name(prefix, index)
            switch step {
            case .action(let action):
                body(action, name)
            case .conditional(_, let then, let otherwise):
                visitActions(in: then, prefix: "\(name) › Then", depth: depth + 1, body)
                visitActions(in: otherwise, prefix: "\(name) › Otherwise", depth: depth + 1, body)
            case .delay, .waitForApp, .notify:
                break
            }
        }
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "an invalid number of" }
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        return String((value * 100).rounded() / 100)
    }
}
