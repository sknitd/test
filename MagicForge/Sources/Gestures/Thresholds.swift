import Foundation
import MFCore

/// Effective thresholds for one gesture kind after sensitivity and calibration scaling.
struct KindThresholds {
    var tapMaxDuration: TimeInterval
    var tapMaxMovementMM: Double
    var holdMinDuration: TimeInterval
    var holdMaxMovementMM: Double
    var swipeMinDistanceMM: Double
    var swipeMinVelocity: Double
    var directionToleranceDegrees: Double
    var pinchMinChangeMM: Double
    var rotationMinDegrees: Double
}

/// Sensitivity → threshold mapping.
///
///     effective = clamp(tuning.sensitivity × globalSensitivity / 0.5, 0…1)
///     factor    = 2^(1 − 2 × effective)        // 0 → 2.0, 0.5 → 1.0, 1 → 0.5
///
/// "Must exceed" thresholds (swipe distance, swipe velocity, pinch change, rotation) are
/// MULTIPLIED by `factor`; "must stay below" tolerances (tap movement, hold movement,
/// direction tolerance) are DIVIDED by it. Durations are never scaled by sensitivity; they
/// change only through `GestureTuning.duration`.
enum SensitivityMapping {
    static func effectiveSensitivity(tuning: Double, global: Double) -> Double {
        let t = tuning.isFinite ? tuning : 0.5
        let g = global.isFinite ? global : 0.5
        return min(max(t * g / 0.5, 0), 1)
    }

    static func factor(forEffectiveSensitivity value: Double) -> Double {
        pow(2, 1 - 2 * min(max(value, 0), 1))
    }
}

/// Precomputed thresholds for every gesture kind; rebuilt only when config or calibration change.
struct ThresholdTable {
    private var byKind: [GestureKind: KindThresholds] = [:]
    private let fallback: KindThresholds
    /// Contacts larger than this are palms (already scaled by calibration).
    let palmSize: Double
    /// Contacts at least this large are "flat" resting-style contacts.
    let flatSize: Double
    let widthMM: Double
    let heightMM: Double

    init(config: RecognizerConfig, calibration: DeviceCalibration) {
        let surface = calibration.surface
        widthMM = surface.widthMM > 0 ? surface.widthMM : SurfaceGeometry.magicMouse.widthMM
        heightMM = surface.heightMM > 0 ? surface.heightMM : SurfaceGeometry.magicMouse.heightMM

        let defaults = DeviceCalibration()
        // Calibration scaling: ratio of the user's typical value to the factory default, clamped.
        let tapMoveScale = ThresholdTable.ratio(calibration.typicalTapMovementMM, defaults.typicalTapMovementMM, 0.5, 2)
        let swipeScale = ThresholdTable.ratio(calibration.typicalSwipeDistanceMM, defaults.typicalSwipeDistanceMM, 0.5, 2)
        let tapDurationScale = ThresholdTable.ratio(calibration.typicalTapDuration, defaults.typicalTapDuration, 0.75, 2)
        let sizeScale = ThresholdTable.ratio(calibration.typicalTapSize, defaults.typicalTapSize, 0.5, 2)
        palmSize = config.palmSizeThreshold * sizeScale
        flatSize = min(defaults.typicalTapSize * sizeScale * EngineConstants.flatContactFactor, palmSize)

        let baseTapDuration = config.tapMaxDuration * tapDurationScale
        func make(_ kind: GestureKind?) -> KindThresholds {
            let tuning = kind.map { config.tuning(for: $0) } ?? GestureTuning()
            let effective = SensitivityMapping.effectiveSensitivity(tuning: tuning.sensitivity,
                                                                    global: config.globalSensitivity)
            let f = SensitivityMapping.factor(forEffectiveSensitivity: effective)
            let override: TimeInterval? = tuning.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let isTap = kind.map(KindMap.isTapKind) ?? false
            let isHold = kind.map(KindMap.isHoldKind) ?? false
            let tapDuration = (isTap ? override : nil) ?? baseTapDuration
            let holdDuration = max((isHold ? override : nil) ?? config.holdMinDuration,
                                   baseTapDuration + EngineConstants.minHoldOverTap)
            return KindThresholds(
                tapMaxDuration: tapDuration,
                tapMaxMovementMM: config.tapMaxMovementMM * tapMoveScale / f,
                holdMinDuration: holdDuration,
                holdMaxMovementMM: config.holdMaxMovementMM * tapMoveScale / f,
                swipeMinDistanceMM: config.swipeMinDistanceMM * swipeScale * f,
                swipeMinVelocity: config.swipeMinVelocityMMPerSecond * f,
                directionToleranceDegrees: min(config.directionToleranceDegrees / f,
                                               EngineConstants.maxDirectionToleranceDegrees),
                pinchMinChangeMM: config.pinchMinChangeMM * f,
                rotationMinDegrees: config.rotationMinDegrees * f)
        }
        fallback = make(nil)
        for kind in GestureKind.allCases where kind.requirement == .rawContacts {
            byKind[kind] = make(kind)
        }
    }

    subscript(kind: GestureKind) -> KindThresholds { byKind[kind] ?? fallback }

    private static func ratio(_ value: Double, _ reference: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite, value > 0, reference > 0 else { return 1 }
        return min(max(value / reference, low), high)
    }
}
