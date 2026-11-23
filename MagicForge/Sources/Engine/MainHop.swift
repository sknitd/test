import Foundation

/// Hops onto the main actor from callbacks whose thread is only documented ("called on the
/// main queue") or unknown (pipeline queue, event-tap thread).
enum MainHop {
    /// Runs `body` right away when already on the main thread, otherwise enqueues it.
    static func run(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            enqueue(body)
        }
    }

    /// Always enqueues on the main queue, so calls made from one thread arrive in order.
    static func enqueue(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }
}
