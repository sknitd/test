import Foundation
import MFCore

/// The kinds of step the builder can add.
enum WorkflowStepKind: String, CaseIterable, Identifiable {
    case action, delay, waitForApp, conditional, notify

    var id: String { rawValue }

    init(_ step: WorkflowStep) {
        switch step {
        case .action: self = .action
        case .delay: self = .delay
        case .waitForApp: self = .waitForApp
        case .conditional: self = .conditional
        case .notify: self = .notify
        }
    }

    var title: String {
        switch self {
        case .action: return "Action"
        case .delay: return "Delay"
        case .waitForApp: return "Wait for App"
        case .conditional: return "Condition"
        case .notify: return "Notification"
        }
    }

    var symbolName: String {
        switch self {
        case .action: return "bolt.fill"
        case .delay: return "timer"
        case .waitForApp: return "hourglass"
        case .conditional: return "arrow.triangle.branch"
        case .notify: return "bell"
        }
    }

    /// A new step of this kind with sensible defaults.
    var newStep: WorkflowStep {
        switch self {
        case .action: return .action(.none)
        case .delay: return .delay(seconds: 0.5)
        case .waitForApp: return .waitForApp(bundleID: "", timeout: 10)
        case .conditional: return .conditional(.frontmostAppIs(bundleID: ""), then: [], otherwise: [])
        case .notify: return .notify(title: "MagicForge", body: "")
        }
    }
}

/// Flat, editable view of a (possibly negated) workflow condition.
struct WorkflowConditionModel: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case frontmostAppIs, appIsRunning, clipboardContains
        var id: String { rawValue }
        var title: String {
            switch self {
            case .frontmostAppIs: return "Frontmost app is"
            case .appIsRunning: return "App is running"
            case .clipboardContains: return "Clipboard contains"
            }
        }
        var usesBundleID: Bool { self != .clipboardContains }
    }

    var kind: Kind
    /// Bundle identifier or the text to look for.
    var value: String
    var isNegated: Bool

    /// Collapses any number of nested `.not` wrappers into a single flag.
    init(_ condition: WorkflowCondition) {
        var negated: Bool = false
        var current: WorkflowCondition = condition
        while case .not(let inner) = current {
            negated.toggle()
            current = inner
        }
        switch current {
        case .frontmostAppIs(let bundleID):
            kind = .frontmostAppIs; value = bundleID
        case .appIsRunning(let bundleID):
            kind = .appIsRunning; value = bundleID
        case .clipboardContains(let text):
            kind = .clipboardContains; value = text
        case .not:
            // Unreachable: the loop above removed every wrapper.
            kind = .frontmostAppIs; value = ""
        }
        isNegated = negated
    }

    var condition: WorkflowCondition {
        let base: WorkflowCondition
        switch kind {
        case .frontmostAppIs: base = .frontmostAppIs(bundleID: value)
        case .appIsRunning: base = .appIsRunning(bundleID: value)
        case .clipboardContains: base = .clipboardContains(value)
        }
        return isNegated ? .not(base) : base
    }

    func summary(appName: (String) -> String = { $0 }) -> String {
        let subject: String
        if kind.usesBundleID {
            subject = value.isEmpty ? "(no app chosen)" : appName(value)
        } else {
            subject = value.isEmpty ? "(no text)" : "“\(ActionText.firstLine(value, limit: 30))”"
        }
        switch (kind, isNegated) {
        case (.frontmostAppIs, false): return "If frontmost app is \(subject)"
        case (.frontmostAppIs, true): return "If frontmost app is not \(subject)"
        case (.appIsRunning, false): return "If \(subject) is running"
        case (.appIsRunning, true): return "If \(subject) is not running"
        case (.clipboardContains, false): return "If clipboard contains \(subject)"
        case (.clipboardContains, true): return "If clipboard does not contain \(subject)"
        }
    }
}

/// Text for step cards. No UI types in this file.
enum WorkflowText {
    static func title(of step: WorkflowStep, in configuration: Configuration, appName: (String) -> String = { $0 }) -> String {
        switch step {
        case .action(let action):
            if action == .none { return "Choose an action" }
            return ActionText.title(for: action, appName: appName)
        case .delay(let seconds):
            return "Wait \(ActionText.numberString(seconds)) s"
        case .waitForApp(let bundleID, _):
            return bundleID.isEmpty ? "Wait for app (none chosen)" : "Wait for \(appName(bundleID))"
        case .conditional(let condition, _, _):
            return WorkflowConditionModel(condition).summary(appName: appName)
        case .notify(let title, _):
            return title.isEmpty ? "Show notification" : "Notify: \(ActionText.firstLine(title, limit: 36))"
        }
    }

    static func subtitle(of step: WorkflowStep, in configuration: Configuration,
                         appName: (String) -> String = { $0 }) -> String? {
        switch step {
        case .action(let action):
            return ActionText.parameterSummary(for: action, in: configuration)
        case .delay:
            return nil
        case .waitForApp(_, let timeout):
            return "Fails after \(ActionText.numberString(timeout)) s if the app is not frontmost"
        case .conditional(_, let then, let otherwise):
            return "\(then.count) step\(then.count == 1 ? "" : "s") if true, \(otherwise.count) otherwise"
        case .notify(_, let body):
            let line: String = ActionText.firstLine(body)
            return line.isEmpty ? nil : line
        }
    }

    static func symbolName(of step: WorkflowStep) -> String {
        if case .action(let action) = step, action != .none { return action.symbolName }
        return WorkflowStepKind(step).symbolName
    }

    static func outcomeText(_ result: Result<Void, ActionError>) -> String {
        switch result {
        case .success: return "Finished successfully."
        case .failure(let error): return ActionText.describe(error)
        }
    }

    /// A name not yet used by another workflow ("Workflow", "Workflow 2", …).
    static func uniqueName(_ base: String, existing: [String]) -> String {
        if !existing.contains(base) { return base }
        var number: Int = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}

enum WorkflowExamples {
    static let visualStudioCodeBundleID = "com.microsoft.VSCode"

    /// The sample from the product spec: open Spotlight → launch VS Code → wait until it is
    /// frontmost → send ⇧⌘P → show a notification.
    static func sample(name: String) -> Workflow {
        var palette = KeyCombo(keyCode: 35, command: true, shift: true)   // kVK_ANSI_P
        palette.label = palette.displayString
        let steps: [WorkflowStep] = [
            .action(.system(.spotlight)),
            .action(.app(.launch(bundleID: visualStudioCodeBundleID))),
            .waitForApp(bundleID: visualStudioCodeBundleID, timeout: 10),
            .action(.keyboard(palette)),
            .notify(title: "MagicForge", body: "VS Code is ready and the Command Palette is open."),
        ]
        return Workflow(name: name, symbolName: "chevron.left.forwardslash.chevron.right", steps: steps,
                        timeout: 30, continueOnError: false)
    }
}
