import Foundation
import MFCore
import MFUtilities

/// Executes leaf actions (`system`, `window`, `app`, `keyboard`, `mouse`, `text`, `script`)
/// against macOS by dispatching to one small executor per action family.
///
/// - Missing permissions are reported as `ActionError.permissionDenied` and never prompt.
/// - Anything this Mac cannot do is reported as `ActionError.unsupported`, never faked.
/// - Non-leaf actions are the engine's job and throw `ActionError.unsupported("routed by the engine")`.
///
/// `@unchecked Sendable`: every stored member is immutable after `init`. The executors are
/// value types or internally locked classes, and `permissions` is only asked for
/// `status(of:)`, which implementations must answer from any thread without prompting
/// (`SystemPermissions` does).
public final class SystemActionPerformer: ActionPerforming, @unchecked Sendable {
    private let permissions: PermissionsProviding
    private let keyboard = KeyboardExecutor()
    private let system = SystemActionExecutor()
    private let window = WindowExecutor()
    private let apps = AppExecutor()
    private let mouse = MouseExecutor()
    private let text = TextExecutor()
    private let scripts: ScriptExecutor
    private let log = Log("actions")

    public init(permissions: PermissionsProviding) {
        self.permissions = permissions
        self.scripts = ScriptExecutor()
    }

    /// - Parameter scriptTimeout: seconds after which a script / shell / Shortcut action is stopped.
    public init(permissions: PermissionsProviding, scriptTimeout: TimeInterval) {
        self.permissions = permissions
        self.scripts = ScriptExecutor(timeout: scriptTimeout)
    }

    /// The permission an action needs before it can run, if any. Never prompts.
    public static func requiredPermission(for action: Action) -> PermissionKind? {
        switch action {
        case .keyboard, .mouse, .window:
            return .accessibility
        case .system(let systemAction):
            return SystemActionExecutor.postsEvents(systemAction) ? .accessibility : nil
        case .text(let textAction):
            return TextExecutor.requiresEventPosting(textAction) ? .accessibility : nil
        case .app, .script, .none, .workflow, .radialMenu, .ai, .control:
            // AppleScript may additionally need Automation consent for the apps it controls;
            // macOS asks for that itself, per target app, when the script first runs.
            return nil
        }
    }

    public func availability(of action: Action) -> ActionAvailability {
        switch action {
        case .system(let systemAction):
            if let reason = SystemActionExecutor.unavailableReason(for: systemAction) {
                return .unavailable(reason: reason)
            }
        case .script(let scriptAction):
            if let reason = ScriptExecutor.unavailableReason(for: scriptAction) {
                return .unavailable(reason: reason)
            }
        case .none, .workflow, .radialMenu, .ai, .control:
            // Routed by the engine; nothing on this Mac prevents them.
            return .available
        case .window, .app, .keyboard, .mouse, .text:
            break
        }
        if let kind = SystemActionPerformer.requiredPermission(for: action), permissions.status(of: kind) != .granted {
            return .needsPermission(kind)
        }
        return .available
    }

    public func perform(_ action: Action, context: ActionContext) async throws {
        guard action.isLeaf else {
            throw ActionError.unsupported("routed by the engine")
        }
        if Task.isCancelled { throw ActionError.cancelled }
        switch availability(of: action) {
        case .available: break
        case .needsPermission(let kind): throw ActionError.permissionDenied(kind)
        case .unavailable(let reason): throw ActionError.unsupported(reason)
        }

        do {
            switch action {
            case .system(let systemAction): try await system.perform(systemAction)
            case .window(let windowAction): try await window.perform(windowAction)
            case .app(let appAction): try await apps.perform(appAction)
            case .keyboard(let combo): try await keyboard.press(combo)
            case .mouse(let mouseAction): try await mouse.perform(mouseAction)
            case .text(let textAction): try await text.perform(textAction)
            case .script(let scriptAction): try await scripts.perform(scriptAction)
            case .none, .workflow, .radialMenu, .ai, .control:
                throw ActionError.unsupported("routed by the engine")
            }
        } catch let error as ActionError {
            throw error
        } catch is CancellationError {
            throw ActionError.cancelled
        } catch {
            log.error("Action failed with an unexpected error: \(error.localizedDescription)")
            throw ActionError.failed(error.localizedDescription)
        }
    }

    /// Releases a held drag lock, if any (call when gestures are paused or the app quits).
    public func releaseHeldInput() {
        mouse.releaseDrag()
    }
}
