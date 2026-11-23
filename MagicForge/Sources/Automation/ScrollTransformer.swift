import Foundation
import MFCore

/// Smart Scroll maths. A pure, deterministic value type: the same samples and settings always
/// give the same decisions, and it performs no I/O.
///
/// It only ever answers "leave this event alone" or "rewrite this event's deltas". It never
/// asks for an event to be dropped or for extra events to be posted, so momentum, phases and
/// event ordering stay exactly as the system produced them.
///
/// For each sample that is not passed through (see `decide`):
///
///     speed   = EMA(|delta| / dt)                      // dt clamped to 1/240 s … 0.1 s
///     gain    = 1 + acceleration · 3 · speed / (speed + reference)
///     factorX = horizontalMultiplier · (invertHorizontal ? −1 : 1) · gain
///     factorY = verticalMultiplier   · (invertVertical   ? −1 : 1) · gain
///     dx      = |dx| < horizontalDeadZone · |dy| ? 0 : dx
///     out     = clamp(delta · factor)
///
/// `reference` is 1500 px/s for continuous deltas and 40 lines/s for line deltas, so `gain`
/// rises monotonically with speed from 1 towards `1 + 3 · acceleration` and is always bounded.
/// Momentum events reuse the factors of the last finger-driven sample of their gesture, so the
/// glide keeps the direction and scale the gesture ended with. Line-based (non-continuous)
/// deltas are additionally low-pass filtered when `smoothing > 0`:
/// `y[n] = (1 − β)·x[n] + β·y[n−1]` with `β = 0.8 · smoothing`, restarted whenever the input
/// stops or reverses so the output never has the opposite sign of its input.
public struct ScrollTransformer: Sendable, Equatable {
    /// A pause longer than this starts a new gesture (speed and smoothing state reset).
    public static let gestureGap: TimeInterval = 0.25
    /// Extra gain at `acceleration == 1` and very high speed (total gain 1 + this).
    public static let maxExtraGain: Double = 3
    public static let continuousReferenceSpeed: Double = 1500
    public static let lineReferenceSpeed: Double = 40
    /// Output clamp per event: pixels for continuous deltas, lines otherwise.
    public static let maxContinuousDelta: Double = 4000
    public static let maxLineDelta: Double = 200
    /// Multipliers are clamped to 0 … this.
    public static let maxMultiplier: Double = 20

    private var lastTimestamp: TimeInterval?
    private var speed: Double = 0
    private var hasFactors = false
    private var factorX: Double = 1
    private var factorY: Double = 1
    private var smoothedX: Double = 0
    private var smoothedY: Double = 0

    public init() {}

    /// Forgets the current gesture. Call when the event tap restarts.
    public mutating func reset() { self = ScrollTransformer() }

    /// Decides what to do with one scroll event.
    ///
    /// Returns `.passThrough` when Smart Scroll is disabled, when `magicMouseOnly` is set and the
    /// event is not from a Magic Mouse, when the settings amount to an identity transform, when
    /// the sample contains non-finite numbers, or when the result equals the input.
    public mutating func decide(_ sample: ScrollSample, settings: ScrollSettings) -> ScrollDecision {
        guard settings.isEnabled else {
            reset()
            return .passThrough
        }
        if settings.magicMouseOnly && !sample.isFromMagicMouse { return .passThrough }
        guard sample.deltaX.isFinite, sample.deltaY.isFinite, sample.timestamp.isFinite else { return .passThrough }

        let parameters = Parameters(settings)
        if parameters.isIdentity(continuous: sample.isContinuous) {
            reset()
            return .passThrough
        }

        let elapsed = lastTimestamp.map { sample.timestamp - $0 }
        let startsGesture = elapsed.map { $0 > Self.gestureGap || $0 < 0 } ?? true
        lastTimestamp = sample.timestamp

        if !sample.isMomentum {
            if startsGesture {
                speed = 0
                smoothedX = 0
                smoothedY = 0
            }
            let dt = startsGesture ? 1.0 / 60.0 : min(max(elapsed ?? 0, 1.0 / 240.0), 0.1)
            let magnitude = (sample.deltaX * sample.deltaX + sample.deltaY * sample.deltaY).squareRoot()
            let instantaneous = magnitude / dt
            speed = startsGesture ? instantaneous : 0.5 * speed + 0.5 * instantaneous
            if !speed.isFinite { speed = 0 }
            let reference = sample.isContinuous ? Self.continuousReferenceSpeed : Self.lineReferenceSpeed
            let gain = 1 + parameters.acceleration * Self.maxExtraGain * speed / (speed + reference)
            factorX = parameters.horizontal * gain
            factorY = parameters.vertical * gain
            hasFactors = true
        } else if !hasFactors {
            // Momentum with no gesture on record (e.g. Smart Scroll was just enabled): no acceleration.
            factorX = parameters.horizontal
            factorY = parameters.vertical
            hasFactors = true
        }

        var inputX = sample.deltaX
        if parameters.deadZone > 0, abs(inputX) < parameters.deadZone * abs(sample.deltaY) { inputX = 0 }
        var outX = inputX * factorX
        var outY = sample.deltaY * factorY

        if !sample.isContinuous, parameters.smoothing > 0 {
            let beta = 0.8 * parameters.smoothing
            outX = Self.smooth(outX, state: &smoothedX, beta: beta)
            outY = Self.smooth(outY, state: &smoothedY, beta: beta)
        }

        let limit = sample.isContinuous ? Self.maxContinuousDelta : Self.maxLineDelta
        outX = min(max(outX, -limit), limit)
        outY = min(max(outY, -limit), limit)
        guard outX.isFinite, outY.isFinite else { return .passThrough }
        if outX == 0 { outX = 0 } // normalise −0
        if outY == 0 { outY = 0 }
        if outX == sample.deltaX && outY == sample.deltaY { return .passThrough }
        return .rewrite(deltaX: outX, deltaY: outY)
    }

    private static func smooth(_ value: Double, state: inout Double, beta: Double) -> Double {
        if value == 0 || state == 0 || (value < 0) != (state < 0) {
            state = value
        } else {
            state = (1 - beta) * value + beta * state
        }
        return state
    }

    /// Settings with every number forced into a safe range.
    private struct Parameters {
        var horizontal: Double
        var vertical: Double
        var acceleration: Double
        var smoothing: Double
        var deadZone: Double

        init(_ settings: ScrollSettings) {
            func clamped(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
                value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
            }
            let h = clamped(settings.horizontalMultiplier, 0...ScrollTransformer.maxMultiplier, fallback: 1)
            let v = clamped(settings.verticalMultiplier, 0...ScrollTransformer.maxMultiplier, fallback: 1)
            horizontal = settings.invertHorizontal ? -h : h
            vertical = settings.invertVertical ? -v : v
            acceleration = clamped(settings.acceleration, 0...1, fallback: 0)
            smoothing = clamped(settings.smoothing, 0...1, fallback: 0)
            deadZone = clamped(settings.horizontalDeadZone, 0...10, fallback: 0)
        }

        func isIdentity(continuous: Bool) -> Bool {
            horizontal == 1 && vertical == 1 && acceleration == 0 && deadZone == 0 && (continuous || smoothing == 0)
        }
    }
}
