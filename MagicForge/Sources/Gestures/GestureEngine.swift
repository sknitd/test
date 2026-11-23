import Foundation
import MFCore

/// Deterministic gesture recognizer for Magic Mouse touch frames.
///
/// Time only ever comes from `TouchFrame.timestamp` and `advance(to:)`; the engine owns no
/// timers, threads or clocks. Not thread-safe: call from one serial context.
/// The state machine, thresholds and conflict rules are described in docs/GESTURES.md.
public final class GestureEngine: GestureRecognizing {
    public var config: RecognizerConfig {
        didSet { table = ThresholdTable(config: config, calibration: calibration) }
    }
    public var calibration: DeviceCalibration {
        didSet { table = ThresholdTable(config: config, calibration: calibration) }
    }
    /// Defaults to every raw-contact kind. Also drives conflict resolution (see docs/GESTURES.md).
    public var enabledKinds: Set<GestureKind> {
        didSet { refreshEnabledFlags() }
    }
    public internal(set) var liveState = RecognizerLiveState()

    var table: ThresholdTable
    var tracks: [ContactTrack] = []
    var episode = Episode()
    var pending: PendingTap?
    var lastEmission: [GestureKind: TimeInterval] = [:]
    var lastClickTime: TimeInterval?
    var hasFrame = false
    var lastFrameTime: TimeInterval = 0
    var lastDeviceID: UInt64 = 0
    var anyTapThenSwipeEnabled = false
    /// Best in-progress guess, refreshed every frame for `liveState`.
    var liveCandidate: GestureKind?
    var liveConfidence: Double = 0

    public init(config: RecognizerConfig = .init(), calibration: DeviceCalibration = .init()) {
        self.config = config
        self.calibration = calibration
        self.table = ThresholdTable(config: config, calibration: calibration)
        self.enabledKinds = Set(GestureKind.allCases.filter { $0.requirement == .rawContacts })
        tracks.reserveCapacity(16)
        refreshEnabledFlags()
    }

    // MARK: GestureRecognizing

    public func process(_ frame: TouchFrame) -> [GestureEvent] {
        var out: [GestureEvent] = []
        let now = frame.timestamp
        var afterGap = false
        if hasFrame {
            if now < lastFrameTime || frame.deviceID != lastDeviceID {
                // Different timebase or device: nothing we remember is comparable any more.
                clearState()
            } else if !tracks.isEmpty && now - lastFrameTime > EngineConstants.maxFrameGap {
                interrupt(now: now, out: &out)
                afterGap = true
            }
        }
        hasFrame = true
        lastFrameTime = now
        lastDeviceID = frame.deviceID

        expirePending(now: now, out: &out)
        updateContacts(frame, now: now, afterGap: afterGap, out: &out)
        liveCandidate = nil
        liveConfidence = 0
        evaluateEpisode(now: now, out: &out)
        resolveClaimedPending(now: now, out: &out)
        refreshLiveState(now: now)
        return out
    }

    public func advance(to now: TimeInterval) -> [GestureEvent] {
        var out: [GestureEvent] = []
        if hasFrame && !tracks.isEmpty && now - lastFrameTime > EngineConstants.maxFrameGap {
            // The stream stopped while fingers were down: do not guess, cancel.
            interrupt(now: now, out: &out)
        }
        expirePending(now: now, out: &out)
        _ = checkHold(now: now, out: &out)
        resolveClaimedPending(now: now, out: &out)
        refreshLiveState(now: now)
        return out
    }

    public var nextDeadline: TimeInterval? {
        var best: TimeInterval?
        if let tap = pending, tap.kind != nil {
            if tap.claimed {
                let expiry = claimedExpiry(tap)
                best = expiry.isFinite ? expiry : lastFrameTime
            } else {
                best = tap.deadline
            }
        }
        if let hold = holdDeadline() {
            best = best.map { min($0, hold) } ?? hold
        }
        return best
    }

    public func notePhysicalClick(at timestamp: TimeInterval) {
        lastClickTime = timestamp
        // A tap that is still waiting for a possible double tap is retracted by the click.
        if let tap = pending, tap.liftTime >= timestamp - config.physicalClickSuppression {
            pending = nil
            episode.claimsPending = false
        }
    }

    public func reset() {
        clearState()
        hasFrame = false
        lastFrameTime = 0
        lastDeviceID = 0
        refreshLiveState(now: 0)
    }

    // MARK: Shared helpers

    func clearState() {
        tracks.removeAll(keepingCapacity: true)
        episode = Episode()
        pending = nil
        lastEmission.removeAll(keepingCapacity: true)
        lastClickTime = nil
        liveCandidate = nil
        liveConfidence = 0
    }

    func refreshEnabledFlags() {
        anyTapThenSwipeEnabled = KindMap.tapThenSwipeKinds.contains { enabledKinds.contains($0) }
    }

    /// Contact interruption: the episode in progress is dropped without emitting, and contacts
    /// that are still down are quarantined until they lift. A tap that was already complete
    /// (pending) is still a real tap and is released as a single tap.
    func interrupt(now: TimeInterval, out: inout [GestureEvent]) {
        episode = Episode()
        for index in tracks.indices {
            tracks[index].isMember = false
            if tracks[index].role == .candidate { tracks[index].role = .quarantined }
        }
        flushClaimedPending(now: now, out: &out)
    }

    /// True when a physical click falls inside (or within the suppression margin of) the span.
    func clickSuppresses(from start: TimeInterval, to end: TimeInterval) -> Bool {
        guard let click = lastClickTime else { return false }
        let margin = config.physicalClickSuppression
        return click >= start - margin && click <= end + margin
    }

    /// The single gate every event passes: enabled kinds, minimum confidence, per-kind cooldown.
    @discardableResult
    func emit(_ kind: GestureKind, at now: TimeInterval, confidence: Double, fingerCount: Int,
              duration: TimeInterval, originX: Double, originY: Double, magnitude: Double = 0,
              out: inout [GestureEvent]) -> Bool {
        guard enabledKinds.contains(kind), confidence >= config.minimumConfidence else { return false }
        if let last = lastEmission[kind], now >= last, now - last < config.cooldown { return false }
        lastEmission[kind] = now
        out.append(GestureEvent(kind: kind, timestamp: now, confidence: min(max(confidence, 0), 1),
                                fingerCount: fingerCount, duration: max(duration, 0), originX: originX,
                                originY: originY, magnitude: magnitude))
        return true
    }
}
