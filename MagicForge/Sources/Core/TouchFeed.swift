import Foundation
import MFUtilities

/// Lock-protected buffer between the input thread and the Touch Lab renderer. The renderer
/// polls `snapshot()` once per display frame, so 100 Hz touch input never invalidates SwiftUI state.
public final class TouchFeed: @unchecked Sendable {
    public struct TrailPoint: Sendable, Equatable {
        public var x: Double, y: Double, timestamp: TimeInterval
    }

    public struct Snapshot: Sendable {
        public var latest: TouchFrame?
        /// Recent positions per contact id (only for contacts still touching or lifted < `trailLifetime` ago).
        public var trails: [Int: [TrailPoint]] = [:]
        /// When each currently touching contact first appeared.
        public var contactStart: [Int: TimeInterval] = [:]
        public var live = RecognizerLiveState()
        public var lastGesture: GestureEvent?
        public var totalFrames: Int = 0
        /// Frames received during the last second.
        public var framesPerSecond: Double = 0
        /// Seconds between the newest frame's timestamp and its arrival in the feed.
        public var lastDeliveryLatency: TimeInterval = 0
        /// Seconds spent in the recognizer for the newest frame.
        public var lastProcessingTime: TimeInterval = 0
        public var isSynthetic: Bool = false
    }

    public var trailLifetime: TimeInterval = 0.8
    public var maxTrailPoints = 120

    private let state = Locked(Snapshot())
    private let paused = Locked(false)
    private let recentArrivals = Locked([TimeInterval]())

    public init() {}

    public var isPaused: Bool {
        get { paused.current }
        set { paused.withLock { $0 = newValue } }
    }

    /// Called from the input pipeline for every frame.
    public func push(_ frame: TouchFrame, live: RecognizerLiveState, processingTime: TimeInterval,
                     isSynthetic: Bool = false, now: TimeInterval = MonotonicClock.now()) {
        guard !isPaused else { return }
        let fps: Double = recentArrivals.withLock { arrivals in
            arrivals.append(now)
            arrivals.removeAll { now - $0 > 1 }
            return Double(arrivals.count)
        }
        state.withLock { snapshot in
            snapshot.latest = frame
            snapshot.live = live
            snapshot.totalFrames += 1
            snapshot.framesPerSecond = fps
            snapshot.lastDeliveryLatency = isSynthetic ? 0 : max(0, now - frame.timestamp)
            snapshot.lastProcessingTime = processingTime
            snapshot.isSynthetic = isSynthetic
            var touchingIDs = Set<Int>()
            for contact in frame.contacts where contact.isTouching {
                touchingIDs.insert(contact.id)
                if snapshot.contactStart[contact.id] == nil {
                    snapshot.contactStart[contact.id] = frame.timestamp
                    snapshot.trails[contact.id] = []
                }
                var trail = snapshot.trails[contact.id] ?? []
                trail.append(TrailPoint(x: contact.x, y: contact.y, timestamp: frame.timestamp))
                if trail.count > maxTrailPoints { trail.removeFirst(trail.count - maxTrailPoints) }
                snapshot.trails[contact.id] = trail
            }
            for id in Array(snapshot.contactStart.keys) where !touchingIDs.contains(id) {
                snapshot.contactStart[id] = nil
            }
            for (id, trail) in snapshot.trails where !touchingIDs.contains(id) {
                if let last = trail.last, frame.timestamp - last.timestamp > trailLifetime { snapshot.trails[id] = nil }
            }
        }
    }

    public func noteGesture(_ event: GestureEvent) {
        guard !isPaused else { return }
        state.withLock { $0.lastGesture = event }
    }

    public func snapshot() -> Snapshot { state.current }

    public func clear() {
        state.withLock { $0 = Snapshot() }
        recentArrivals.withLock { $0.removeAll() }
    }
}
