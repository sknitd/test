import XCTest
import MFCore
@testable import MFGestures

final class TuningTests: XCTestCase {
    /// 9.9 mm stroke in 80 ms: shorter than the default 14 mm swipe distance.
    let shortStroke = [SyntheticTouch.linePath(from: Point(0.5, 0.45), to: Point(0.5, 0.56), duration: 0.08)]

    func testSensitivityMapping() {
        XCTAssertEqual(SensitivityMapping.factor(forEffectiveSensitivity: 0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(SensitivityMapping.factor(forEffectiveSensitivity: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(SensitivityMapping.factor(forEffectiveSensitivity: 0), 2, accuracy: 1e-12)
        XCTAssertEqual(SensitivityMapping.effectiveSensitivity(tuning: 0.5, global: 0.5), 0.5)
        XCTAssertEqual(SensitivityMapping.effectiveSensitivity(tuning: 1, global: 1), 1)
        XCTAssertEqual(SensitivityMapping.effectiveSensitivity(tuning: 0.8, global: 0.25), 0.4, accuracy: 1e-12)
        XCTAssertEqual(SensitivityMapping.effectiveSensitivity(tuning: .nan, global: 0.5), 0.5)

        var config = RecognizerConfig()
        config.setTuning(GestureTuning(sensitivity: 1), for: .twoFingerSwipeLeft)
        config.setTuning(GestureTuning(sensitivity: 0), for: .pinchIn)
        let table = ThresholdTable(config: config, calibration: DeviceCalibration())
        XCTAssertEqual(table[.twoFingerSwipeLeft].swipeMinDistanceMM, 7, accuracy: 1e-9)
        XCTAssertEqual(table[.twoFingerSwipeLeft].swipeMinVelocity, 35, accuracy: 1e-9)
        XCTAssertEqual(table[.twoFingerSwipeLeft].directionToleranceDegrees, 44, accuracy: 1e-9)   // 60° clamped
        XCTAssertEqual(table[.twoFingerSwipeLeft].tapMaxMovementMM, 5, accuracy: 1e-9)
        XCTAssertEqual(table[.twoFingerSwipeRight].swipeMinDistanceMM, 14, accuracy: 1e-9)
        XCTAssertEqual(table[.pinchIn].pinchMinChangeMM, 16, accuracy: 1e-9)
        XCTAssertEqual(table[.pinchIn].rotationMinDegrees, 36, accuracy: 1e-9)
        XCTAssertEqual(table[.oneFingerTap].tapMaxDuration, 0.22, accuracy: 1e-9)   // durations are not scaled
        XCTAssertEqual(table[.oneFingerHold].holdMinDuration, 0.5, accuracy: 1e-9)
    }

    func testHigherPerGestureSensitivityAcceptsShorterSwipe() {
        XCTAssertEqual(kinds(drive(makeEngine(), render(shortStroke))), [])
        let sensitive = makeEngine { $0.setTuning(GestureTuning(sensitivity: 1), for: .oneFingerSwipeUp) }
        XCTAssertEqual(kinds(drive(sensitive, render(shortStroke))), [.oneFingerSwipeUp])
        // Tuning one kind does not change another.
        let other = makeEngine { $0.setTuning(GestureTuning(sensitivity: 1), for: .oneFingerSwipeDown) }
        XCTAssertEqual(kinds(drive(other, render(shortStroke))), [])
    }

    func testLowerSensitivityRequiresMoreDeliberateGesture() {
        let frames = SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 3)   // 22 mm stroke
        XCTAssertEqual(kinds(drive(makeEngine(), frames)), [.twoFingerSwipeLeft])
        let strict = makeEngine { $0.setTuning(GestureTuning(sensitivity: 0), for: .twoFingerSwipeLeft) }   // needs 28 mm
        XCTAssertEqual(kinds(drive(strict, frames)), [])
        let pinch = SyntheticTouch.frames(for: .pinchIn, startTime: 3)               // 23 mm change
        let strictPinch = makeEngine { $0.setTuning(GestureTuning(sensitivity: 0), for: .pinchIn) }  // needs 16 mm
        XCTAssertEqual(kinds(drive(strictPinch, pinch)), [.pinchIn])
        let small = [SyntheticTouch.linePath(id: 1, from: Point(0.5, 0.66), to: Point(0.5, 0.60), duration: 0.2),
                     SyntheticTouch.linePath(id: 2, from: Point(0.5, 0.34), to: Point(0.5, 0.40), duration: 0.2)]  // 10.8 mm
        XCTAssertEqual(kinds(drive(makeEngine(), render(small))), [.pinchIn])
        XCTAssertEqual(kinds(drive(strictPinch, render(small, at: 20))), [])
    }

    func testGlobalSensitivityScalesEveryGesture() {
        let loose = makeEngine { $0.globalSensitivity = 1 }
        XCTAssertEqual(kinds(drive(loose, render(shortStroke))), [.oneFingerSwipeUp])
        let strict = makeEngine { $0.globalSensitivity = 0 }
        XCTAssertEqual(kinds(drive(strict, SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 3))), [])
        // A sloppy tap (2.0 mm of movement) passes at neutral sensitivity and fails when strict
        // (the tolerance halves to 1.25 mm).
        let sloppy = render([SyntheticTouch.tapPath(at: Point(0.5, 0.8), driftMM: 2.0)])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), sloppy)), [.oneFingerTap])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]) { $0.globalSensitivity = 0 }, sloppy)), [])
    }

    func testConfigChangesApplyToARunningEngine() {
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, render(shortStroke))), [])
        engine.config.swipeMinDistanceMM = 8
        XCTAssertEqual(kinds(drive(engine, render(shortStroke, at: 20))), [.oneFingerSwipeUp])
    }

    func testCalibrationScalesThresholds() {
        var calibration = DeviceCalibration()
        calibration.typicalSwipeDistanceMM = 50          // this user swipes long: 28 mm needed
        calibration.typicalTapMovementMM = 1.6           // and taps sloppily: 5 mm allowed
        let table = ThresholdTable(config: RecognizerConfig(), calibration: calibration)
        XCTAssertEqual(table[.oneFingerSwipeUp].swipeMinDistanceMM, 28, accuracy: 1e-9)
        XCTAssertEqual(table[.oneFingerTap].tapMaxMovementMM, 5, accuracy: 1e-9)

        let engine = GestureEngine(calibration: calibration)
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 3))), [])
        let sloppy = render([SyntheticTouch.tapPath(at: Point(0.5, 0.8), driftMM: 3.5)])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), sloppy)), [])
        engine.enabledKinds = [.oneFingerTap]
        XCTAssertEqual(kinds(drive(engine, sloppy)), [.oneFingerTap])
    }

    func testSurfaceGeometryConvertsToMillimetres() {
        // The same normalized stroke is half as long on a surface half the size.
        var calibration = DeviceCalibration()
        calibration.surface = SurfaceGeometry(widthMM: 26, heightMM: 30)
        let stroke = [SyntheticTouch.linePath(from: Point(0.5, 0.3), to: Point(0.5, 0.7), duration: 0.2)]   // 12 mm here
        XCTAssertEqual(kinds(drive(GestureEngine(calibration: calibration), render(stroke))), [])
        XCTAssertEqual(kinds(drive(GestureEngine(), render(stroke))), [.oneFingerSwipeUp])               // 36 mm
        // The generator honours the surface it is given.
        let small = SurfaceGeometry(widthMM: 40, heightMM: 60)
        calibration.surface = small
        for kind in rawKinds {
            let frames = SyntheticTouch.frames(for: kind, startTime: 1, surface: small)
            XCTAssertEqual(kinds(drive(GestureEngine(calibration: calibration), frames)), expectedWithAllEnabled(kind),
                           "\(kind) on a 40×60 mm surface")
        }
    }

    func testMinimumConfidence() throws {
        let clean = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        // 2.2 mm of movement and 200 ms: inside the limits, but only just.
        let marginal = render([SyntheticTouch.tapPath(at: Point(0.5, 0.8), duration: 0.19, driftMM: 2.2)])

        let lenient = makeEngine(enabled: [.oneFingerTap]) { $0.minimumConfidence = 0 }
        let cleanEvent = try XCTUnwrap(drive(lenient, clean).first)
        let marginalEvent = try XCTUnwrap(drive(lenient, marginal).first)
        XCTAssertGreaterThan(cleanEvent.confidence, 0.85)
        XCTAssertLessThan(marginalEvent.confidence, 0.7)
        XCTAssertGreaterThanOrEqual(marginalEvent.confidence, 0.5)

        let standard = makeEngine(enabled: [.oneFingerTap]) { $0.minimumConfidence = 0.7 }
        XCTAssertEqual(kinds(drive(standard, clean)), [.oneFingerTap])
        XCTAssertEqual(kinds(drive(standard, marginal)), [])
        let impossible = makeEngine { $0.minimumConfidence = 1.01 }
        for kind in rawKinds {
            XCTAssertEqual(kinds(drive(impossible, SyntheticTouch.frames(for: kind, startTime: 5))), [])
            impossible.reset()
        }
    }

    func testConfidenceReflectsHowCleanlyTheGestureWasMade() throws {
        let straight = try XCTUnwrap(drive(makeEngine(), SyntheticTouch.frames(for: .oneFingerSwipeUp, startTime: 1)).first)
        let slanted = try XCTUnwrap(drive(makeEngine(), render(
            [SyntheticTouch.linePath(from: Point(0.5, 0.3), to: Point(0.75, 0.7), duration: 0.2)])).first)   // ~20° off
        XCTAssertEqual(slanted.kind, .oneFingerSwipeUp)
        XCTAssertGreaterThan(straight.confidence, slanted.confidence)
        XCTAssertGreaterThan(straight.confidence, 0.9)
        for kind in rawKinds {
            for event in drive(makeEngine(), SyntheticTouch.frames(for: kind, startTime: 5)) {
                XCTAssertGreaterThanOrEqual(event.confidence, 0.6, "\(kind)")
                XCTAssertLessThanOrEqual(event.confidence, 1, "\(kind)")
            }
        }
    }

    func testConfidenceFormulaBounds() {
        XCTAssertEqual(Confidence.tap(movementMM: 0, maxMovementMM: 2.5, duration: 0, maxDuration: 0.22,
                                      landingSpread: 0, landingWindow: 0.09), 1, accuracy: 1e-12)
        XCTAssertEqual(Confidence.tap(movementMM: 2.5, maxMovementMM: 2.5, duration: 0.22, maxDuration: 0.22,
                                      landingSpread: 0.09, landingWindow: 0.09), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Confidence.swipe(deviationDegrees: 30, toleranceDegrees: 30, velocity: 70, minVelocity: 70,
                                        distanceMM: 7, pathMM: 10, coherence: 0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Confidence.swipe(deviationDegrees: 0, toleranceDegrees: 30, velocity: 140, minVelocity: 70,
                                        distanceMM: 14, pathMM: 14, coherence: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(Confidence.twoFingerShape(winner: 1, runnerUp: 1, strokeTime: 0.8, maxStrokeTime: 0.8), 0.5,
                       accuracy: 1e-12)
    }
}
