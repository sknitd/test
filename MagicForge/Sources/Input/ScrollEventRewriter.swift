import CoreGraphics
import Foundation

/// Reads and rewrites the delta fields of a scroll-wheel `CGEvent` in place.
///
/// A scroll event carries three representations per axis (axis 1 = vertical, axis 2 = horizontal):
/// - `scrollWheelEventDeltaAxisN`        integer "line" delta (what legacy clients read),
/// - `scrollWheelEventFixedPtDeltaAxisN` fractional line delta (16.16 fixed point, read as double),
/// - `scrollWheelEventPointDeltaAxisN`   pixel delta (what `NSEvent.scrollingDeltaX/Y` reports for
///                                       continuous devices such as the Magic Mouse).
///
/// A rewrite sets all three consistently on the SAME event; nothing is ever posted. The integer
/// line field is written first because writing it makes CoreGraphics recompute the other two
/// (the order used by long-standing scroll utilities); phase and momentum fields are untouched.
struct ScrollEventRewriter {
    struct Axis {
        var line: Int64
        var fixed: Double
        var point: Int64
    }

    /// Pixels per line assumed when the event itself does not reveal the ratio.
    static let defaultPointsPerLine: Double = 10

    let isContinuous: Bool
    let vertical: Axis
    let horizontal: Axis

    init(event: CGEvent) {
        isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        vertical = Axis(line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                        fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                        point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        horizontal = Axis(line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                          fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                          point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
    }

    /// The delta reported to the engine: pixels for continuous events, (fractional) lines otherwise.
    static func sampleDelta(_ axis: Axis, isContinuous: Bool) -> Double {
        if isContinuous { return Double(axis.point) }
        return axis.fixed != 0 ? axis.fixed : Double(axis.line)
    }

    var sampleDeltaX: Double { ScrollEventRewriter.sampleDelta(horizontal, isContinuous: isContinuous) }
    var sampleDeltaY: Double { ScrollEventRewriter.sampleDelta(vertical, isContinuous: isContinuous) }

    /// Computes the three field values for a new delta given in the same unit as `sampleDelta`.
    static func rewritten(_ axis: Axis, newDelta: Double, isContinuous: Bool) -> Axis {
        var pointsPerLine = defaultPointsPerLine
        if axis.fixed != 0 && axis.point != 0 {
            let ratio = abs(Double(axis.point) / axis.fixed)
            if ratio.isFinite && ratio >= 1 && ratio <= 200 { pointsPerLine = ratio }
        }
        let limit: Double = 100_000
        let delta = min(limit, max(-limit, newDelta))
        if isContinuous {
            let fixed = delta / pointsPerLine
            return Axis(line: Int64(fixed.rounded(.towardZero)), fixed: fixed, point: Int64(delta.rounded()))
        }
        var line = Int64(delta.rounded())
        if line == 0 && delta != 0 { line = delta > 0 ? 1 : -1 }
        return Axis(line: line, fixed: delta, point: Int64((delta * pointsPerLine).rounded()))
    }

    /// Writes new deltas (same unit as the sample) into `event`. Non-finite values are ignored.
    func apply(deltaX: Double, deltaY: Double, to event: CGEvent) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        if deltaX == sampleDeltaX && deltaY == sampleDeltaY { return }
        let newVertical = ScrollEventRewriter.rewritten(vertical, newDelta: deltaY, isContinuous: isContinuous)
        let newHorizontal = ScrollEventRewriter.rewritten(horizontal, newDelta: deltaX, isContinuous: isContinuous)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newVertical.line)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: newHorizontal.line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: newVertical.fixed)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: newHorizontal.fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newVertical.point)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: newHorizontal.point)
    }
}
