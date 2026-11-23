import Foundation
import MFCore

/// Taps, double taps, pending single taps and zone resolution.
extension GestureEngine {
    /// Every member of the episode has lifted.
    func finishEpisode(now: TimeInterval, out: inout [GestureEvent]) {
        let finished = episode
        episode = Episode()
        if finished.phase == .tracking { evaluateTap(finished, now: now, out: &out) }
        // Whatever the episode was, it is over: a tap still waiting on it is a single tap.
        flushClaimedPending(now: now, out: &out)
    }

    private func evaluateTap(_ finished: Episode, now: TimeInterval, out: inout [GestureEvent]) {
        let count = finished.peakCount
        guard let plainKind = KindMap.tap(count) else { return }
        let originX = finished.originX, originY = finished.originY
        let singleKind = resolveSingleTapKind(count: count, x: originX, y: originY)
        let thresholds = table[singleKind ?? plainKind]
        let duration = now - finished.startTime
        guard duration <= thresholds.tapMaxDuration,
              duration >= EngineConstants.minContactDuration,
              finished.maxDisplacementMM <= thresholds.tapMaxMovementMM,
              !clickSuppresses(from: finished.startTime, to: now) else { return }

        let confidence = Confidence.tap(movementMM: finished.maxDisplacementMM,
                                        maxMovementMM: thresholds.tapMaxMovementMM, duration: duration,
                                        maxDuration: thresholds.tapMaxDuration,
                                        landingSpread: finished.lastLandTime - finished.startTime,
                                        landingWindow: config.multiFingerLandingWindow)

        if let first = pending, first.claimed, finished.claimsPending, first.count == count,
           let doubleKind = KindMap.doubleTap(count), enabledKinds.contains(doubleKind) {
            let dx = (originX - first.originX) * table.widthMM, dy = (originY - first.originY) * table.heightMM
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= EngineConstants.doubleTapMaxDistanceMM {
                pending = nil
                let both = Confidence.doubleTap(first: first.confidence, second: confidence,
                                                gap: finished.startTime - first.liftTime,
                                                window: config.doubleTapWindow, distanceMM: distance,
                                                maxDistanceMM: EngineConstants.doubleTapMaxDistanceMM)
                emit(doubleKind, at: now, confidence: both, fingerCount: count, duration: now - first.startTime,
                     originX: first.originX, originY: first.originY, out: &out)
                return
            }
        }

        // Not a double tap: an older pending tap is released first, in order.
        flushPending(now: now, out: &out)
        if needsWait(count: count) {
            pending = PendingTap(count: count, startTime: finished.startTime, liftTime: now, originX: originX,
                                 originY: originY, kind: singleKind, confidence: confidence,
                                 deadline: now + config.doubleTapWindow)
        } else if let kind = singleKind {
            emit(kind, at: now, confidence: confidence, fingerCount: count, duration: duration,
                 originX: originX, originY: originY, out: &out)
        }
    }

    /// A single tap has to wait only when something enabled could still extend it.
    func needsWait(count: Int) -> Bool {
        if let doubleKind = KindMap.doubleTap(count), enabledKinds.contains(doubleKind) { return true }
        return count == 1 && anyTapThenSwipeEnabled
    }

    /// Most specific ENABLED single-tap kind for a tap at this position:
    /// corner zone → centre zone → plain tap. Exactly one kind per physical tap.
    func resolveSingleTapKind(count: Int, x: Double, y: Double) -> GestureKind? {
        if count == 1 {
            let corner = config.cornerZoneFraction
            let left = x <= corner, right = x >= 1 - corner
            let rear = y <= corner, front = y >= 1 - corner
            var cornerKind: GestureKind?
            if left && front { cornerKind = .cornerTapTopLeft }
            else if right && front { cornerKind = .cornerTapTopRight }
            else if left && rear { cornerKind = .cornerTapBottomLeft }
            else if right && rear { cornerKind = .cornerTapBottomRight }
            if let kind = cornerKind, enabledKinds.contains(kind) { return kind }
            let third = 1.0 / 3.0
            if x >= third && x <= 1 - third && y >= third && y <= 1 - third && enabledKinds.contains(.centerTap) {
                return .centerTap
            }
        }
        guard let plain = KindMap.tap(count), enabledKinds.contains(plain) else { return nil }
        return plain
    }

    func flushPending(now: TimeInterval, out: inout [GestureEvent]) {
        guard let tap = pending else { return }
        pending = nil
        episode.claimsPending = false
        guard let kind = tap.kind else { return }
        emit(kind, at: now, confidence: tap.confidence, fingerCount: tap.count, duration: now - tap.startTime,
             originX: tap.originX, originY: tap.originY, out: &out)
    }

    func flushClaimedPending(now: TimeInterval, out: inout [GestureEvent]) {
        if pending?.claimed == true { flushPending(now: now, out: &out) }
    }

    /// Unclaimed pending taps become single taps when the double-tap window closes.
    func expirePending(now: TimeInterval, out: inout [GestureEvent]) {
        if let tap = pending, !tap.claimed, now >= tap.deadline { flushPending(now: now, out: &out) }
    }

    /// Latest time at which the claiming episode could still turn the pending tap into a
    /// double tap or tap-then-swipe; −∞ when it no longer can.
    func claimedExpiry(_ tap: PendingTap) -> TimeInterval {
        var expiry = -Double.infinity
        guard episode.phase == .tracking, episode.claimsPending else { return expiry }
        if let doubleKind = KindMap.doubleTap(tap.count), enabledKinds.contains(doubleKind),
           let plain = KindMap.tap(tap.count), episode.peakCount <= tap.count {
            let thresholds = table[plain]
            if episode.maxDisplacementMM <= thresholds.tapMaxMovementMM {
                expiry = max(expiry, episode.startTime + thresholds.tapMaxDuration)
            }
        }
        if tap.count == 1 && anyTapThenSwipeEnabled && episode.peakCount == 1 && !episode.liftedAny {
            expiry = max(expiry, tap.liftTime + config.sequenceWindow)
        }
        return expiry
    }

    /// Releases the pending tap as a single tap as soon as the episode that claimed it can no
    /// longer complete a double tap or tap-then-swipe.
    func resolveClaimedPending(now: TimeInterval, out: inout [GestureEvent]) {
        guard let tap = pending, tap.claimed else { return }
        if now < claimedExpiry(tap) { return }
        flushPending(now: now, out: &out)
    }
}
