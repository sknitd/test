import XCTest
import MFCore
@testable import MFGestures

final class SwipeTests: XCTestCase {
    func testAllDirectionsForOneTwoAndThreeFingers() {
        let table: [[GestureKind]] = [
            [.oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown],
            [.twoFingerSwipeLeft, .twoFingerSwipeRight, .twoFingerSwipeUp, .twoFingerSwipeDown],
            [.threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp, .threeFingerSwipeDown],
        ]
        for (index, row) in table.enumerated() {
            for kind in row {
                let events = drive(makeEngine(), SyntheticTouch.frames(for: kind, startTime: 20))
                XCTAssertEqual(kinds(events), [kind])
                XCTAssertEqual(events.first?.fingerCount, index + 1)
                XCTAssertGreaterThanOrEqual(events.first?.magnitude ?? 0, 14)
            }
        }
    }

    func testSwipeFiresBeforeLiftAndOnlyOncePerEpisode() throws {
        let engine = makeEngine()
        // A long stroke up and then all the way back down, without lifting.
        let up = SyntheticTouch.linePath(id: 1, from: Point(0.5, 0.2), to: Point(0.5, 0.8), duration: 0.3)
        let path = SyntheticTouch.ContactPath(id: 1, start: 0, duration: 0.6) { progress in
            progress < 0.5 ? up.position(progress * 2) : up.position((1 - progress) * 2)
        }
        let frames = render([path])
        let events = drive(engine, frames)
        XCTAssertEqual(kinds(events), [.oneFingerSwipeUp])
        let lift = try XCTUnwrap(frames.last?.timestamp)
        XCTAssertLessThan(events[0].timestamp, lift - 0.3)
        XCTAssertLessThan(events[0].duration, 0.2)
    }

    func testQuickFlickShorterThanTheLandingWindowIsRecognized() {
        // 26 mm in 66 ms (about 400 mm/s): over before the 90 ms landing window closes.
        let flick = SyntheticTouch.linePath(from: Point(0.75, 0.5), to: Point(0.25, 0.5), duration: 0.066)
        XCTAssertEqual(kinds(drive(makeEngine(), render([flick]))), [.oneFingerSwipeLeft])
        let pair = [SyntheticTouch.linePath(id: 1, from: Point(0.38, 0.3), to: Point(0.38, 0.7), duration: 0.066),
                    SyntheticTouch.linePath(id: 2, from: Point(0.62, 0.3), to: Point(0.62, 0.7), duration: 0.066)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(pair, endStyle: .disappear))), [.twoFingerSwipeUp])
    }

    func testEdgeSwipesTakePrecedenceAndFallBackWhenDisabled() {
        let cases: [(GestureKind, GestureKind)] = [(.leftEdgeSwipe, .oneFingerSwipeUp), (.rightEdgeSwipe, .oneFingerSwipeDown),
                                                   (.topEdgeSwipe, .oneFingerSwipeRight),
                                                   (.bottomEdgeSwipe, .oneFingerSwipeLeft)]
        for (edge, plain) in cases {
            let frames = SyntheticTouch.frames(for: edge, startTime: 4)
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [edge, plain]), frames)), [edge])
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [plain]), frames)), [plain])
        }
    }

    func testEdgeSwipeRunsInEitherDirection() {
        let down = SyntheticTouch.linePath(from: Point(0.08, 0.7), to: Point(0.08, 0.3), duration: 0.22)
        XCTAssertEqual(kinds(drive(makeEngine(), render([down]))), [.leftEdgeSwipe])
    }

    func testStrokeLeavingTheEdgeZoneIsAPlainSwipe() {
        // Starts in the left strip but runs across the surface.
        let across = SyntheticTouch.linePath(from: Point(0.08, 0.5), to: Point(0.7, 0.5), duration: 0.2)
        XCTAssertEqual(kinds(drive(makeEngine(), render([across]))), [.oneFingerSwipeRight])
        // Vertical stroke that drifts out of the strip before reaching swipe length.
        let drifting = SyntheticTouch.linePath(from: Point(0.12, 0.3), to: Point(0.26, 0.7), duration: 0.22)
        XCTAssertEqual(kinds(drive(makeEngine(), render([drifting]))), [.oneFingerSwipeUp])
    }

    func testDiagonalSwipeOutsideToleranceEmitsNothing() {
        // 20.8 mm right and 20.7 mm up: 45°, outside the 30° tolerance of both axes.
        let diagonal = SyntheticTouch.linePath(from: Point(0.3, 0.4), to: Point(0.7, 0.63), duration: 0.2)
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, render([diagonal]))), [])
        // 20° off axis is still a swipe.
        let slanted = SyntheticTouch.linePath(from: Point(0.5, 0.3), to: Point(0.75, 0.7), duration: 0.2)
        XCTAssertEqual(kinds(drive(makeEngine(), render([slanted]))), [.oneFingerSwipeUp])
    }

    func testDiagonalThatStraightensLaterStillEmitsNothing() {
        let path = SyntheticTouch.ContactPath(id: 1, start: 0, duration: 0.4) { progress in
            progress < 0.5 ? Point(0.3 + 0.8 * progress, 0.3 + 0.46 * progress)
                           : Point(0.7, 0.53 + 0.8 * (progress - 0.5))
        }
        XCTAssertEqual(kinds(drive(makeEngine(), render([path]))), [])
    }

    func testTooSlowStrokeIsCancelled() {
        // 36 mm in 1.2 s = 30 mm/s, far below the 70 mm/s minimum.
        let slow = SyntheticTouch.linePath(from: Point(0.5, 0.3), to: Point(0.5, 0.7), duration: 1.2, easing: .linear)
        let engine = makeEngine()
        let frames = render([slow])
        var events: [GestureEvent] = []
        var sawCancelled = false
        for frame in frames {
            events += engine.process(frame)
            if engine.liveState.phase == "cancelled" { sawCancelled = true }
        }
        XCTAssertEqual(kinds(events), [])
        XCTAssertTrue(sawCancelled)
    }

    func testTooShortStrokeEmitsNothing() {
        let short = SyntheticTouch.linePath(from: Point(0.5, 0.45), to: Point(0.5, 0.56), duration: 0.08)   // 9.9 mm
        XCTAssertEqual(kinds(drive(makeEngine(), render([short]))), [])
    }

    func testFingersMovingInOppositeDirectionsAreNotASwipe() {
        // Three fingers; the centroid moves up 14+ mm but one finger goes the other way.
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.3, 0.2), to: Point(0.3, 0.75)),
                     SyntheticTouch.linePath(id: 2, from: Point(0.5, 0.2), to: Point(0.5, 0.75)),
                     SyntheticTouch.linePath(id: 3, from: Point(0.7, 0.6), to: Point(0.7, 0.5))]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [])
    }
}
