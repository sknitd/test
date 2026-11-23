import Foundation
import MFCore

// Addressing scheme for the (recursive) step tree of a workflow. No UI types in this file.
//
// A *list* of steps is addressed by a `WorkflowStepListPath`: the empty path is the workflow's
// top-level list; each component descends into one branch of a conditional step.
// A single *step* is addressed by the list that contains it plus its index.

enum WorkflowStepBranch: String, Hashable, CaseIterable {
    case then, otherwise
}

struct WorkflowStepListPath: Hashable {
    struct Component: Hashable {
        /// Index of the conditional step in its parent list.
        var index: Int
        var branch: WorkflowStepBranch
    }
    var components: [Component] = []

    static let root = WorkflowStepListPath()

    /// Number of conditionals this list is nested in.
    var depth: Int { components.count }

    func step(_ index: Int) -> WorkflowStepPath { WorkflowStepPath(list: self, index: index) }
}

struct WorkflowStepPath: Hashable {
    var list: WorkflowStepListPath
    var index: Int

    /// The list of one branch of the conditional step at this path.
    func branch(_ branch: WorkflowStepBranch) -> WorkflowStepListPath {
        var path: WorkflowStepListPath = list
        path.components.append(WorkflowStepListPath.Component(index: index, branch: branch))
        return path
    }

    /// Human readable step number such as "2" or "2 › then › 1".
    var displayNumber: String {
        var parts: [String] = []
        for component in list.components {
            parts.append(String(component.index + 1))
            parts.append(component.branch == .then ? "then" : "else")
        }
        parts.append(String(index + 1))
        return parts.joined(separator: " › ")
    }
}

/// Pure get / set / insert / remove / move helpers over `[WorkflowStep]`.
enum WorkflowStepTree {
    /// Conditionals may be nested this deep in the builder (the engine itself has no limit).
    static let maximumConditionalDepth = 3

    // MARK: Reading

    static func steps(at path: WorkflowStepListPath, in root: [WorkflowStep]) -> [WorkflowStep]? {
        var current: [WorkflowStep] = root
        for component in path.components {
            guard current.indices.contains(component.index),
                  case .conditional(_, let then, let otherwise) = current[component.index] else { return nil }
            current = component.branch == .then ? then : otherwise
        }
        return current
    }

    static func step(at path: WorkflowStepPath, in root: [WorkflowStep]) -> WorkflowStep? {
        guard let list = steps(at: path.list, in: root), list.indices.contains(path.index) else { return nil }
        return list[path.index]
    }

    // MARK: Writing

    /// Applies `body` to the list at `path`. Returns false (leaving `root` untouched) when the
    /// path does not resolve to a list.
    @discardableResult
    static func mutateSteps(at path: WorkflowStepListPath, in root: inout [WorkflowStep],
                            _ body: (inout [WorkflowStep]) -> Void) -> Bool {
        mutate(&root, components: path.components[...], body)
    }

    private static func mutate(_ list: inout [WorkflowStep], components: ArraySlice<WorkflowStepListPath.Component>,
                               _ body: (inout [WorkflowStep]) -> Void) -> Bool {
        guard let first = components.first else {
            body(&list)
            return true
        }
        guard list.indices.contains(first.index),
              case .conditional(let condition, var then, var otherwise) = list[first.index] else { return false }
        let rest: ArraySlice<WorkflowStepListPath.Component> = components.dropFirst()
        let succeeded: Bool
        switch first.branch {
        case .then: succeeded = mutate(&then, components: rest, body)
        case .otherwise: succeeded = mutate(&otherwise, components: rest, body)
        }
        if succeeded {
            list[first.index] = .conditional(condition, then: then, otherwise: otherwise)
        }
        return succeeded
    }

    @discardableResult
    static func replaceStep(at path: WorkflowStepPath, with step: WorkflowStep, in root: inout [WorkflowStep]) -> Bool {
        var replaced: Bool = false
        mutateSteps(at: path.list, in: &root) { list in
            if list.indices.contains(path.index) {
                list[path.index] = step
                replaced = true
            }
        }
        return replaced
    }

    /// Appends when `index` is nil or out of range. Returns the path of the inserted step.
    @discardableResult
    static func insertStep(_ step: WorkflowStep, in listPath: WorkflowStepListPath, at index: Int? = nil,
                           root: inout [WorkflowStep]) -> WorkflowStepPath? {
        var inserted: Int?
        mutateSteps(at: listPath, in: &root) { list in
            let target: Int
            if let index = index, index >= 0, index <= list.count { target = index } else { target = list.count }
            list.insert(step, at: target)
            inserted = target
        }
        return inserted.map { listPath.step($0) }
    }

    @discardableResult
    static func removeStep(at path: WorkflowStepPath, in root: inout [WorkflowStep]) -> WorkflowStep? {
        var removed: WorkflowStep?
        mutateSteps(at: path.list, in: &root) { list in
            if list.indices.contains(path.index) { removed = list.remove(at: path.index) }
        }
        return removed
    }

    /// Moves a step by `offset` positions inside its own list (-1 = up, +1 = down).
    /// Returns the new path, or nil when the move is not possible.
    @discardableResult
    static func moveStep(at path: WorkflowStepPath, by offset: Int, in root: inout [WorkflowStep]) -> WorkflowStepPath? {
        var destination: Int?
        mutateSteps(at: path.list, in: &root) { list in
            let target: Int = path.index + offset
            guard list.indices.contains(path.index), list.indices.contains(target), target != path.index else { return }
            let step: WorkflowStep = list.remove(at: path.index)
            list.insert(step, at: target)
            destination = target
        }
        return destination.map { path.list.step($0) }
    }

    static func canMoveStep(at path: WorkflowStepPath, by offset: Int, in root: [WorkflowStep]) -> Bool {
        guard let list = steps(at: path.list, in: root) else { return false }
        return list.indices.contains(path.index) && list.indices.contains(path.index + offset) && offset != 0
    }

    /// Total number of steps including nested ones.
    static func count(_ steps: [WorkflowStep]) -> Int {
        var total: Int = 0
        for step in steps {
            total += 1
            if case .conditional(_, let then, let otherwise) = step {
                total += count(then) + count(otherwise)
            }
        }
        return total
    }
}
