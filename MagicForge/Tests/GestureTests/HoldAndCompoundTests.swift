import XCTest
import MFCore
@testable import MFGestures

final class HoldAndCompoundTests: XCTestCase {
    func testHoldFiresOnceViaAdvanceAtTheDeadline() throws {
        let engine = makeEngine(enabled: [.oneFingerHold])
        let frames = SyntheticTouch.frames(for: .oneFingerHold, startTime: 30)
        let start = try XCTUnwrap(frames.first?.timestamp)
        var events: [GestureEvent] = []
        var advanced = false
        for frame in frames {
            if !advanced, let deadline = engine.nextDeadline, deadline < frame.timestamp {
                XCTAssertEqual(deadline, start + engine.config.holdMinDuration, accuracy: 1e-9)
                events += engine.advance(to: deadline)
                XCTAssertEqual(kinds(events), [.oneFingerHold])
                XCTAssertEqual(events[0].timestamp, deadline)
                XCTAssertNil(engine.nextDeadline)
                XCTAssertEqual(engine.liveState.phase, "held")
                advanced = true
            }
            events += engine.process(frame)
        }
        XCTAssertTrue(advanced)
        XCTAssertEqual(kinds(events), [.oneFingerHold])
        XCTAssertEqual(events[0].duration, 0.5, accuracy: 1e-6)
    }

    func testHoldFiresOnceFromALaterFrameWithoutAdvance() throws {
        let engine = makeEngine(enabled: [.oneFingerHold, .twoFingerHold, .threeFingerHold])
        for kind in [GestureKind.oneFingerHold, .twoFingerHold, .threeFingerHold] {
            let frames = SyntheticTouch.frames(for: kind, startTime: 30)
            let start = try XCTUnwrap(frames.first?.timestamp)
            var events: [GestureEvent] = []
            for frame in frames { events += engine.process(frame) }
            XCTAssertEqual(kinds(events), [kind])
            XCTAssertGreaterThanOrEqual(events[0].timestamp, start + 0.5)
            XCTAssertLessThan(events[0].timestamp, start + 0.5 + 0.012)
            engine.reset()
        }
    }

    func testHoldIsCancelledByMovement() {
        // Creeps 6 mm in 0.7 s: past the 3 mm hold tolerance before 0.5 s, never a swipe.
        let path = SyntheticTouch.slowDriftPath(from: Point(0.5, 0.5), to: Point(0.5, 0.567), duration: 0.7)
        XCTAssertEqual(kinds(drive(makeEngine(), render([path]))), [])
    }

    func testReleasedBeforeHoldDurationIsNeitherTapNorHold() {
        let path = SyntheticTouch.holdPath(at: Point(0.5, 0.8), duration: 0.4)
        XCTAssertEqual(kinds(drive(makeEngine(), render([path]))), [])
    }

    func testHoldDurationOverride() {
        let engine = makeEngine(enabled: [.oneFingerHold]) { config in
            config.setTuning(GestureTuning(sensitivity: 0.5, duration: 0.3), for: .oneFingerHold)
        }
        let events = drive(engine, render([SyntheticTouch.holdPath(at: Point(0.5, 0.8), duration: 0.4)]))
        XCTAssertEqual(kinds(events), [.oneFingerHold])
        XCTAssertEqual(events[0].duration, 0.3, accuracy: 1e-6)
    }

    func testHoldThenSwipeAllDirections() {
        for kind in [GestureKind.holdThenSwipeLeft, .holdThenSwipeRight, .holdThenSwipeUp, .holdThenSwipeDown] {
            let frames = SyntheticTouch.frames(for: kind, startTime: 12)
            XCTAssertEqual(kinds(drive(makeEngine(), frames)), [.oneFingerHold, kind])
            // The compound gesture does not need the hold itself to be enabled.
            XCTAssertEqual(kinds(drive(makeEngine(enabled: [kind]), frames)), [kind])
            // After a hold the stroke is never reported as a plain swipe.
            let plain: [GestureKind] = [.oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown]
            XCTAssertEqual(kinds(drive(makeEngine(enabled: plain), frames)), [])
        }
    }

    func testTapThenSwipeAllDirections() {
        for kind in [GestureKind.tapThenSwipeLeft, .tapThenSwipeRight, .tapThenSwipeUp, .tapThenSwipeDown] {
            let frames = SyntheticTouch.frames(for: kind, startTime: 12)
            let events = drive(makeEngine(), frames)
            XCTAssertEqual(kinds(events), [kind])          // the tap is consumed, not emitted as well
            XCTAssertEqual(events.first?.fingerCount, 1)
        }
    }

    func testTapThenSwipeInADirectionThatIsNotEnabledIsTapPlusSwipe() {
        let frames = SyntheticTouch.frames(for: .tapThenSwipeUp, startTime: 12)
        let engine = makeEngine(enabled: [.centerTap, .oneFingerTap, .tapThenSwipeLeft, .oneFingerSwipeUp])
        // The tap is released first (in order), then the plain swipe.
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .oneFingerSwipeUp])
    }

    func testTapThenLateSwipeIsNotCompound() {
        let ends = SyntheticTouch.strokeEnds(for: .left, surface: .magicMouse)
        let frames = render([SyntheticTouch.tapPath(id: 1, at: ends.from),
                             SyntheticTouch.linePath(id: 2, from: ends.from, to: ends.to, start: 0.9)])
        let engine = makeEngine(enabled: [.oneFingerTap, .tapThenSwipeLeft, .oneFingerSwipeLeft])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .oneFingerSwipeLeft])
    }

    func testTapThenHoldReleasesTheTapFirst() {
        let spot = Point(0.5, 0.8)
        let frames = render([SyntheticTouch.tapPath(id: 1, at: spot),
                             SyntheticTouch.holdPath(id: 2, at: spot, start: 0.18, duration: 0.7)])
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap, .oneFingerHold])
        XCTAssertEqual(kinds(drive(engine, frames)), [.oneFingerTap, .oneFingerHold])
    }
}
