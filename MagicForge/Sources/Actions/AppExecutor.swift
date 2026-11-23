import AppKit
import Foundation
import MFCore

/// Launches, switches to, hides and quits applications; opens URLs and files. No permission needed.
struct AppExecutor: Sendable {
    func perform(_ action: AppAction) async throws {
        switch action {
        case .launch(let bundleID):
            try await AppExecutor.openApplication(at: try AppExecutor.applicationURL(for: bundleID))
        case .switchTo(let bundleID):
            try await switchTo(bundleID)
        case .hideFrontmost:
            let app = try AppExecutor.frontmostOtherApplication(verb: "hide")
            if !app.hide() { throw ActionError.failed("\(app.localizedName ?? "The app") could not be hidden.") }
        case .quitFrontmost:
            let app = try AppExecutor.frontmostOtherApplication(verb: "quit")
            if !app.terminate() { throw ActionError.failed("\(app.localizedName ?? "The app") refused to quit.") }
        case .openURL(let string):
            try openURL(string)
        case .openPath(let path):
            try openPath(path)
        }
    }

    static func applicationURL(for bundleID: String) throws -> URL {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActionError.notFound("No application with bundle identifier \(bundleID) is installed.")
        }
        return url
    }

    /// Opens (or activates, when already running) the application and waits for the system to confirm.
    static func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: ActionError.failed(
                        "Could not open \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func switchTo(_ bundleID: String) async throws {
        let running: [NSRunningApplication] = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            if app.isHidden { _ = app.unhide() }
            if app.activate(options: [.activateAllWindows]) { return }
        }
        // Not running, or activation was refused: let Launch Services bring it forward.
        try await AppExecutor.openApplication(at: try AppExecutor.applicationURL(for: bundleID))
    }

    /// The frontmost application, refusing to act on MagicForge itself.
    private static func frontmostOtherApplication(verb: String) throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ActionError.failed("There is no frontmost application.")
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ActionError.failed("MagicForge will not \(verb) itself.")
        }
        return app
    }

    private func openURL(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else {
            throw ActionError.failed("Not a valid URL (it must include a scheme such as https://).")
        }
        if !NSWorkspace.shared.open(url) {
            throw ActionError.failed("No application could open this URL.")
        }
    }

    private func openPath(_ path: String) throws {
        let expanded: String = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty, FileManager.default.fileExists(atPath: expanded) else {
            throw ActionError.notFound("Nothing exists at this path.")
        }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: expanded)) {
            throw ActionError.failed("The file or folder could not be opened.")
        }
    }
}
