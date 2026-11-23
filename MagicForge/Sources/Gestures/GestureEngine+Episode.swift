import Foundation
import MFCore

/// Per-frame evaluation of the episode in progress: holds, swipes, pinch and rotate.
extension GestureEngine {
    /// Snapshot of the episode members for one frame (all millimetres).
    private struct MemberGeometry {
        var count = 0
        var first = -1
        var second = -1
        var dx = 0.0
        var dy = 0.0
        var distance = 0.0
        var meanPath = 0.0
    }

    func evaluateEpisode(now: TimeInterval, out: inout [GestureEvent]) {
        guard episode.phase == .tracking || episode.phase == .held, episode.touching > 0 else { return }
        // Until the landing window closes the finger count is not known.
        guard now >= episode.startTime + config.multiFingerLandingWindow else { return }
        let fingers = episode.peakCount
        if fingers > EngineConstants.maxFingers { cancelEpisode("tooManyFingers"); return }
        // After a finger left, only the tap evaluation at the end remains.
        if episode.liftedAny { return }

        var geometry = MemberGeometry()
        var sumX = 0.0, sumY = 0.0, sumOriginX = 0.0, sumOriginY = 0.0, sumPath = 0.0
        for index in tracks.indices where tracks[index].isMember {
            let track = tracks[index]
            sumX += track.xMM; sumY += track.yMM
            sumOriginX += track.originXMM; sumOriginY += track.originYMM
            sumPath += track.pathMM
            if geometry.count == 0 { geometry.first = index } else if geometry.count == 1 { geometry.second = index }
            geometry.count += 1
        }
        guard geometry.count == fingers, fingers > 0 else { return }
        let inverse = 1 / Double(fingers)
        geometry.dx = (sumX - sumOriginX) * inverse
        geometry.dy = (sumY - sumOriginY) * inverse
        geometry.distance = (geometry.dx * geometry.dx + geometry.dy * geometry.dy).squareRoot()
        geometry.meanPath = sumPath * inverse

        var pinchDelta = 0.0, rotation = 0.0
        if fingers == 2 {
            let a = tracks[geometry.first], b = tracks[geometry.second]
            let originVX = b.originXMM - a.originXMM, originVY = b.originYMM - a.originYMM
            let currentVX = b.xMM - a.xMM, currentVY = b.yMM - a.yMM
            let originSeparation = (originVX * originVX + originVY * originVY).squareRoot()
            let currentSeparation = (currentVX * currentVX + currentVY * currentVY).squareRoot()
            pinchDelta = currentSeparation - originSeparation
            if originSeparation >= EngineConstants.minRotationSeparationMM
                && currentSeparation >= EngineConstants.minRotationSeparationMM {
                // Signed angle from the original finger-to-finger vector to the current one.
                // x grows right and y grows toward the front, so positive = counterclockwise
                // seen from above.
                let cross = originVX * currentVY - originVY * currentVX
                let dot = originVX * currentVX + originVY * currentVY
                rotation = atan2(cross, dot) * 180 / .pi
            }
        }

        if geometry.distance <= EngineConstants.motionSlopMM && abs(pinchDelta) <= EngineConstants.motionSlopMM
            && abs(rotation) <= EngineConstants.motionSlopDegrees {
            episode.moveStartTime = now
        }

        if episode.phase == .tracking && checkHold(now: now, out: &out) { return }
        if episode.phase == .held {
            // After a hold only a one-finger hold-then-swipe can follow.
            if fingers == 1 { checkSwipe(geometry, fingers: 1, now: now, out: &out) }
            return
        }
        if fingers == 2 {
            checkTwoFinger(geometry, pinchDelta: pinchDelta, rotation: rotation, now: now, out: &out)
        } else {
            checkSwipe(geometry, fingers: fingers, now: now, out: &out)
        }
    }

    // MARK: Hold

    /// Time at which `advance(to:)` would emit a hold, if one is still possible and enabled.
    func holdDeadline() -> TimeInterval? {
        guard episode.phase == .tracking, !episode.liftedAny, episode.touching > 0,
              let kind = KindMap.hold(episode.peakCount), enabledKinds.contains(kind) else { return nil }
        let thresholds = table[kind]
        guard episode.maxDisplacementMM <= thresholds.holdMaxMovementMM else { return nil }
        return episode.startTime + max(thresholds.holdMinDuration, config.multiFingerLandingWindow)
    }

