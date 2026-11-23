import XCTest
import MFCore
@testable import MFGestures

final class TwoFingerShapeTests: XCTestCase {
    func testPinchInAndOut() {
        for kind in [GestureKind.pinchIn, .pinchOut] {
            let events = drive(makeEngine(), SyntheticTouch.frames(for: kind, startTime: 9))
            XCTAssertEqual(kinds(events), [kind])
            XCTAssertGreaterThanOrEqual(events.first?.magnitude ?? 0, 8)
            XCTAssertEqual(events.first?.fingerCount, 2)
        }
    }

    func testRotateBothDirections() {
        for kind in [GestureKind.rotateClockwise, .rotateCounterclockwise] {
            let events = drive(makeEngine(), SyntheticTouch.frames(for: kind, startTime: 9))
            XCTAssertEqual(kinds(events), [kind])
            XCTAssertGreaterThanOrEqual(events.first?.magnitude ?? 0, 18)
        }
    }

    func testDiagonalPinchAndRotationAtOtherOrientations() {
        let pinch = [SyntheticTouch.linePath(id: 1, from: Point(0.3, 0.35), to: Point(0.42, 0.45), duration: 0.25),
                     SyntheticTouch.linePath(id: 2, from: Point(0.7, 0.65), to: Point(0.58, 0.55), duration: 0.25)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(pinch))), [.pinchIn])
        let center = Point(0.5, 0.5)
        let rotate = [SyntheticTouch.arcPath(id: 1, center: center, radiusMM: 14, fromDegrees: 95, toDegrees: 60),
                      SyntheticTouch.arcPath(id: 2, center: center, radiusMM: 14, fromDegrees: 275, toDegrees: 240)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(rotate))), [.rotateClockwise])
    }

    func testOnlyOneTwoFingerGesturePerEpisode() {
        // Pinch in, then keep going: rotate and translate without lifting.
        let a = SyntheticTouch.ContactPath(id: 1, start: 0, duration: 0.6) { progress in
            progress < 0.4 ? Point(0.5, 0.72 - 0.13 * progress / 0.4) : Point(0.5 + (progress - 0.4), 0.59)
        }
        let b = SyntheticTouch.ContactPath(id: 2, start: 0, duration: 0.6) { progress in
            progress < 0.4 ? Point(0.5, 0.28 + 0.13 * progress / 0.4) : Point(0.5 - (progress - 0.4) * 0.5, 0.41)
        }
        XCTAssertEqual(kinds(drive(makeEngine(), render([a, b]))), [.pinchIn])
    }

    func testAmbiguousPinchPlusTranslationEmitsNothing() {
        // Both fingers travel right, one 10 mm and one 18 mm: translation and separation
        // change reach their thresholds together, so neither dominates.
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.2, 0.5), to: Point(0.392, 0.5), easing: .linear),
                     SyntheticTouch.linePath(id: 2, from: Point(0.45, 0.5), to: Point(0.796, 0.5), easing: .linear)]
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, render(paths))), [])
    }

    func testOneStaticFingerIsNotAPinchOrRotate() {
        let paths = [SyntheticTouch.holdPath(id: 1, at: Point(0.5, 0.3), duration: 0.25),
                     SyntheticTouch.linePath(id: 2, from: Point(0.5, 0.5), to: Point(0.5, 0.75), duration: 0.25)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [])
    }

    func testVerySlowPinchEmitsNothing() {
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.5, 0.72), to: Point(0.5, 0.62), duration: 3, easing: .linear),
                     SyntheticTouch.linePath(id: 2, from: Point(0.5, 0.28), to: Point(0.5, 0.38), duration: 3, easing: .linear)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [])
    }

    func testTwoFingerSwipeIsNotMistakenForPinchWhenFingersSpreadSlightly() {
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.36, 0.3), to: Point(0.34, 0.7)),
                     SyntheticTouch.linePath(id: 2, from: Point(0.62, 0.3), to: Point(0.65, 0.7))]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [.twoFingerSwipeUp])
    }
}
