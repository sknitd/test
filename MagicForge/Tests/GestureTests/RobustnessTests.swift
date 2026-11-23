import XCTest
import MFCore
@testable import MFGestures

final class RobustnessTests: XCTestCase {
    // MARK: Contact interruption

    func testFrameGapDuringSwipeCancelsInsteadOfEmitting() {
        let frames = SyntheticTouch.frames(for: .oneFingerSwipeUp, startTime: 10)
        let interrupted = SyntheticTouch.droppingFrames(frames, from: 10.03, to: 10.16)
        XCTAssertLessThan(interrupted.count, frames.count)
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, interrupted)), [])
        // The next gesture is recognized normally.
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerSwipeUp, startTime: 12))),
                       [.oneFingerSwipeUp])
    }

    func testFrameGapDuringHoldCancels() {
        let frames = SyntheticTouch.frames(for: .oneFingerHold, startTime: 10)
        let interrupted = SyntheticTouch.droppingFrames(frames, from: 10.2, to: 10.45)
        let engine = makeEngine()
        var events: [GestureEvent] = []
        for frame in interrupted { events += engine.process(frame) }
        XCTAssertEqual(kinds(events), [])
    }

    func testStreamThatStopsWhileTouchingCancelsOnAdvance() {
        let frames = SyntheticTouch.frames(for: .oneFingerHold, startTime: 10).filter { $0.timestamp < 10.2 }
        let engine = makeEngine()
        var events: [GestureEvent] = []
        for frame in frames { events += engine.process(frame) }
        XCTAssertNotNil(engine.nextDeadline)
        events += engine.advance(to: 10.5)     // 300 ms after the last frame: stale
        XCTAssertEqual(kinds(events), [])
        XCTAssertNil(engine.nextDeadline)
        XCTAssertEqual(engine.liveState.activeFingerCount, 0)
    }

    func testContactThatSurvivesAGapCannotTapOrHold() {
        // A finger is down, the stream drops out, and the finger is still there afterwards.
        let frames = render([SyntheticTouch.holdPath(at: Point(0.5, 0.8), duration: 1.0)], at: 10)
        let interrupted = SyntheticTouch.droppingFrames(frames, from: 10.05, to: 10.3)
        XCTAssertEqual(kinds(drive(makeEngine(), interrupted)), [])
    }

    func testCancelledContactPhaseEmitsNothing() {
        var frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        let last = frames.count - 1
        frames[last].contacts[0].phase = .cancelled
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), frames)), [])
    }

    func testPendingTapSurvivesALaterInterruption() {
        // Tap, then a second touch whose stream breaks: the completed tap is still a tap.
        let spot = Point(0.5, 0.8)
        let frames = render([SyntheticTouch.tapPath(id: 1, at: spot),
                             SyntheticTouch.holdPath(id: 2, at: spot, start: 0.18, duration: 0.5)], at: 10)
        let interrupted = SyntheticTouch.droppingFrames(frames, from: 10.22, to: 10.5)
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap])
        XCTAssertEqual(kinds(drive(engine, interrupted)), [.oneFingerTap])
    }

    func testTimestampsGoingBackwardsResetTheEngine() {
        let engine = makeEngine(enabled: [.oneFingerTap])
        let half = SyntheticTouch.frames(for: .oneFingerTap, startTime: 100).prefix(3)
        for frame in half { _ = engine.process(frame) }
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerTap, startTime: 5))), [.oneFingerTap])
    }

    // MARK: Rapid repetition and cooldown

    func testRapidRepeatedGesturesAreAllRecognized() {
        let spot = Point(0.5, 0.8)
        let taps = (0..<6).map { SyntheticTouch.tapPath(id: $0 + 1, at: spot, start: Double($0) * 0.25) }
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap]), render(taps))),
                       Array(repeating: .oneFingerTap, count: 6))
        var swipes: [TouchFrame] = []
        for index in 0..<5 {
            let kind: GestureKind = index % 2 == 0 ? .twoFingerSwipeLeft : .twoFingerSwipeRight
            swipes += SyntheticTouch.frames(for: kind, startTime: 3 + Double(index) * 0.3)
        }
        XCTAssertEqual(kinds(drive(makeEngine(), swipes)),
                       [.twoFingerSwipeLeft, .twoFingerSwipeRight, .twoFingerSwipeLeft, .twoFingerSwipeRight,
                        .twoFingerSwipeLeft])
    }

    func testCooldownDropsSameKindRepeatedTooQuickly() {
        let spot = Point(0.5, 0.8)
        // Six 44 ms taps, one every 110 ms: closer together than the 180 ms cooldown.
        let taps = (0..<6).map { SyntheticTouch.tapPath(id: $0 + 1, at: spot, start: Double($0) * 0.11, duration: 0.044) }
        let frames = render(taps)
        let events = drive(makeEngine(enabled: [.oneFingerTap]), frames)
        XCTAssertEqual(events.count, 3)
        for (previous, next) in zip(events, events.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.timestamp - previous.timestamp, 0.18)
        }
        let noCooldown = makeEngine(enabled: [.oneFingerTap]) { $0.cooldown = 0 }
        XCTAssertEqual(drive(noCooldown, frames).count, 6)
    }

    func testCooldownIsPerKind() {
        let frames = render([SyntheticTouch.tapPath(id: 1, at: Point(0.5, 0.8), duration: 0.05),
                             SyntheticTouch.tapPath(id: 2, at: Point(0.38, 0.6), start: 0.09, duration: 0.05),
                             SyntheticTouch.tapPath(id: 3, at: Point(0.62, 0.6), start: 0.09, duration: 0.05)])
        XCTAssertEqual(kinds(drive(makeEngine(enabled: [.oneFingerTap, .twoFingerTap]), frames)),
                       [.oneFingerTap, .twoFingerTap])
    }

    // MARK: Multi-contact transitions

    func testOneToTwoToOneFingersEmitsNothingAndRecovers() {
        // A swipe that would fire at ~130 ms, but a second finger lands at 110 ms and leaves again.
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.4, 0.3), to: Point(0.4, 0.7), duration: 0.3),
                     SyntheticTouch.tapPath(id: 2, at: Point(0.7, 0.5), start: 0.11, duration: 0.09)]
        let engine = makeEngine()
        XCTAssertEqual(kinds(drive(engine, render(paths))), [])
        XCTAssertEqual(engine.liveState.phase, "idle")
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .threeFingerTap, startTime: 20))), [.threeFingerTap])
    }

    func testTwoToOneFingerLiftBeforeThresholdEmitsNothing() {
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.38, 0.3), to: Point(0.38, 0.7), duration: 0.22),
                     SyntheticTouch.ContactPath(id: 2, start: 0, duration: 0.06) { _ in Point(0.62, 0.3) }]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [])
    }

    func testSecondFingerLandingAfterSwipeFiredDoesNotFireAgain() {
        let paths = [SyntheticTouch.linePath(id: 1, from: Point(0.4, 0.2), to: Point(0.4, 0.8), duration: 0.4),
                     SyntheticTouch.linePath(id: 2, from: Point(0.6, 0.5), to: Point(0.6, 0.8), start: 0.25, duration: 0.15)]
        XCTAssertEqual(kinds(drive(makeEngine(), render(paths))), [.oneFingerSwipeUp])
    }

    func testFingerSwapInOneFrameIsTwoSeparateTouches() {
        // Finger 1 vanishes in the same frame finger 2 appears (no .ended sample).
        let frames = render([SyntheticTouch.tapPath(id: 1, at: Point(0.38, 0.6), duration: 0.066),
                             SyntheticTouch.tapPath(id: 2, at: Point(0.62, 0.6), start: 0.066, duration: 0.066)],
                            endStyle: .disappear)
        let events = drive(makeEngine(enabled: [.oneFingerTap, .twoFingerTap]) { $0.cooldown = 0 }, frames)
        XCTAssertEqual(kinds(events), [.oneFingerTap, .oneFingerTap])
    }

    // MARK: enabledKinds

    func testEnabledKindsFiltering() {
        let nothing = makeEngine(enabled: [])
        for kind in rawKinds {
            XCTAssertEqual(kinds(drive(nothing, SyntheticTouch.frames(for: kind, startTime: 5))), [], "\(kind)")
            XCTAssertNil(nothing.nextDeadline)
            nothing.reset()
        }
        let swipesOnly = makeEngine(enabled: [.twoFingerSwipeLeft])
        XCTAssertEqual(kinds(drive(swipesOnly, SyntheticTouch.frames(for: .twoFingerTap, startTime: 1))), [])
        XCTAssertEqual(kinds(drive(swipesOnly, SyntheticTouch.frames(for: .twoFingerSwipeRight, startTime: 2))), [])
        XCTAssertEqual(kinds(drive(swipesOnly, SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 3))),
                       [.twoFingerSwipeLeft])
        // The default enables every raw-contact kind and no fallback kind.
        XCTAssertEqual(GestureEngine().enabledKinds, Set(rawKinds))
    }

    func testDoubleTapOnlyEnabledEmitsNothingForASingleTap() {
        let engine = makeEngine(enabled: [.oneFingerDoubleTap])
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerTap, startTime: 1), settle: false)), [])
        XCTAssertNil(engine.nextDeadline)      // nothing could be emitted by advance(to:)
        XCTAssertEqual(kinds(drive(engine, SyntheticTouch.frames(for: .oneFingerDoubleTap, startTime: 5))),
                       [.oneFingerDoubleTap])
    }

    // MARK: nextDeadline / liveState

    func testNextDeadlineLifecycle() throws {
        let engine = makeEngine(enabled: [.oneFingerTap, .oneFingerDoubleTap, .oneFingerHold])
        XCTAssertNil(engine.nextDeadline)
        XCTAssertTrue(engine.advance(to: 5).isEmpty)
        let frames = SyntheticTouch.frames(for: .oneFingerTap, startTime: 10)
        _ = engine.process(frames[0])
        // Finger down and still: the hold deadline.
        XCTAssertEqual(try XCTUnwrap(engine.nextDeadline), 10 + 0.5, accuracy: 1e-9)
        for frame in frames.dropFirst() { XCTAssertTrue(engine.process(frame).isEmpty) }
        // Lifted: the pending single tap deadline.
        let lift = try XCTUnwrap(frames.last?.timestamp)
        XCTAssertEqual(try XCTUnwrap(engine.nextDeadline), lift + 0.30, accuracy: 1e-9)
        // A second touch claims the pending tap; while it can still become a double tap the
        // deadline is the end of its tap window.
        let second = SyntheticTouch.frames(for: .oneFingerHold, startTime: lift + 0.1)
        _ = engine.process(second[0])
        XCTAssertEqual(try XCTUnwrap(engine.nextDeadline), lift + 0.1 + engine.config.tapMaxDuration, accuracy: 1e-9)
        var events: [GestureEvent] = []
        for frame in second.dropFirst() {
            while let deadline = engine.nextDeadline, deadline < frame.timestamp { events += engine.advance(to: deadline) }
            events += engine.process(frame)
        }
        XCTAssertEqual(kinds(events), [.oneFingerTap, .oneFingerHold])
        XCTAssertNil(engine.nextDeadline)
    }

    func testNextDeadlineDisappearsWhenFingerMoves() {
        let engine = makeEngine(enabled: [.oneFingerHold])
        let frames = SyntheticTouch.frames(for: .oneFingerSwipeUp, startTime: 10)
        _ = engine.process(frames[0])
        XCTAssertNotNil(engine.nextDeadline)
        for frame in frames.dropFirst().prefix(12) { _ = engine.process(frame) }
        XCTAssertNil(engine.nextDeadline)
    }

    func testLiveStateTracksCandidates() {
        let engine = makeEngine()
        XCTAssertEqual(engine.liveState, RecognizerLiveState())
        var phases: [String] = []
        var candidates: [GestureKind] = []
        for frame in SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 10) {
            _ = engine.process(frame)
            let live = engine.liveState
            if phases.last != live.phase { phases.append(live.phase) }
            if let candidate = live.candidate, candidates.last != candidate { candidates.append(candidate) }
            XCTAssertGreaterThanOrEqual(live.candidateConfidence, 0)
            XCTAssertLessThanOrEqual(live.candidateConfidence, 1)
            if live.phase == "landing" || live.phase == "tracking" { XCTAssertEqual(live.activeFingerCount, 2) }
        }
        XCTAssertEqual(phases, ["landing", "tracking", "recognized", "idle"])
        XCTAssertEqual(candidates.first, .twoFingerTap)
        XCTAssertEqual(candidates.last, .twoFingerSwipeLeft)
        XCTAssertEqual(engine.liveState.activeFingerCount, 0)

        engine.reset()
        var holdCandidateSeen = false
        for frame in SyntheticTouch.frames(for: .oneFingerHold, startTime: 10) {
            _ = engine.process(frame)
            if engine.liveState.phase == "tracking" && engine.liveState.candidate == .oneFingerHold { holdCandidateSeen = true }
        }
        XCTAssertTrue(holdCandidateSeen)
    }
}
