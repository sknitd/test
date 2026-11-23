import XCTest
import MFCore
@testable import MFGestures

final class FalsePositiveTests: XCTestCase {
    static let tapKinds: Set<GestureKind> = [.oneFingerTap, .oneFingerDoubleTap, .twoFingerTap, .twoFingerDoubleTap,
                                             .threeFingerTap, .cornerTapTopLeft, .cornerTapTopRight,
                                             .cornerTapBottomLeft, .cornerTapBottomRight, .centerTap]
    static let holdKinds: Set<GestureKind> = [.oneFingerHold, .twoFingerHold, .threeFingerHold]

    func testRestingFingersEmitNothing() {
        let paths = [SyntheticTouch.restingPath(id: 1, at: Point(0.15, 0.5), duration: 6),
                     SyntheticTouch.restingPath(id: 2, at: Point(0.85, 0.45), start: 0.4, duration: 5),
                     SyntheticTouch.restingPath(id: 3, at: Point(0.5, 0.3), start: 2.0, duration: 2.5)]
        let engine = makeEngine()
        var events: [GestureEvent] = []
        var maxResting = 0
        for frame in render(paths) {
            events += engine.process(frame)
            maxResting = max(maxResting, engine.liveState.restingFingerCount)
        }
        XCTAssertEqual(kinds(events), [])
        XCTAssertEqual(maxResting, 3)
        XCTAssertNil(engine.nextDeadline)
    }

    func testTapByNewFingerWhileOthersRest() {
        let paths = [SyntheticTouch.restingPath(id: 1, at: Point(0.15, 0.5), duration: 4),
                     SyntheticTouch.restingPath(id: 2, at: Point(0.85, 0.45), start: 0.3, duration: 3.5),
                     SyntheticTouch.tapPath(id: 3, at: Point(0.5, 0.8), start: 2.0)]
        let events = drive(makeEngine(), render(paths))
        XCTAssertEqual(kinds(events), [.oneFingerTap])
        XCTAssertEqual(events[0].fingerCount, 1)
    }

    func testTwoFingerTapWhileOneFingerRests() {
        let paths = [SyntheticTouch.restingPath(id: 1, at: Point(0.15, 0.5), duration: 4),
                     SyntheticTouch.tapPath(id: 2, at: Point(0.4, 0.7), start: 2.0),
                     SyntheticTouch.tapPath(id: 3, at: Point(0.64, 0.7), start: 2.0)]
        let events = drive(makeEngine(), render(paths))
        XCTAssertEqual(kinds(events), [.twoFingerTap])
        XCTAssertEqual(events[0].fingerCount, 2)
    }

