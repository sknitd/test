import XCTest
import MFCore
@testable import MFGestures

final class TapTests: XCTestCase {
    let spot = Point(0.5, 0.8)

    func testSingleTapEmitsImmediatelyOnLiftWhenNoDoubleTapIsEnabled() {
        let engine = makeEngine(enabled: [.oneFingerTap])
        let frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        let events = drive(engine, frames, settle: false)
        XCTAssertEqual(kinds(events), [.oneFingerTap])
        XCTAssertEqual(events[0].timestamp, frames.last?.timestamp)   // the lift frame itself
        XCTAssertNil(engine.nextDeadline)
        XCTAssertEqual(events[0].originX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(events[0].originY, 0.8, accuracy: 1e-9)
    }

    func testSingleTapWaitsForDoubleTapWindowOnlyWhenDoubleTapEnabled() throws {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        XCTAssertTrue(drive(engine, frames, settle: false).isEmpty)
        let lift = try XCTUnwrap(frames.last?.timestamp)
        let deadline = try XCTUnwrap(engine.nextDeadline)
        XCTAssertEqual(deadline, lift + engine.config.doubleTapWindow, accuracy: 1e-9)
        XCTAssertEqual(engine.liveState.phase, "awaitingSecondTap")
        XCTAssertTrue(engine.advance(to: deadline - 0.01).isEmpty)
        let events = engine.advance(to: deadline)
        XCTAssertEqual(kinds(events), [.oneFingerTap])
        XCTAssertEqual(events[0].timestamp, deadline)
        XCTAssertNil(engine.nextDeadline)
        XCTAssertTrue(engine.advance(to: deadline + 1).isEmpty)
    }

    func testTapThenSwipeEnabledAlsoDelaysSingleTap() {
        let engine = makeEngine(enabled: [.oneFingerTap, .tapThenSwipeLeft])
        XCTAssertTrue(drive(engine, SyntheticTouch.frames(for: .oneFingerTap, startTime: 1), settle: false).isEmpty)
        XCTAssertNotNil(engine.nextDeadline)
        // Two-finger taps are not delayed by one-finger compound gestures.
        let other = makeEngine(enabled: [.twoFingerTap, .oneFingerDoubleTap, .tapThenSwipeLeft])
        XCTAssertEqual(kinds(drive(other, SyntheticTouch.frames(for: .twoFingerTap, startTime: 1), settle: false)),
                       [.twoFingerTap])
    }

    func testDoubleTap() {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let events = drive(engine, SyntheticTouch.frames(for: .oneFingerDoubleTap, startTime: 10))
        XCTAssertEqual(kinds(events), [.oneFingerDoubleTap])
        XCTAssertEqual(events[0].fingerCount, 1)
    }

    func testTwoFingerDoubleTap() {
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .twoFingerDoubleTap, startTime: 10))),
                       [.twoFingerDoubleTap])
    }

    func testTwoSlowTapsAreTwoSingleTaps() {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let frames = render([SyntheticTouch.tapPath(id: 1, at: spot), SyntheticTouch.tapPath(id: 2, at: spot, start: 0.6)])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .oneFingerTap])
    }

    func testTwoQuickTapsFarApartAreTwoSingleTaps() {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let frames = render([SyntheticTouch.tapPath(id: 1, at: Point(0.5, 0.8)),
                             SyntheticTouch.tapPath(id: 2, at: Point(0.5, 0.2), start: 0.18)])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .oneFingerTap])
    }

    func testOneFingerTapFollowedByTwoFingerTapAreSeparate() {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap, .twoFingerTap])
        let frames = render([SyntheticTouch.tapPath(id: 1, at: spot),
                             SyntheticTouch.tapPath(id: 2, at: Point(0.38, 0.6), start: 0.18),
                             SyntheticTouch.tapPath(id: 3, at: Point(0.62, 0.6), start: 0.18)])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .twoFingerTap])
    }

    func testTripleTapIsDoubleThenSingle() {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let frames = render([SyntheticTouch.tapPath(id: 1, at: spot), SyntheticTouch.tapPath(id: 2, at: spot, start: 0.2),
                             SyntheticTouch.tapPath(id: 3, at: spot, start: 0.4)])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerDoubleTap, .oneFingerTap])
    }

    func testCornerAndCenterTaps() {
        let cases: [(GestureKind, Point)] = [(.cornerTapTopLeft, Point(0.1, 0.9)), (.cornerTapTopRight, Point(0.9, 0.9)),
                                             (.cornerTapBottomLeft, Point(0.1, 0.1)),
                                             (.cornerTapBottomRight, Point(0.9, 0.1)), (.centerTap, Point(0.5, 0.5))]
        for (kind, point) in cases {
            let frames = render([SyntheticTouch.tapPath(at: point)])
            // Most specific enabled kind wins, and exactly one kind is emitted.
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap, kind]), frames)), [kind])
            // With the zone kind disabled the same touch is a plain tap.
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), frames)), [.oneFingerTap])
            // With only another zone enabled nothing fires.
            let other: GestureKind = kind == .centerTap ? .cornerTapTopLeft : .centerTap
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [other]), frames)), [])
        }
        // A tap outside every zone is plain even when all zones are enabled.
        let plain = render([SyntheticTouch.tapPath(at: Point(0.5, 0.8))])
        let all: [GestureKind] = [.oneFingerTap, .centerTap, .cornerTapTopLeft, .cornerTapTopRight,
                                  .cornerTapBottomLeft, .cornerTapBottomRight]
        XCTAssertEqual(kinds(drive(makeEngine(enabled: all), plain)), [.oneFingerTap])
    }

    func testDoubleTapInsideAZoneWinsOverZoneTap() {
        let engine = makeEngine(enabled: [.oneFingerDoubleTap, .centerTap, .oneFingerTap])
        let center = Point(0.5, 0.5)
        let frames = render([SyntheticTouch.tapPath(id: 1, at: center), SyntheticTouch.tapPath(id: 2, at: center, start: 0.18)])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerDoubleTap])
    }

    func testTooLongTouchIsNotATap() {
        let engine = makeEngine(enabled: [.oneFingerTap, .twoFingerTap, .threeFingerTap])
        XCTAssertEqual(kinds(drive(engine, render([SyntheticTouch.tapPath(at: spot, duration: 0.3)]))), [])
    }

    func testTouchThatMovesTooMuchIsNotATap() {
        let engine = makeEngine()
        let path = SyntheticTouch.linePath(from: Point(0.5, 0.5), to: Point(0.5, 0.56), duration: 0.09)   // 5.4 mm
        XCTAssertEqual(kinds(drive(engine, render([path]))), [])
    }

    func testSingleFrameBlipIsNotATap() {
        let engine = makeEngine(enabled: [.oneFingerTap])
        let frames = render([SyntheticTouch.tapPath(at: spot, duration: 0.009)], endStyle: .disappear)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(kinds(drive(engine, frames)), [])
    }

    func testThreeFingerTapAndStaggeredLanding() {
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .threeFingerTap, startTime: 2))), [.threeFingerTap])
        // Fingers landing 40 ms apart (inside the 90 ms landing window) are still one two-finger tap.
        let staggered = render([SyntheticTouch.tapPath(id: 1, at: Point(0.38, 0.6), duration: 0.1),
                                SyntheticTouch.tapPath(id: 2, at: Point(0.62, 0.6), start: 0.04, duration: 0.08)])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap, .twoFingerTap]), staggered)), [.twoFingerTap])
        // 150 ms apart is not a two-finger tap.
        let late = render([SyntheticTouch.tapPath(id: 1, at: Point(0.38, 0.6), duration: 0.2),
                           SyntheticTouch.tapPath(id: 2, at: Point(0.62, 0.6), start: 0.15, duration: 0.05)])
        XCTAssertFalse(kinds(drive(makeEngine(enabled: [.oneFingerTap, .twoFingerTap]), late)).contains(.twoFingerTap))
    }

    func testFourFingersEmitNothing() {
        let points = [Point(0.2, 0.6), Point(0.4, 0.6), Point(0.6, 0.6), Point(0.8, 0.6)]
        let taps = points.enumerated().map { SyntheticTouch.tapPath(id: $0.offset + 1, at: $0.element) }
        XCTAssertEqual(kinds(drive(makeEngine(), render(taps))), [])
    }
}
