import Foundation
import MFCore

/// Plain-text descriptions of actions, errors and availability. No UI types in this file.
enum ActionText {
    /// First non-empty line of `text`, truncated to `limit` characters.
    static func firstLine(_ text: String, limit: Int = 44) -> String {
        let lines: [Substring] = text.split(whereSeparator: { $0.isNewline })
        var candidate: String = ""
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                candidate = trimmed
                break
            }
        }
        if candidate.count > limit {
            return String(candidate.prefix(limit)) + "…"
        }
        return candidate
    }

    /// Name of the action with app names resolved ("Launch Safari" rather than the bundle identifier).
    static func title(for action: Action, appName: (String) -> String = { $0 }) -> String {
        if case .app(let app) = action {
            switch app {
            case .launch(let bundleID):
                return bundleID.isEmpty ? "Launch App" : "Launch \(appName(bundleID))"
            case .switchTo(let bundleID):
                return bundleID.isEmpty ? "Switch to App" : "Switch to \(appName(bundleID))"
            default:
                break
            }
        }
        return action.displayName
    }

    /// Short description of parameters that `title(for:)` does not already contain (workflow name,
    /// first script line, fixed text, scroll amount), or nil.
    static func parameterSummary(for action: Action, in configuration: Configuration) -> String? {
        switch action {
        case .none, .system, .control, .window, .app, .keyboard:
            return nil
        case .mouse(let mouse):
            if case .scroll(let dx, let dy) = mouse {
                return "→ \(numberString(dx))  ↑ \(numberString(dy))"
            }
            return nil
        case .text(let text):
            switch text {
            case .copy, .paste: return nil
            case .copyText(let value), .pasteText(let value): return nonEmpty(firstLine(value))
            }
        case .script(let script):
            switch script {
            case .appleScript(let source): return nonEmpty(firstLine(source))
            case .shell(let command): return nonEmpty(firstLine(command))
            case .shortcut: return nil
            }
        case .workflow(let id):
            return configuration.workflows.first(where: { $0.id == id })?.name ?? "Missing workflow"
        case .radialMenu(let id):
            return configuration.radialMenus.first(where: { $0.id == id })?.name ?? "Missing menu"
        case .ai(let templateID):
            return configuration.ai.templates.first(where: { $0.id == templateID })?.name ?? "Missing template"
        }
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    static func percentString(_ fraction: Double) -> String {
        let percent: Int = Int((fraction * 100).rounded())
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    static func numberString(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    static func describe(_ error: ActionError) -> String {
        switch error {
        case .permissionDenied(let kind):
            return "\(kind.displayName) permission is required. Grant it in the Permissions section."
        case .unsupported(let reason):
            return "Not supported: \(reason)"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .timedOut:
            return "Timed out."
        case .cancelled:
            return "Cancelled."
        case .untrusted:
            return "This script has not been approved on this Mac. Approve it before running."
        case .notFound(let what):
            return "Not found: \(what)"
        }
    }

    /// Nil when the action is available.
    static func describe(_ availability: ActionAvailability) -> String? {
        switch availability {
        case .available:
            return nil
        case .needsPermission(let kind):
            return "Needs \(kind.displayName) permission"
        case .unavailable(let reason):
            return reason
        }
    }

    /// True for strings that can be opened as a URL: a scheme followed by something.
    static func isValidURL(_ text: String) -> Bool {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), let components = URLComponents(string: trimmed),
              let scheme = components.scheme, !scheme.isEmpty else { return false }
        let rest: String = String(trimmed.dropFirst(scheme.count + 1))
        if rest.isEmpty || rest == "//" { return false }
        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { return false }
        }
        return true
    }
}

/// Default action for each category, used when the user switches category in the editor.
enum ActionDefaults {
    /// Nil when the category needs something that does not exist yet (a recorded shortcut, a
    /// workflow, a radial menu or a prompt template).
    static func action(for category: ActionCategory, in configuration: Configuration) -> Action? {
        switch category {
        case .system: return .system(.missionControl)
        case .window: return .window(.snapLeft)
        case .app: return .app(.launch(bundleID: ""))
        case .mouse: return .mouse(.middleClick)
        case .text: return .text(.paste)
        case .script: return .script(.shortcut(name: ""))
        case .workflow: return configuration.workflows.first.map { Action.workflow(id: $0.id) }
        case .radialMenu: return configuration.radialMenus.first.map { Action.radialMenu(id: $0.id) }
        case .ai: return configuration.ai.templates.first.map { Action.ai(templateID: $0.id) }
        case .control: return .control(.toggleGesturesPaused)
        default: return nil
        }
    }
}
