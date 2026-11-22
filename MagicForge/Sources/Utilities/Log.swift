import Foundation
#if canImport(os)
import os
#endif

/// Structured logging facade. Uses `os.Logger` on Apple platforms and stderr elsewhere.
/// Never log touch coordinates, clipboard contents, typed text or script bodies at default level.
public struct Log: Sendable {
    public enum Level: String, Sendable { case debug, info, notice, error }

    public let category: String
    #if canImport(os)
    private let logger: Logger
    #endif

    public static let subsystem = "com.magicforge.app"

    public init(_ category: String) {
        self.category = category
        #if canImport(os)
        self.logger = Logger(subsystem: Log.subsystem, category: category)
        #endif
    }

    public func debug(_ message: @autoclosure () -> String) { emit(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { emit(.info, message()) }
    public func notice(_ message: @autoclosure () -> String) { emit(.notice, message()) }
    public func error(_ message: @autoclosure () -> String) { emit(.error, message()) }

    private func emit(_ level: Level, _ message: String) {
        #if canImport(os)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        #else
        if level != .debug {
            FileHandle.standardError.write(Data("[\(level.rawValue)] \(category): \(message)\n".utf8))
        }
        #endif
    }
}