    /// Moves the episode into `held` once every finger has stayed put long enough. The hold
    /// event fires exactly once; the episode may continue into hold-then-swipe.
    func checkHold(now: TimeInterval, out: inout [GestureEvent]) -> Bool {
        guard episode.phase == .tracking, !episode.liftedAny, episode.touching > 0,
              let kind = KindMap.hold(episode.peakCount) else { return false }
        let thresholds = table[kind]
        guard episode.maxDisplacementMM <= thresholds.holdMaxMovementMM,
              now >= episode.startTime + max(thresholds.holdMinDuration, config.multiFingerLandingWindow)
        else { return false }

        let confidence = Confidence.hold(movementMM: episode.maxDisplacementMM,
                                         maxMovementMM: thresholds.holdMaxMovementMM,
                                         landingSpread: episode.lastLandTime - episode.startTime,
                                         landingWindow: config.multiFingerLandingWindow)
        episode.phase = .held
        episode.holdTime = now
        episode.holdConfidence = confidence
        episode.moveStartTime = now
        for index in tracks.indices where tracks[index].isMember { tracks[index].reanchorOrigin() }
        flushClaimedPending(now: now, out: &out)
        // Pressing the button and keeping it down (a drag) is not a touch hold.
        if !clickSuppresses(from: episode.startTime, to: now) {
            let emitted = emit(kind, at: now, confidence: confidence, fingerCount: episode.peakCount,
                               duration: now - episode.startTime, originX: episode.originX,
                               originY: episode.originY, out: &out)
            if emitted { episode.firedKind = kind; episode.firedConfidence = confidence }
        }
        return true
    }

    // MARK: Swipes

    private enum SwipeContext { case plain, afterHold, afterTap }

    private func checkSwipe(_ geometry: MemberGeometry, fingers: Int, now: TimeInterval,
                            out: inout [GestureEvent]) {
        guard geometry.distance > 0 else { return }
        let stroke = StrokeDirection(dx: geometry.dx, dy: geometry.dy)
        var context = SwipeContext.plain
        var candidate = KindMap.swipe(fingers, stroke.direction)
        if fingers == 1 {
            if episode.phase == .held {
                context = .afterHold
                candidate = KindMap.holdThenSwipe(stroke.direction)
            } else if let tap = pending, tap.claimed, episode.claimsPending, tap.count == 1,
                      now < tap.liftTime + config.sequenceWindow,
                      enabledKinds.contains(KindMap.tapThenSwipe(stroke.direction)) {
                context = .afterTap
                candidate = KindMap.tapThenSwipe(stroke.direction)
            } else if let edge = edgeKind(for: tracks[geometry.first], stroke: stroke) {
                candidate = edge
            }
        }
        guard let kind = candidate else { return }
        let thresholds = table[kind]
        if liveCandidate == nil {
            liveCandidate = kind
            liveConfidence = min(geometry.distance / thresholds.swipeMinDistanceMM, 1) * 0.5
        }
        guard geometry.distance >= thresholds.swipeMinDistanceMM else { return }

        // The stroke reached swipe length: it either fires now or the episode is over.
        if stroke.deviationDegrees > thresholds.directionToleranceDegrees {
            cancelEpisode("ambiguousDirection"); return
        }
        let strokeTime = now - episode.moveStartTime
        guard strokeTime > 0 else { cancelEpisode("teleport"); return }
        let velocity = geometry.distance / strokeTime
        if velocity < thresholds.swipeMinVelocity { cancelEpisode("tooSlow"); return }

        var coherence = 1.0
        if fingers > 1 {
            let unitX = geometry.dx / geometry.distance, unitY = geometry.dy / geometry.distance
            for track in tracks where track.isMember {
                let along = (track.xMM - track.originXMM) * unitX + (track.yMM - track.originYMM) * unitY
                coherence = min(coherence, along / geometry.distance)
            }
            if coherence < EngineConstants.swipeCoherence { cancelEpisode("fingersDisagree"); return }
        }

        var confidence = Confidence.swipe(deviationDegrees: stroke.deviationDegrees,
                                          toleranceDegrees: thresholds.directionToleranceDegrees,
                                          velocity: velocity, minVelocity: thresholds.swipeMinVelocity,
                                          distanceMM: geometry.distance, pathMM: geometry.meanPath,
                                          coherence: coherence)
        var duration = now - episode.startTime
        var originX = episode.originX, originY = episode.originY
        switch context {
        case .afterHold:
            confidence = (confidence + episode.holdConfidence) / 2
        case .afterTap:
            if let tap = pending {
                confidence = (confidence + tap.confidence) / 2
                duration = now - tap.startTime
                originX = tap.originX; originY = tap.originY
            }
            pending = nil   // the tap is consumed by the compound gesture
            episode.claimsPending = false
        case .plain:
            flushClaimedPending(now: now, out: &out)
        }
        fire(kind, now: now, confidence: confidence, fingers: fingers, duration: duration, originX: originX,
             originY: originY, magnitude: geometry.distance, out: &out)
    }

