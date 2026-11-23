import XCTest
import MFCore
@testable import MFGestures

final class SequenceMatcherTests: XCTestCase {
    typealias Resolution = SequenceMatcher.Resolution

    func event(_ kind: GestureKind, _ time: TimeInterval) -> GestureEvent {
        GestureEvent(kind: kind, timestamp: time, confidence: 1, fingerCount: kind.fingerCount)
    }

    func testUnrelatedGesturePassesStraightThrough() {
        let matcher = SequenceMatcher(sequences: [[.twoFingerTap, .twoFingerSwipeLeft]])
        let tap = event(.oneFingerTap, 1)
        XCTAssertEqual(matcher.feed(tap), [.single(tap)])
        XCTAssertFalse(matcher.isHolding)
        XCTAssertNil(matcher.nextDeadline)
        XCTAssertFalse(matcher.delaysSingle(.oneFingerTap))
        XCTAssertTrue(matcher.delaysSingle(.twoFingerTap))
        XCTAssertFalse(matcher.delaysSingle(.twoFingerSwipeLeft))
    }

    func testSequenceCompletesInsideWindow() {
        let matcher = SequenceMatcher(sequences: [[.twoFingerTap, .twoFingerSwipeLeft]], window: 0.6)
        XCTAssertEqual(matcher.feed(event(.twoFingerTap, 1)), [])
        XCTAssertTrue(matcher.isHolding)
        XCTAssertEqual(matcher.nextDeadline, 1.6)
        let swipe = event(.twoFingerSwipeLeft, 1.5)
        XCTAssertEqual(matcher.feed(swipe), [.sequence([.twoFingerTap, .twoFingerSwipeLeft], completedBy: swipe)])
        XCTAssertFalse(matcher.isHolding)
    }

    func testWindowExpiryReleasesHeldEventAsSingle() {
        let matcher = SequenceMatcher(sequences: [[.twoFingerTap, .twoFingerSwipeLeft]], window: 0.6)
        let tap = event(.twoFingerTap, 1)
        XCTAssertEqual(matcher.feed(tap), [])
        XCTAssertEqual(matcher.advance(to: 1.59), [])
        XCTAssertEqual(matcher.advance(to: 1.6), [.single(tap)])
        XCTAssertEqual(matcher.advance(to: 5), [])
        // Without advance(): a late second event first releases the stale one.
        XCTAssertEqual(matcher.feed(tap), [])
        let late = event(.twoFingerSwipeLeft, 1.7)
        XCTAssertEqual(matcher.feed(late), [.single(tap), .single(late)])
    }

    func testMismatchReleasesInOrderAndRestarts() {
        let matcher = SequenceMatcher(sequences: [[.twoFingerTap, .twoFingerSwipeLeft], [.threeFingerTap, .pinchIn]])
        let a = event(.twoFingerTap, 1), b = event(.threeFingerTap, 1.2), c = event(.pinchIn, 1.4)
        XCTAssertEqual(matcher.feed(a), [])
        XCTAssertEqual(matcher.feed(b), [.single(a)])          // b starts another sequence and is now held
        XCTAssertEqual(matcher.feed(c), [.sequence([.threeFingerTap, .pinchIn], completedBy: c)])
    }

    func testRepeatedFirstElementStillMatches() {
        let matcher = SequenceMatcher(sequences: [[.oneFingerTap, .twoFingerTap]])
        let a1 = event(.oneFingerTap, 1), a2 = event(.oneFingerTap, 1.3), b = event(.twoFingerTap, 1.6)
        XCTAssertEqual(matcher.feed(a1), [])
        XCTAssertEqual(matcher.feed(a2), [.single(a1)])
        XCTAssertEqual(matcher.feed(b), [.sequence([.oneFingerTap, .twoFingerTap], completedBy: b)])
    }

