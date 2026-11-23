import ApplicationServices
import CoreGraphics
import Foundation
import MFCore
import MFUtilities

/// Global pointer / hot-key source built on one active `CGEventTap`.
///
/// - Tap: session level, inserted at the head, `.defaultTap` (active) because Smart Scroll rewrites
///   scroll deltas in place and chords / hot keys are swallowed. It observes left / right / other
///   mouse down + up, scroll wheel, key down and key up. An active tap needs the Accessibility
///   permission; `start` returns false without prompting when it is missing.
/// - Threading: the tap runs on its own thread with its own run loop. Handlers are invoked
///   synchronously on that thread and must return quickly (the system disables slow taps; the
///   tap re-enables itself when that happens).
/// - Events posted by MagicForge itself (tagged with `syntheticEventUserData` in
///   `eventSourceUserData`) pass through untouched and trigger no handler.
/// - Scroll origin: a scroll event does not identify its device. `ScrollSample.isFromMagicMouse`
///   is true only for continuous (pixel-precise) events whose gesture started while
///   `magicMouseActivityProbe` returned true; momentum events inherit the verdict of the gesture
///   they follow. Without a probe, `assumeContinuousScrollIsMagicMouse` decides (default false, so
///   trackpad scrolling is never modified by mistake).
/// - Chords: Control+Option (without Command / Shift) + left or right click, and Control+Option +
///   scroll (one `chordScroll*` per burst; a burst ends after 250 ms without scroll events).
/// - Hot keys: key code plus exact Command / Option / Control / Shift state; matching key downs
///   (and their key ups and auto-repeats) are swallowed.
public final class EventTapPointerSource: PointerEventSource, @unchecked Sendable {
    /// `eventSourceUserData` marker ("MFORGE") of events synthesized by MagicForge.
    public static let syntheticEventUserData: Int64 = 0x4D46_4F52_4745

    private static let log = Log("eventtap")

    private let configuration = Locked<EventTapConfiguration>(EventTapConfiguration())
    private let lifecycleLock = NSLock()
    private var session: EventTapSession?

    public init() {}

    deinit { stop() }

    /// Returns true when a finger was on a Magic Mouse very recently. Wire this to
    /// `MultitouchSupportAdapter.activity.isActive()`. Called on the tap thread.
    public var magicMouseActivityProbe: (() -> Bool)? {
        get { configuration.withLock { $0.magicMouseActivityProbe } }
        set { configuration.withLock { $0.magicMouseActivityProbe = newValue } }
    }

    /// Used only while `magicMouseActivityProbe` is nil: treat every continuous scroll event as
    /// coming from a Magic Mouse (appropriate on a Mac without any trackpad).
    public var assumeContinuousScrollIsMagicMouse: Bool {
        get { configuration.withLock { $0.assumeContinuousScrollIsMagicMouse } }
        set { configuration.withLock { $0.assumeContinuousScrollIsMagicMouse = newValue } }
    }

    // MARK: PointerEventSource

    public var isRunning: Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return session?.isEnabled ?? false
    }

    public func start(handlers: PointerEventHandlers) -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        configuration.withLock { $0.handlers = handlers }
        if let existing = session {
            if existing.isEnabled { return true }
            existing.stop()
            session = nil
        }
        guard AXIsProcessTrusted() else {
            EventTapPointerSource.log.notice("Event tap not started: Accessibility permission is not granted")
            return false
        }
        let created = EventTapSession(configuration: configuration)
        guard created.start() else { return false }
        session = created
        EventTapPointerSource.log.notice("Event tap started")
        return true
    }

    public func stop() {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard let existing = session else { return }
        existing.stop()
        session = nil
        configuration.withLock { $0.handlers = nil }
        EventTapPointerSource.log.notice("Event tap stopped")
    }

    public func setEnabledChords(_ kinds: Set<GestureKind>) {
        let chords: Set<GestureKind> = kinds.filter { $0.category == .fallback }
        configuration.withLock { $0.enabledChords = chords }
    }

    public func setScrollInterceptionEnabled(_ enabled: Bool) {
        configuration.withLock { $0.scrollInterceptionEnabled = enabled }
    }

    public func registerHotKeys(_ hotKeys: [UUID: KeyCombo]) {
        configuration.withLock { $0.hotKeys = hotKeys }
    }
}