    /// Edge swipes win over plain one-finger swipes when the whole stroke stayed inside the
    /// strip and runs along it, and the edge kind is enabled.
    private func edgeKind(for track: ContactTrack, stroke: StrokeDirection) -> GestureKind? {
        let edge = config.edgeZoneFraction
        if stroke.isVertical {
            if track.maxX <= edge && enabledKinds.contains(.leftEdgeSwipe) { return .leftEdgeSwipe }
            if track.minX >= 1 - edge && enabledKinds.contains(.rightEdgeSwipe) { return .rightEdgeSwipe }
        } else {
            if track.minY >= 1 - edge && enabledKinds.contains(.topEdgeSwipe) { return .topEdgeSwipe }
            if track.maxY <= edge && enabledKinds.contains(.bottomEdgeSwipe) { return .bottomEdgeSwipe }
        }
        return nil
    }

    // MARK: Two fingers: swipe vs pinch vs rotate

    /// Explicit three-way comparison. Each measure is normalised by its own threshold:
    /// centroid translation / swipe distance, |separation change| / pinch minimum,
    /// |angle change| / rotation minimum. Nothing happens until one reaches 1.0; the largest
    /// then wins if it beats the runner-up by `dominanceRatio`, otherwise the episode is
    /// cancelled as ambiguous. Exactly one of the three can fire per episode.
    private func checkTwoFinger(_ geometry: MemberGeometry, pinchDelta: Double, rotation: Double,
                                now: TimeInterval, out: inout [GestureEvent]) {
        let stroke = StrokeDirection(dx: geometry.dx, dy: geometry.dy)
        guard let swipeKind = KindMap.swipe(2, stroke.direction) else { return }
        let pinchKind: GestureKind = pinchDelta < 0 ? .pinchIn : .pinchOut
        let rotateKind: GestureKind = rotation > 0 ? .rotateCounterclockwise : .rotateClockwise
        let translationProgress = geometry.distance / table[swipeKind].swipeMinDistanceMM
        let pinchProgress = abs(pinchDelta) / table[pinchKind].pinchMinChangeMM
        let rotationProgress = abs(rotation) / table[rotateKind].rotationMinDegrees
        let top = max(translationProgress, pinchProgress, rotationProgress)

        if translationProgress >= top {
            liveCandidate = swipeKind
        } else if pinchProgress >= top {
            liveCandidate = pinchKind
        } else {
            liveCandidate = rotateKind
        }
        liveConfidence = min(top, 1) * 0.5
        guard top >= 1 else { return }

        if translationProgress >= top {
            let runnerUp = max(pinchProgress, rotationProgress)
            guard translationProgress >= runnerUp * EngineConstants.dominanceRatio else {
                cancelEpisode("ambiguousTwoFinger"); return
            }
            checkSwipe(geometry, fingers: 2, now: now, out: &out)
            return
        }

        let isPinch = pinchProgress >= top
        let runnerUp = isPinch ? max(translationProgress, rotationProgress)
                               : max(translationProgress, pinchProgress)
        guard top >= runnerUp * EngineConstants.dominanceRatio else {
            cancelEpisode("ambiguousTwoFinger"); return
        }
        let strokeTime = now - episode.moveStartTime
        guard strokeTime > 0 else { cancelEpisode("teleport"); return }
        guard strokeTime <= EngineConstants.maxPinchRotateStroke else { cancelEpisode("tooSlow"); return }
        // Both fingers must take part; one finger resting while the other scrolls is not a pinch.
        let a = tracks[geometry.first], b = tracks[geometry.second]
        let travelA = ((a.xMM - a.originXMM) * (a.xMM - a.originXMM)
            + (a.yMM - a.originYMM) * (a.yMM - a.originYMM)).squareRoot()
        let travelB = ((b.xMM - b.originXMM) * (b.xMM - b.originXMM)
            + (b.yMM - b.originYMM) * (b.yMM - b.originYMM)).squareRoot()
        guard min(travelA, travelB) >= max(travelA, travelB) * EngineConstants.minPartnerTravelShare else {
            cancelEpisode("oneFingerStatic"); return
        }

        let confidence = Confidence.twoFingerShape(winner: top, runnerUp: runnerUp, strokeTime: strokeTime,
                                                   maxStrokeTime: EngineConstants.maxPinchRotateStroke)
        flushClaimedPending(now: now, out: &out)
        fire(isPinch ? pinchKind : rotateKind, now: now, confidence: confidence, fingers: 2,
             duration: now - episode.startTime, originX: episode.originX, originY: episode.originY,
             magnitude: isPinch ? abs(pinchDelta) : abs(rotation), out: &out)
    }

    /// Marks the episode as done (one motion gesture per episode) and emits if allowed.
    private func fire(_ kind: GestureKind, now: TimeInterval, confidence: Double, fingers: Int,
                      duration: TimeInterval, originX: Double, originY: Double, magnitude: Double,
                      out: inout [GestureEvent]) {
        episode.phase = .fired
        let emitted = emit(kind, at: now, confidence: confidence, fingerCount: fingers, duration: duration,
                           originX: originX, originY: originY, magnitude: magnitude, out: &out)
        if emitted { episode.firedKind = kind; episode.firedConfidence = confidence }
    }
}
