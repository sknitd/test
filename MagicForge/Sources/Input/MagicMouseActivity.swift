import Foundation
import MFUtilities

/// Remembers when a finger was last seen on a Magic Mouse surface.
///
/// The event tap cannot tell from a scroll event alone whether it came from a Magic Mouse or a
/// trackpad (both produce continuous, phased scroll events). `MultitouchSupportAdapter` updates
/// this object for every frame with a touching contact, and the app wires
/// `EventTapPointerSource.magicMouseActivityProbe` to `isActive()`, which makes the scroll origin
/// decision "a continuous scroll gesture that started while a finger was on the Magic Mouse".
///
/// Limits: with a Magic Mouse and a trackpad used at the very same moment the answer can be wrong,
/// and it is only available while the private multitouch adapter is streaming.
public final class MagicMouseActivity: @unchecked Sendable {
    public static let defaultWindow: TimeInterval = 0.35

    private let lastTouch = Locked<TimeInterval?>(nil)

    public init() {}

    /// Monotonic time of the most recent touching contact, if any since launch.
    public var lastTouchTime: TimeInterval? { lastTouch.current }

    public func noteTouch(at timestamp: TimeInterval = MonotonicClock.now()) {
        lastTouch.withLock { $0 = timestamp }
    }

    /// True when a finger was on a Magic Mouse within the last `window` seconds.
    public func isActive(within window: TimeInterval = MagicMouseActivity.defaultWindow,
                         now: TimeInterval = MonotonicClock.now()) -> Bool {
        guard let last = lastTouch.current else { return false }
        return now - last <= window
    }

    public func reset() {
        lastTouch.withLock { $0 = nil }
    }
}
