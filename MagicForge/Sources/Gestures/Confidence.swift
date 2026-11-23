import Foundation

/// Confidence model.
///
/// Every gesture has a few "comfort" terms in 0…1 that say how comfortably a threshold was
/// cleared, and a confidence of
///
///     confidence = 0.5 + 0.5 × Σ(weightᵢ × comfortᵢ)        (weights sum to 1)
///
/// so a gesture that only just scrapes past every threshold scores 0.5 and a textbook gesture
/// scores close to 1.0. With the default `minimumConfidence` of 0.6 a gesture needs an average
/// comfort of at least 0.2.
///
/// Comfort terms:
/// - below(value, limit)  = clamp(1 − value / limit)          for "must stay below" limits
/// - above(value, minimum) = clamp(value / minimum − 1)       for "must exceed" minimums (full at 2×)
enum Confidence {
    static func clamp(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }

    static func below(_ value: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return clamp(1 - value / limit)
    }

    static func above(_ value: Double, minimum: Double) -> Double {
        guard minimum > 0 else { return 1 }
        return clamp(value / minimum - 1)
    }

    /// Tap: 0.45 movement, 0.30 duration, 0.25 landing simultaneity (1 for one finger).
    static func tap(movementMM: Double, maxMovementMM: Double, duration: TimeInterval, maxDuration: TimeInterval,
                    landingSpread: TimeInterval, landingWindow: TimeInterval) -> Double {
        let terms = 0.45 * below(movementMM, limit: maxMovementMM)
            + 0.30 * below(duration, limit: maxDuration)
            + 0.25 * below(landingSpread, limit: max(landingWindow, 1e-6))
        return 0.5 + 0.5 * terms
    }

    /// Double tap: mean of both tap confidences, scaled by 0.8 + 0.2 × mean(gap comfort, distance comfort).
    static func doubleTap(first: Double, second: Double, gap: TimeInterval, window: TimeInterval,
                          distanceMM: Double, maxDistanceMM: Double) -> Double {
        let pairing = 0.5 * below(gap, limit: window) + 0.5 * below(distanceMM, limit: maxDistanceMM)
        return clamp((first + second) / 2 * (0.8 + 0.2 * pairing))
    }

    /// Hold: 0.75 movement, 0.25 landing simultaneity.
    static func hold(movementMM: Double, maxMovementMM: Double, landingSpread: TimeInterval,
                     landingWindow: TimeInterval) -> Double {
        let terms = 0.75 * below(movementMM, limit: maxMovementMM)
            + 0.25 * below(landingSpread, limit: max(landingWindow, 1e-6))
        return 0.5 + 0.5 * terms
    }

    /// Swipe: 0.40 direction accuracy, 0.30 velocity, 0.20 straightness, 0.10 finger coherence.
    /// Straightness maps (distance / path length) from 0.7…1.0 onto 0…1.
    static func swipe(deviationDegrees: Double, toleranceDegrees: Double, velocity: Double, minVelocity: Double,
                      distanceMM: Double, pathMM: Double, coherence: Double) -> Double {
        let straightRatio = pathMM > 0 ? min(distanceMM / pathMM, 1) : 1
        let terms = 0.40 * below(deviationDegrees, limit: toleranceDegrees)
            + 0.30 * above(velocity, minimum: minVelocity)
            + 0.20 * clamp((straightRatio - 0.7) / 0.3)
            + 0.10 * clamp(coherence)
        return 0.5 + 0.5 * terms
    }

    /// Pinch / rotate: 0.60 dominance over the runner-up measure, 0.40 stroke speed.
    static func twoFingerShape(winner: Double, runnerUp: Double, strokeTime: TimeInterval,
                               maxStrokeTime: TimeInterval) -> Double {
        let dominance = winner > 0 ? clamp(1 - runnerUp / winner) : 0
        let terms = 0.60 * dominance + 0.40 * below(strokeTime, limit: maxStrokeTime)
        return 0.5 + 0.5 * terms
    }
}
