import Foundation
import MFCore
import MFUtilities

/// Runs user-authored code: AppleScript, shell commands and Shortcuts.
///
/// SECURITY: this executes arbitrary code with the user's privileges. The engine verifies that
/// the script's hash is in `Configuration.approvedScriptHashes` *before* calling the performer;
/// this type performs no trust check of its own. Script bodies are never logged.
struct ScriptExecutor: Sendable {
    static let defaultTimeout: TimeInterval = 20

    static let osascriptPath = "/usr/bin/osascript"
    static let shortcutsPath = "/usr/bin/shortcuts"
    private static let shellCandidates = ["/bin/zsh", "/bin/sh"]

    let timeout: TimeInterval
    private let log = Log("actions.script")

    init(timeout: TimeInterval = ScriptExecutor.defaultTimeout) {
        self.timeout = timeout > 0 ? timeout : ScriptExecutor.defaultTimeout
    }

    static func unavailableReason(for action: ScriptAction) -> String? {
        let fileManager = FileManager.default
        switch action {
        case .appleScript:
            return fileManager.isExecutableFile(atPath: osascriptPath) ? nil : "osascript is missing on this Mac."
        case .shell:
            return shellPath() == nil ? "No shell was found on this Mac." : nil
        case .shortcut:
            return fileManager.isExecutableFile(atPath: shortcutsPath)
                ? nil : "The Shortcuts command-line tool is missing on this Mac."
        }
    }

    private static func shellPath() -> String? {
        shellCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func perform(_ action: ScriptAction) async throws {
        if let reason = ScriptExecutor.unavailableReason(for: action) {
            throw ActionError.unsupported(reason)
        }
        let environment: [String: String] = ProcessRunner.minimalEnvironment()
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let output: ProcessOutput
        let kind: String

        switch action {
        case .appleScript(let source):
            // With no script file and no -e option, osascript reads the script from standard
            // input. NSAppleScript is not used because it must run on (and would block) the
            // main thread and cannot be timed out.
            kind = "AppleScript"
            output = try await ProcessRunner.run(executable: URL(fileURLWithPath: ScriptExecutor.osascriptPath),
                                                 arguments: [], input: Data(source.utf8), environment: environment,
                                                 currentDirectory: home, timeout: timeout)
        case .shell(let command):
            guard let shell = ScriptExecutor.shellPath() else {
                throw ActionError.unsupported("No shell was found on this Mac.")
            }
            kind = "Shell command"
            var shellEnvironment = environment
            shellEnvironment["SHELL"] = shell
            output = try await ProcessRunner.run(executable: URL(fileURLWithPath: shell), arguments: ["-c", command],
                                                 environment: shellEnvironment, currentDirectory: home,
                                                 timeout: timeout)
        case .shortcut(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ActionError.failed("The shortcut has no name.") }
            kind = "Shortcut"
            output = try await ProcessRunner.run(executable: URL(fileURLWithPath: ScriptExecutor.shortcutsPath),
                                                 arguments: ["run", trimmed], environment: environment,
                                                 currentDirectory: home, timeout: timeout)
        }

        guard output.exitCode == 0 else {
            log.info("\(kind) exited with status \(output.exitCode)")
            throw ScriptExecutor.error(kind: kind, output: output)
        }
    }

    private static func error(kind: String, output: ProcessOutput) -> ActionError {
        let detail: String = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        // errAEEventNotPermitted: the user has not allowed MagicForge to control the target app.
        if kind == "AppleScript", detail.contains("-1743") {
            return .permissionDenied(.automation)
        }
        let limit = 400
        let shortened: String = detail.count > limit ? String(detail.prefix(limit)) + "…" : detail
        if shortened.isEmpty {
            return .failed("\(kind) failed with exit status \(output.exitCode).")
        }
        return .failed("\(kind) failed (exit status \(output.exitCode)): \(shortened)")
    }
}
