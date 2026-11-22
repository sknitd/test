import Foundation

/// Monotonic time source in seconds. All `TouchFrame.timestamp` values and recognizer deadlines
/// use this timebase (same as `ProcessInfo.systemUptime` / `CACurrentMediaTime`).
public enum MonotonicClock {
    public static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Minimal lock wrapper usable on every platform.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    public init(_ value: Value) { self.value = value }
    public func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(&value)
    }
    public var current: Value { withLock { $0 } }
}
