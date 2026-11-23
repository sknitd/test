import Foundation
import MFCore

/// Measurements of one finger contact, derived from a `TouchFeed` trail (first touch → lift).
struct CalibrationContactSample: Equatable, Sendable {
    /// First trail point → last trail point, seconds.
    var duration: TimeInterval
    /// Largest distance from the landing point at any time, millimetres.
    var maxMovementMM: Double
    /// Net displacement landing → lift, millimetres (x right, y toward the front edge).
    var netXMM: Double
    var netYMM: Double
    /// Median sensor contact size seen while the finger was down; nil when the adapter reports none.
    var size: Double?

    var netDistanceMM: Double { (netXMM * netXMM + netYMM * netYMM).squareRoot() }
}

/// The statistics behind calibration. Everything is a plain median of the accepted samples:
/// medians ignore the odd sloppy tap without needing outlier rules.
enum CalibrationMath {
    /// Contacts longer / further than this are not counted as calibration taps.
    static let tapMaxDuration: TimeInterval = 0.5
    static let tapMaxMovementMM: Double = 6
    /// A calibration swipe must travel at least this far.
    static let swipeMinDistanceMM: Double = 6

    static let requiredTaps = 5
    static let swipeOrder: [GestureKind.Direction] = [.up, .down, .left, .right]

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    static func sample(from trail: [TouchFeed.TrailPoint], sizes: [Double], surface: SurfaceGeometry) -> CalibrationContactSample? {
        guard let first = trail.first, let last = trail.last else { return nil }
        var maxMovement: Double = 0
        for point in trail {
            let dx = (point.x - first.x) * surface.widthMM
            let dy = (point.y - first.y) * surface.heightMM
            maxMovement = max(maxMovement, (dx * dx + dy * dy).squareRoot())
        }
        let positiveSizes = sizes.filter { $0 > 0 }
        return CalibrationContactSample(duration: max(0, last.timestamp - first.timestamp), maxMovementMM: maxMovement,
                                        netXMM: (last.x - first.x) * surface.widthMM,
                                        netYMM: (last.y - first.y) * surface.heightMM,
                                        size: median(positiveSizes))
    }

    static func isTap(_ sample: CalibrationContactSample) -> Bool {
        sample.duration <= tapMaxDuration && sample.maxMovementMM <= tapMaxMovementMM
    }

    /// Direction of a swipe sample, or nil when it is too short to tell.
    static func direction(of sample: CalibrationContactSample) -> GestureKind.Direction? {
        guard sample.netDistanceMM >= swipeMinDistanceMM else { return nil }
        if abs(sample.netXMM) > abs(sample.netYMM) { return sample.netXMM > 0 ? .right : .left }
        return sample.netYMM > 0 ? .up : .down
    }

    /// Builds the calibration from accepted samples. Fields without samples keep `base`'s value.
    static func calibration(taps: [CalibrationContactSample], swipes: [CalibrationContactSample],
                            surface: SurfaceGeometry, base: DeviceCalibration, date: Date) -> DeviceCalibration {
        var result = base
        result.surface = surface
        if let size = median(taps.compactMap(\.size)) { result.typicalTapSize = size }
        if let movement = median(taps.map(\.maxMovementMM)) { result.typicalTapMovementMM = movement }
        if let duration = median(taps.map(\.duration)) { result.typicalTapDuration = duration }
        if let distance = median(swipes.map(\.netDistanceMM)) { result.typicalSwipeDistanceMM = distance }
        result.calibratedAt = date
        return result
    }
}
