import Foundation
import MFCore

/// Trust decisions for actions that run user-authored code.
///
/// A script may only run when the SHA-256 of its `trustPayload` is in
/// `Configuration.approvedScriptHashes`. Approval is tied to the exact text: changing a single
/// character of a script makes it untrusted again.
public enum ScriptTrust {
    /// Lowercase hex SHA-256 of `data`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256Pure.hex(Digest.sha256(data))
    }

    /// Lowercase hex SHA-256 of the script's `trustPayload` (UTF-8).
    public static func hash(of script: ScriptAction) -> String {
        sha256Hex(Data(script.trustPayload.utf8))
    }

    public static func isTrusted(_ script: ScriptAction, in configuration: Configuration) -> Bool {
        configuration.approvedScriptHashes.contains(hash(of: script))
    }

    public static func approve(_ script: ScriptAction, in configuration: inout Configuration) {
        configuration.approvedScriptHashes.insert(hash(of: script))
    }

    public static func revoke(_ script: ScriptAction, in configuration: inout Configuration) {
        configuration.approvedScriptHashes.remove(hash(of: script))
    }

    // MARK: Collecting scripts (each distinct script once, in order of first appearance)

    /// Every script anywhere in the configuration: profile bindings, workflow steps (including
    /// conditional branches) and radial menus (including submenus).
    public static func scripts(in configuration: Configuration) -> [ScriptAction] {
        var actions: [Action] = []
        for profile in configuration.profiles { actions += ActionTraversal.actions(in: profile) }
        for workflow in configuration.workflows { actions += ActionTraversal.actions(in: workflow.steps) }
        for menu in configuration.radialMenus { actions += ActionTraversal.actions(in: menu.items) }
        return unique(actions.compactMap(\.script))
    }

    /// Scripts bound directly in the profile. Use `scripts(in:resolvingReferencesIn:)` to also
    /// see scripts inside the workflows and radial menus its bindings open.
    public static func scripts(in profile: Profile) -> [ScriptAction] {
        unique(ActionTraversal.actions(in: profile).compactMap(\.script))
    }

    public static func scripts(in workflow: Workflow) -> [ScriptAction] { scripts(in: workflow.steps) }

    public static func scripts(in steps: [WorkflowStep]) -> [ScriptAction] {
        unique(ActionTraversal.actions(in: steps).compactMap(\.script))
    }

    public static func scripts(in menu: RadialMenu) -> [ScriptAction] {
        unique(ActionTraversal.actions(in: menu.items).compactMap(\.script))
    }

    /// Scripts the profile can run, directly or through `.workflow(id:)` / `.radialMenu(id:)`
    /// references resolved in `configuration`.
    public static func scripts(in profile: Profile, resolvingReferencesIn configuration: Configuration) -> [ScriptAction] {
        scripts(reachableFrom: ActionTraversal.actions(in: profile), in: configuration)
    }

    /// Scripts `action` can run: itself when it is a script, plus everything reachable through
    /// workflow and radial-menu references (reference cycles are tolerated).
    public static func scripts(reachableFrom action: Action, in configuration: Configuration) -> [ScriptAction] {
        scripts(reachableFrom: [action], in: configuration)
    }

    /// Scripts anywhere in the configuration that are not approved.
    public static func untrustedScripts(in configuration: Configuration) -> [ScriptAction] {
        scripts(in: configuration).filter { !isTrusted($0, in: configuration) }
    }

    /// Scripts the action could run that are not approved; empty means it is safe to execute.
    public static func untrustedScripts(reachableFrom action: Action, in configuration: Configuration) -> [ScriptAction] {
        scripts(reachableFrom: action, in: configuration).filter { !isTrusted($0, in: configuration) }
    }

    // MARK: Internals

    static func scripts(reachableFrom actions: [Action], in configuration: Configuration) -> [ScriptAction] {
        var found = actions.compactMap(\.script)
        let references = ReferenceSet.reachable(from: actions, in: configuration)
        for workflow in configuration.workflows where references.workflows.contains(workflow.id) {
            found += ActionTraversal.actions(in: workflow.steps).compactMap(\.script)
        }
        for menu in configuration.radialMenus where references.radialMenus.contains(menu.id) {
            found += ActionTraversal.actions(in: menu.items).compactMap(\.script)
        }
        return unique(found)
    }

    static func unique(_ scripts: [ScriptAction]) -> [ScriptAction] {
        var seen = Set<ScriptAction>()
        return scripts.filter { seen.insert($0).inserted }
    }
}
