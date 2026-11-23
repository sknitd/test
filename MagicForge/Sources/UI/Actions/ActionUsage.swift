import Foundation
import MFCore

/// One place in the configuration that references an action.
struct ActionUsageLocation: Identifiable, Hashable {
    enum Kind: String { case binding, radialMenu, workflow }
    var id: String
    var kind: Kind
    /// Profile, radial menu or workflow name.
    var container: String
    /// Trigger, item title or step number.
    var detail: String
}

/// A script referenced by the configuration together with where it is used.
struct ActionScriptReference: Identifiable, Hashable {
    var script: ScriptAction
    var locations: [ActionUsageLocation]
    var id: String { script.trustPayload }
}

/// Walks every action stored in a configuration. No UI types in this file.
enum ActionUsage {
    typealias Visitor = (Action, ActionUsageLocation) -> Void

    static func forEachAction(in configuration: Configuration, _ visit: Visitor) {
        for profile in configuration.profiles {
            for binding in profile.bindings {
                let location = ActionUsageLocation(id: "binding-\(binding.id.uuidString)", kind: .binding,
                                                   container: profile.name, detail: binding.trigger.displayName)
                visit(binding.action, location)
            }
        }
        for menu in configuration.radialMenus {
            visitItems(menu.items, menuName: menu.name, trail: "", visit)
        }
        for workflow in configuration.workflows {
            visitSteps(workflow.steps, workflow: workflow, prefix: "", visit)
        }
    }

    private static func visitItems(_ items: [RadialMenuItem], menuName: String, trail: String, _ visit: Visitor) {
        for item in items {
            let title: String = trail.isEmpty ? item.title : trail + " › " + item.title
            if item.children.isEmpty {
                let location = ActionUsageLocation(id: "radial-\(item.id.uuidString)", kind: .radialMenu,
                                                   container: menuName, detail: title)
                visit(item.action, location)
            } else {
                visitItems(item.children, menuName: menuName, trail: title, visit)
            }
        }
    }

    private static func visitSteps(_ steps: [WorkflowStep], workflow: Workflow, prefix: String, _ visit: Visitor) {
        for (index, step) in steps.enumerated() {
            let number: String = prefix + String(index + 1)
            switch step {
            case .action(let action):
                let location = ActionUsageLocation(id: "workflow-\(workflow.id.uuidString)-\(number)", kind: .workflow,
                                                   container: workflow.name, detail: "Step \(number)")
                visit(action, location)
            case .conditional(_, let then, let otherwise):
                visitSteps(then, workflow: workflow, prefix: number + ".then.", visit)
                visitSteps(otherwise, workflow: workflow, prefix: number + ".else.", visit)
            case .delay, .waitForApp, .notify:
                break
            }
        }
    }

    /// Everything that references an action equal to `action`.
    static func locations(of action: Action, in configuration: Configuration) -> [ActionUsageLocation] {
        var result: [ActionUsageLocation] = []
        if action == .none { return result }
        forEachAction(in: configuration) { candidate, location in
            if candidate == action { result.append(location) }
        }
        return result
    }

    /// Every distinct script in the configuration, in first-use order.
    static func scripts(in configuration: Configuration) -> [ActionScriptReference] {
        var order: [ScriptAction] = []
        var locations: [ScriptAction: [ActionUsageLocation]] = [:]
        forEachAction(in: configuration) { candidate, location in
            guard let script = candidate.script else { return }
            if locations[script] == nil { order.append(script) }
            locations[script, default: []].append(location)
        }
        return order.map { ActionScriptReference(script: $0, locations: locations[$0] ?? []) }
    }
}