    func testSwipeWhileTwoFingersRest() {
        let swipe = SyntheticTouch.paths(for: .oneFingerSwipeUp).map { path -> SyntheticTouch.ContactPath in
            var moved = path; moved.id = 9; moved.start = 1.5; return moved
        }
        let paths = [SyntheticTouch.restingPath(id: 1, at: Point(0.12, 0.5), duration: 3),
                     SyntheticTouch.restingPath(id: 2, at: Point(0.88, 0.5), duration: 3)] + swipe
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [.oneFingerSwipeUp])
    }

    func testFingertipSizedStillFingerDoesNotBlockATapByAnotherFinger() {
        // The still finger is too small to be classified by size and has only been down
        // 0.6 s (not yet "resting" by duration); the late tap demotes it to resting.
        let paths = [SyntheticTouch.holdPath(id: 1, at: Point(0.2, 0.5), duration: 2, size: 0.6),
                     SyntheticTouch.tapPath(id: 2, at: Point(0.5, 0.8), start: 0.6)]
        let engine = makeEngine(enabled: [.oneFingerTap, .twoFingerTap])
        XCTAssertEqual(kinds(drive(engine, render(paths))), [.oneFingerTap])
    }

    func testLongStillFingertipBecomesRestingByDuration() {
        let engine = makeEngine(enabled: [.oneFingerTap])
        var restingSeenAt: TimeInterval?
        for frame in render([SyntheticTouch.holdPath(at: Point(0.3, 0.5), duration: 2.0)], at: 10) {
            _ = engine.process(frame)
            if restingSeenAt == nil && engine.liveState.restingFingerCount == 1 { restingSeenAt = frame.timestamp }
        }
        XCTAssertEqual(restingSeenAt ?? 0, 10 + engine.config.restingFingerDuration, accuracy: 0.012)
    }

    func testRestingFingerThatStartsMovingStaysIgnored() {
        let rest = SyntheticTouch.restingPath(id: 1, at: Point(0.5, 0.3), duration: 2)
        let path = SyntheticTouch.ContactPath(id: 1, start: 0, duration: 2.3, size: 1.3) { progress in
            let elapsed = progress * 2.3
            if elapsed <= 2 { return rest.position(elapsed / 2) }
            let end = rest.position(1)
            return Point(end.x, end.y + 0.4 * (elapsed - 2) / 0.3)
        }
        XCTAssertEqual(kinds(drive(makeEngine(), render([path]))), [])
    }

    func testSlowDriftEmitsNothing() {
        // 10 mm/s for 2.5 s: too slow for a swipe, too much movement for a tap or hold.
        let drift = SyntheticTouch.slowDriftPath(from: Point(0.5, 0.3), to: Point(0.5, 0.578), duration: 2.5)
        XCTAssertEqual(kinds(drive(makeEngine(), render([drift]))), [])
        let sideways = SyntheticTouch.slowDriftPath(from: Point(0.2, 0.5), to: Point(0.6, 0.52), duration: 2.0)
        XCTAssertEqual(kinds(drive(makeEngine(), render([sideways]))), [])
    }

    func testPalmContactsAreIgnored() {
        let engine = makeEngine()
        // A palm that taps, holds and slides produces nothing.
        XCTAssertEqual(kinds(drive(engine, render([SyntheticTouch.palmPath(id: 1, duration: 0.08)]))), [])
        XCTAssertEqual(kinds(drive(engine, render([SyntheticTouch.palmPath(id: 1, duration: 1.5)], at: 20))), [])
        let sliding = SyntheticTouch.linePath(id: 1, from: Point(0.5, 0.2), to: Point(0.5, 0.7), size: 2.8)
        XCTAssertEqual(kinds(drive(engine, render([sliding], at: 30))), [])
        // A palm lying on the rear does not stop a fingertip tap, and is not counted as a finger.
        let paths = [SyntheticTouch.palmPath(id: 1, duration: 2), SyntheticTouch.tapPath(id: 2, at: Point(0.5, 0.8), start: 1)]
        let events = drive(engine, render(paths, at: 40))
        XCTAssertEqual(kinds(events), [.oneFingerTap])
    }

    func testContactGrowingIntoAPalmCancelsItsGesture() {
        var frames = SyntheticTouch.frames(for: .oneFingerSwipeUp, startTime: 10)
        for index in frames.indices where index >= 4 {
            for contact in frames[index].contacts.indices { frames[index].contacts[contact].size = 2.9 }
        }
        XCTAssertEqual(kinds(drive(makeEngine(), frames)), [])
    }

    func testPalmRejectionIsOffWhenSizesAreUnknown() {
        var frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        for index in frames.indices {
            for contact in frames[index].contacts.indices { frames[index].contacts[contact].size = 0 }
        }
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), frames)), [.oneFingerTap])
    }

    func testLongScrollLikeMotionEmitsNoTapsOrHolds() {
        var unwanted = 0, swipes = 0
        for seed in UInt64(1)...4 {
            let frames = SyntheticTouch.render(SyntheticTouch.scrollPaths(seed: seed, duration: 45), startTime: 10)
            XCTAssertGreaterThan(frames.count, 1000)
            for event in drive(makeEngine(), frames) {
                if FalsePositiveTests.tapKinds.contains(event.kind) || FalsePositiveTests.holdKinds.contains(event.kind) {
                    unwanted += 1
                } else {
                    swipes += 1
                    // Scroll strokes can only ever look like the (opt-in) one-finger swipes.
                    XCTAssertTrue(event.kind == .oneFingerSwipeUp || event.kind == .oneFingerSwipeDown, "\(event.kind)")
                }
            }
        }
        XCTAssertEqual(unwanted, 0)
        XCTAssertGreaterThan(swipes, 0)
    }

    // MARK: Physical clicks

    func testPhysicalClickSuppressesImmediateTap() {
        let touch = SyntheticTouch.physicalClickTouch(startTime: 10)
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), touch.frames)), [.oneFingerTap])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), touch.frames, clicks: [touch.clickTime])), [])
    }

    func testPhysicalClickRetractsPendingTap() throws {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        let frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        XCTAssertTrue(drive(engine, frames, settle: false).isEmpty)
        XCTAssertNotNil(engine.nextDeadline)
        engine.notePhysicalClick(at: try XCTUnwrap(frames.last?.timestamp) + 0.05)   // click reported after the lift
        XCTAssertNil(engine.nextDeadline)
        XCTAssertTrue(engine.advance(to: 11).isEmpty)
    }

    func testTapShortlyAfterAClickIsSuppressedAndLaterTapIsNot() {
        let engine = makeEngine(enabled: [.oneFingerTap])
        engine.notePhysicalClick(at: 10)
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerTap, startTime: 10.1))), [])
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerTap, startTime: 10.6))), [.oneFingerTap])
    }

    func testClickAndHoldIsNotATouchHold() {
        let frames = SyntheticTouch.frames(for: .oneFingerHold, startTime: 10)
        XCTAssertEqual(kinds(drive(makeEngine(), frames, clicks: [10.08])), [])
    }
}
