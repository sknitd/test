import Foundation
import MFCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Result of a finished child process.
struct ProcessOutput: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

/// Runs a child process without blocking the caller's thread.
///
/// Guarantees:
/// - stdin is `/dev/null` unless `input` is given (then it is written and closed);
/// - stdout / stderr are captured up to `outputLimit` bytes each, the rest is discarded;
/// - after `timeout` seconds the process gets SIGTERM, and SIGKILL two seconds later
///   (`ActionError.timedOut`); the same happens when the calling task is cancelled
///   (`ActionError.cancelled`);
/// - when the child is the leader of its own process group (checked at run time) the signals go
///   to the whole group, so children it spawned are stopped too; otherwise only the child itself
///   can be signalled.
enum ProcessRunner {
    static func run(executable: URL, arguments: [String], input: Data? = nil, environment: [String: String],
                    currentDirectory: URL? = nil, timeout: TimeInterval,
                    outputLimit: Int = 64 * 1024) async throws -> ProcessOutput {
        let run = ProcessRun(executable: executable, arguments: arguments, input: input, environment: environment,
                             currentDirectory: currentDirectory, timeout: timeout, outputLimit: outputLimit)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                run.start(continuation)
            }
        } onCancel: {
            run.stop(.cancelled)
        }
    }

    /// Small, predictable environment for user scripts (no inherited secrets from the app's environment).
    static func minimalEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "LANG": inherited["LANG"] ?? "en_US.UTF-8",
        ]
        if let temporary = inherited["TMPDIR"] { environment["TMPDIR"] = temporary }
        return environment
    }
}

/// One execution. All mutable state is guarded by `lock`.
private final class ProcessRun: @unchecked Sendable {
    enum StopReason { case timedOut, cancelled }

    private let process = Process()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let inputPipe: Pipe?
    private let input: Data?
    private let timeout: TimeInterval
    private let outputLimit: Int
    private let queue = DispatchQueue(label: "com.magicforge.process-runner")

    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var stopReason: StopReason?
    private var isStarted = false
    private var isFinished = false
    private var pid: pid_t = 0
    private var isGroupLeader = false
    private var outputData = Data()
    private var errorData = Data()
    private var outputTruncated = false
    private var errorTruncated = false

    init(executable: URL, arguments: [String], input: Data?, environment: [String: String], currentDirectory: URL?,
         timeout: TimeInterval, outputLimit: Int) {
        self.input = input
        self.inputPipe = input == nil ? nil : Pipe()
        self.timeout = timeout
        self.outputLimit = max(0, outputLimit)
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if let inputPipe {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
    }

    func start(_ continuation: CheckedContinuation<ProcessOutput, Error>) {
        lock.lock()
        if stopReason != nil {
            // Cancelled before launch: never start the process.
            isFinished = true
            lock.unlock()
            continuation.resume(throwing: ActionError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle, isError: false)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle, isError: true)
        }
        process.terminationHandler = { [weak self] _ in
            self?.processDidExit()
        }

        do {
            try process.run()
        } catch {
            detachHandlers()
            finish(with: .failure(ActionError.failed("Could not start \(process.executableURL?.lastPathComponent ?? "process"): \(error.localizedDescription)")))
            return
        }

        let childPID: pid_t = process.processIdentifier
        lock.lock()
        pid = childPID
        isGroupLeader = childPID > 0 && getpgid(childPID) == childPID
        isStarted = true
        let pendingStop: StopReason? = stopReason
        lock.unlock()

        if pendingStop != nil {
            // Cancellation raced with the launch.
            terminateThenKill()
        }
        writeInput()
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.stop(.timedOut)
        }
    }

    func stop(_ reason: StopReason) {
        lock.lock()
        if isFinished || stopReason != nil {
            lock.unlock()
            return
        }
        stopReason = reason
        let started = isStarted
        lock.unlock()
        if started { terminateThenKill() }
    }

    // MARK: Private

    private func terminateThenKill() {
        send(SIGTERM)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let finished = self.isFinished
            self.lock.unlock()
            if !finished { self.send(SIGKILL) }
        }
    }

    private func send(_ signal: Int32) {
        lock.lock()
        let target: pid_t = pid
        let group: Bool = isGroupLeader
        lock.unlock()
        guard target > 0 else { return }
        if group {
            _ = kill(-target, signal)
        } else if process.isRunning {
            _ = kill(target, signal)
        }
    }

    private func writeInput() {
        guard let inputPipe, let input else { return }
        let handle: FileHandle = inputPipe.fileHandleForWriting
        #if canImport(Darwin)
        // A child that exits without reading must not kill MagicForge with SIGPIPE.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        #endif
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handle.write(contentsOf: input)
            } catch {
                // The child closed its stdin early; its exit status tells the story.
            }
            try? handle.close()
        }
    }

    private func consume(_ handle: FileHandle, isError: Bool) {
        let chunk: Data = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil   // end of file
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if isError {
            ProcessRun.append(chunk, to: &errorData, truncated: &errorTruncated, limit: outputLimit)
        } else {
            ProcessRun.append(chunk, to: &outputData, truncated: &outputTruncated, limit: outputLimit)
        }
    }

    private static func append(_ chunk: Data, to buffer: inout Data, truncated: inout Bool, limit: Int) {
        let room: Int = limit - buffer.count
        if room <= 0 {
            truncated = true
            return
        }
        if chunk.count > room {
            buffer.append(chunk.prefix(room))
            truncated = true
        } else {
            buffer.append(chunk)
        }
    }

    private func processDidExit() {
        // Give the pipe handlers a moment to deliver the last bytes. Do not wait for end-of-file:
        // a background grandchild may keep the pipe open indefinitely.
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.completeAfterExit()
        }
    }

    private func completeAfterExit() {
        detachHandlers()
        lock.lock()
        let reason: StopReason? = stopReason
        let group: Bool = isGroupLeader
        let target: pid_t = pid
        let output = ProcessOutput(exitCode: process.terminationStatus,
                                   standardOutput: ProcessRun.text(outputData, truncated: outputTruncated),
                                   standardError: ProcessRun.text(errorData, truncated: errorTruncated))
        lock.unlock()

        if let reason {
            // Make sure nothing from a stopped run stays behind.
            if group && target > 0 { _ = kill(-target, SIGKILL) }
            switch reason {
            case .timedOut: finish(with: .failure(ActionError.timedOut))
            case .cancelled: finish(with: .failure(ActionError.cancelled))
            }
        } else {
            finish(with: .success(output))
        }
    }

    private func detachHandlers() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func finish(with result: Result<ProcessOutput, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        isFinished = true
        lock.unlock()
        pending?.resume(with: result)
    }

    private static func text(_ data: Data, truncated: Bool) -> String {
        let string = String(decoding: data, as: UTF8.self)
        return truncated ? string + "\n… (output truncated)" : string
    }
}