    func testPrefixSequenceIsDeferredAndLongestMatchWins() {
        let short: [GestureKind] = [.twoFingerTap, .twoFingerTap]
        let long: [GestureKind] = [.twoFingerTap, .twoFingerTap, .twoFingerSwipeUp]
        let matcher = SequenceMatcher(sequences: [short, long], window: 0.6)
        XCTAssertTrue(matcher.isProperPrefix(short))
        XCTAssertTrue(matcher.isComplete(short))
        XCTAssertFalse(matcher.isProperPrefix(long))

        // Continues to the longer sequence.
        let t1 = event(.twoFingerTap, 1), t2 = event(.twoFingerTap, 1.3), s = event(.twoFingerSwipeUp, 1.7)
        XCTAssertEqual(matcher.feed(t1), [])
        XCTAssertEqual(matcher.feed(t2), [])                      // complete, but may still grow: deferred
        XCTAssertEqual(matcher.nextDeadline, 1.9)
        XCTAssertEqual(matcher.feed(s), [.sequence(long, completedBy: s)])

        // Window elapses: the shorter sequence fires.
        XCTAssertEqual(matcher.feed(event(.twoFingerTap, 5)), [])
        let second = event(.twoFingerTap, 5.2)
        XCTAssertEqual(matcher.feed(second), [])
        XCTAssertEqual(matcher.advance(to: 5.8), [.sequence(short, completedBy: second)])

        // A different gesture arrives: the shorter sequence fires first, then the newcomer.
        XCTAssertEqual(matcher.feed(event(.twoFingerTap, 9)), [])
        let pair = event(.twoFingerTap, 9.2)
        XCTAssertEqual(matcher.feed(pair), [])
        let other = event(.pinchOut, 9.4)
        XCTAssertEqual(matcher.feed(other), [.sequence(short, completedBy: pair), .single(other)])
    }

    func testEveryEventComesBackExactlyOnce() {
        let sequences: [[GestureKind]] = [[.oneFingerTap, .twoFingerTap], [.oneFingerTap, .twoFingerTap, .threeFingerTap, .pinchIn],
                                          [.twoFingerTap, .twoFingerTap]]
        let matcher = SequenceMatcher(sequences: sequences, window: 0.5)
        var generator = SyntheticTouch.LCG(seed: 42)
        let alphabet: [GestureKind] = [.oneFingerTap, .twoFingerTap, .threeFingerTap, .pinchIn]
        var time = 0.0
        var fed = 0, returned = 0
        for _ in 0..<2000 {
            time += generator.range(0.05, 0.9)
            for resolution in matcher.advance(to: time - 0.01) + matcher.feed(event(alphabet[generator.int(4)], time)) {
                switch resolution {
                case .single: returned += 1
                case .sequence(let kinds, _):
                    XCTAssertTrue(sequences.contains(kinds))
                    returned += kinds.count
                }
            }
            fed += 1
            XCTAssertLessThanOrEqual(matcher.held.count, SequenceMatcher.maximumLength)
        }
        for resolution in matcher.advance(to: time + 10) {
            if case .sequence(let kinds, _) = resolution { returned += kinds.count } else { returned += 1 }
        }
        XCTAssertEqual(fed, returned)
        XCTAssertFalse(matcher.isHolding)
    }

    func testInvalidSequencesAreIgnoredAndTriggersInitializer() {
        let matcher = SequenceMatcher(sequences: [[.oneFingerTap], [], [.oneFingerTap, .twoFingerTap],
                                                  [.oneFingerTap, .twoFingerTap],
                                                  [.pinchIn, .pinchIn, .pinchIn, .pinchIn, .pinchIn]])
        XCTAssertEqual(matcher.sequences, [[.oneFingerTap, .twoFingerTap]])
        var config = RecognizerConfig()
        config.sequenceWindow = 0.4
        let fromTriggers = SequenceMatcher(triggers: [.single(.oneFingerTap), .sequence([.pinchIn, .pinchOut])], config: config)
        XCTAssertEqual(fromTriggers.sequences, [[.pinchIn, .pinchOut]])
        XCTAssertEqual(fromTriggers.window, 0.4)
        XCTAssertEqual(fromTriggers.feed(event(.pinchIn, 1)), [])
        fromTriggers.sequences = [[.oneFingerTap]]          // invalid: cleaned, and held events are dropped
        XCTAssertEqual(fromTriggers.sequences, [])
        XCTAssertFalse(fromTriggers.isHolding)
        fromTriggers.reset()
    }

    func testEngineOutputDrivesTheMatcher() {
        let engine = makeEngine(enabled: [.twoFingerTap, .twoFingerSwipeLeft])
        let matcher = SequenceMatcher(sequences: [[.twoFingerTap, .twoFingerSwipeLeft]], window: engine.config.sequenceWindow)
        let frames = SyntheticTouch.frames(for: .twoFingerTap, startTime: 10)
            + SyntheticTouch.frames(for: .twoFingerSwipeLeft, startTime: 10.3)
        var resolutions: [Resolution] = []
        for gesture in drive(engine, frames) { resolutions += matcher.feed(gesture) }
        XCTAssertEqual(resolutions.count, 1)
        if case .sequence(let kinds, _)? = resolutions.first {
            XCTAssertEqual(kinds, [.twoFingerTap, .twoFingerSwipeLeft])
        } else {
            XCTFail("expected a sequence")
        }
    }
}
