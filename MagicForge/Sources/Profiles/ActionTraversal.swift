import Foundation
import MFCore

/// Walks and rewrites the actions nested inside profiles, workflows and radial menus.
enum ActionTraversal {
    static func actions(in profile: Profile) -> [Action] { profile.bindings.map(\.action) }

    static func actions(in steps: [WorkflowStep]) -> [Action] {
        var result: [Action] = []
        for step in steps {
            switch step {
            case .action(let action): result.append(action)
            case .conditional(_, let then, let otherwise):
                result += actions(in: then)
                result += actions(in: otherwise)
            case .delay, .waitForApp, .notify: break
            }
        }
        return result
    }

    /// Includes the action of items that currently open a submenu: it is ignored at run time but
    /// becomes live again as soon as the children are removed, so trust checks must see it.
    static func actions(in items: [RadialMenuItem]) -> [Action] {
        var result: [Action] = []
        for item in items {
            result.append(item.action)
            result += actions(in: item.children)
        }
        return result
    }

    static func mapActions(in steps: [WorkflowStep], _ transform: (Action) -> Action) -> [WorkflowStep] {
        steps.map { step in
            switch step {
            case .action(let action): return .action(transform(action))
            case .conditional(let condition, let then, let otherwise):
                return .conditional(condition, then: mapActions(in: then, transform),
                                    otherwise: mapActions(in: otherwise, transform))
            case .delay, .waitForApp, .notify: return step
            }
        }
    }

    static func mapItems(_ items: [RadialMenuItem], _ transform: (RadialMenuItem) -> RadialMenuItem) -> [RadialMenuItem] {
        items.map { item in
            var copy = transform(item)
            copy.children = mapItems(copy.children, transform)
            return copy
        }
    }

    static func allItems(in items: [RadialMenuItem]) -> [RadialMenuItem] {
        items.flatMap { [$0] + allItems(in: $0.children) }
    }
}

/// The workflows, radial menus and AI templates something refers to.
struct ReferenceSet: Equatable {
    var workflows: Set<UUID> = []
    var radialMenus: Set<UUID> = []
    var templates: Set<UUID> = []

    mutating func insert(_ action: Action) {
        switch action {
        case .workflow(let id): workflows.insert(id)
        case .radialMenu(let id): radialMenus.insert(id)
        case .ai(let id): templates.insert(id)
        case .none, .system, .window, .app, .keyboard, .mouse, .text, .script, .control: break
        }
    }

    /// Everything reachable from `actions`, following workflow and radial-menu references
    /// through `configuration` (cycles are tolerated).
    static func reachable(from actions: [Action], in configuration: Configuration) -> ReferenceSet {
        var result = ReferenceSet()
        var pending = actions
        while let action = pending.popLast() {
            switch action {
            case .workflow(let id):
                guard result.workflows.insert(id).inserted else { continue }
                if let workflow = configuration.workflows.first(where: { $0.id == id }) {
                    pending += ActionTraversal.actions(in: workflow.steps)
                }
            case .radialMenu(let id):
                guard result.radialMenus.insert(id).inserted else { continue }
                if let menu = configuration.radialMenus.first(where: { $0.id == id }) {
                    pending += ActionTraversal.actions(in: menu.items)
                }
            case .ai(let id): result.templates.insert(id)
            case .none, .system, .window, .app, .keyboard, .mouse, .text, .script, .control: break
            }
        }
        return result
    }
}

/// Plain-English names that do not depend on the catalog in MFCore.
enum GestureNaming {
    static func name(_ kind: GestureKind) -> String {
        var words: [String] = []
        var current = ""
        for character in kind.rawValue {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let joined = words.map { $0.lowercased() }.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func name(_ trigger: GestureTrigger) -> String {
        switch trigger {
        case .single(let kind): return name(kind)
        case .sequence(let kinds): return kinds.map(name).joined(separator: ", then ")
        }
    }
}
