import Foundation
import MFCore

/// Keeps `liveState` current for the Touch Lab overlay.
extension GestureEngine {
    func refreshLiveState(now: TimeInterval) {
        var state = RecognizerLiveState()
        for track in tracks {
            if track.isMember { state.activeFingerCount += 1 }
            if track.role == .resting { state.restingFingerCount += 1 }
        }
        switch episode.phase {
        case .idle:
            if let tap = pending {
                state.phase = "awaitingSecondTap"
                state.candidate = tap.kind ?? KindMap.doubleTap(tap.count)
                state.candidateConfidence = tap.confidence
            } else {
                state.phase = "idle"
            }
        case .tracking:
            let landing = now < episode.startTime + config.multiFingerLandingWindow
            state.phase = landing ? "landing" : "tracking"
            if let candidate = liveCandidate, liveConfidence > 0.08 {
                state.candidate = candidate
                state.candidateConfidence = liveConfidence
            } else {
                fillStationaryCandidate(&state, now: now)
            }
        case .held:
            state.phase = "held"
            if let candidate = liveCandidate, liveConfidence > 0.08 {
                state.candidate = candidate
                state.candidateConfidence = liveConfidence
            } else {
                state.candidate = KindMap.hold(episode.peakCount)
                state.candidateConfidence = episode.holdConfidence
            }
        case .fired:
            state.phase = "recognized"
            state.candidate = episode.firedKind
            state.candidateConfidence = episode.firedConfidence
        case .cancelled:
            state.phase = "cancelled"
        }
        liveState = state
    }

    /// While the fingers have not moved: a tap candidate first, then a hold candidate whose
    /// confidence grows with elapsed time.
    private func fillStationaryCandidate(_ state: inout RecognizerLiveState, now: TimeInterval) {
        let count = episode.peakCount
        guard !episode.liftedAny, let plain = KindMap.tap(count) else { return }
        let age = now - episode.startTime
        let tapKind = resolveSingleTapKind(count: count, x: episode.originX, y: episode.originY) ?? plain
        let tapThresholds = table[tapKind]
        if age <= tapThresholds.tapMaxDuration && episode.maxDisplacementMM <= tapThresholds.tapMaxMovementMM {
            state.candidate = tapKind
            state.candidateConfidence = Confidence.tap(
                movementMM: episode.maxDisplacementMM, maxMovementMM: tapThresholds.tapMaxMovementMM,
                duration: age, maxDuration: tapThresholds.tapMaxDuration,
                landingSpread: episode.lastLandTime - episode.startTime,
                landingWindow: config.multiFingerLandingWindow)
            return
        }
        guard let holdKind = KindMap.hold(count) else { return }
        let holdThresholds = table[holdKind]
        if episode.maxDisplacementMM <= holdThresholds.holdMaxMovementMM {
            state.candidate = holdKind
            state.candidateConfidence = Confidence.clamp(age / holdThresholds.holdMinDuration)
                * Confidence.hold(movementMM: episode.maxDisplacementMM,
                                  maxMovementMM: holdThresholds.holdMaxMovementMM,
                                  landingSpread: episode.lastLandTime - episode.startTime,
                                  landingWindow: config.multiFingerLandingWindow)
        }
    }
}
