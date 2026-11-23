import XCTest
import MFCore
@testable import MFGestures

final class RoundTripTests: XCTestCase {
    func testEveryRawKindWithOnlyThatKindEnabled() {
        for kind in rawKinds {
            let engine = makeEngine(enabled: [kind])
            let events = drive(engine, SyntheticTouch.frames(for: kind, startTime: 5))
            XCTAssertEqual(kinds(events), [kind], "only \(kind) enabled")
            if let event = events.first {
                XCTAssertGreaterThanOrEqual(event.confidence, 0.6, "\(kind)")
                XCTAssertLessThanOrEqual(event.confidence, 1.0, "\(kind)")
                XCTAssertEqual(event.fingerCount, kind.fingerCount, "\(kind)")
            }
        }
    }

    func testEveryRawKindWithAllKindsEnabled() {
        for kind in rawKinds {
            let engine = makeEngine()
            let events = drive(engine, SyntheticTouch.frames(for: kind, startTime: 5))
            XCTAssertEqual(kinds(events), expectedWithAllEnabled(kind), "all enabled, stream for \(kind)")
        }
    }

    func testRoundTripWithDisappearingContactsAndOtherFrameRates() {
        for interval in [0.008, 0.011, 0.0125] {
            for kind in rawKinds {
                let engine = makeEngine()
                let frames = SyntheticTouch.render(SyntheticTouch.paths(for: kind), startTime: 100,
                                                   frameInterval: interval, endStyle: .disappear)
                XCTAssertEqual(kinds(drive(engine, frames)), expectedWithAllEnabled(kind),
                               "\(kind) at \(interval)s frames")
            }
        }
    }

    func testFallbackKindsHaveNoSyntheticStream() {
        for kind in GestureKind.allCases where kind.requirement == .pointerEvents {
            XCTAssertTrue(SyntheticTouch.frames(for: kind, startTime: 0).isEmpty)
        }
    }

    func testDemoReelIsRecognized() {
        let engine = makeEngine()
        let frames = SyntheticTouch.demoReel(startTime: 50)
        XCTAssertFalse(frames.isEmpty)
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(previous.timestamp, next.timestamp)
        }
        let events = drive(engine, frames)
        XCTAssertEqual(kinds(events), [.oneFingerTap, .oneFingerDoubleTap, .twoFingerTap, .twoFingerSwipeLeft,
                                       .twoFingerSwipeRight, .pinchOut, .pinchIn, .rotateClockwise,
                                       .threeFingerSwipeUp, .leftEdgeSwipe, .cornerTapTopRight, .oneFingerHold,
                                       .tapThenSwipeRight, .oneFingerHold, .holdThenSwipeDown])
    }

    func testDeterminism() {
        let frames = SyntheticTouch.demoReel(startTime: 3)
            + SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 7, duration: 20), startTime: 40)
        let first = drive(makeEngine(), frames)
        let second = drive(makeEngine(), frames)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        // A reused engine behaves like a new one after reset().
        let engine = makeEngine()
        _ = drive(engine, frames)
        engine.reset()
        XCTAssertEqual(drive(engine, frames), first)
        // Seeded generators are reproducible.
        XCTAssertEqual(SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 7, duration: 5), startTime: 0),
                       SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 7, duration: 5), startTime: 0))
        XCTAssertNotEqual(SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 7, duration: 5), startTime: 0),
                          SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 8, duration: 5), startTime: 0))
    }
}
