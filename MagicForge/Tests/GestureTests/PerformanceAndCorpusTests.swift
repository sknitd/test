import XCTest
import MFCore
@testable import MFGestures

final class PerformanceAndCorpusTests: XCTestCase {
    /// Kinds a user would realistically bind: everything except the one-finger swipes that
    /// overlap native scrolling by definition (`overlapsNativeScrolling`).
    static let corpusKinds: [GestureKind] = rawKinds.filter { !$0.overlapsNativeScrolling }

    func testProcessTimePerFrame() {
        // ~100k frames: hand noise (resting fingers, scrolling, palms, blips) mixed with
        // deliberate gestures, replayed back to back.
        var base = SyntheticTouch.render(SyntheticTouch.noisePaths(seed: 11, duration: 60), startTime: 0)
        var cursor = (base.last?.timestamp ?? 0) + 1
        for kind in rawKinds {
            let segment = SyntheticTouch.frames(for: kind, startTime: cursor)
            base += segment
            cursor = (segment.last?.timestamp ?? cursor) + 0.7
        }
        let span = cursor + 1
        var frames: [TouchFrame] = []
        frames.reserveCapacity(101_000)
        var lap = 0.0
        while frames.count < 100_000 {
            for frame in base {
                var shifted = frame
                shifted.timestamp += lap
                frames.append(shifted)
            }
            lap += span
        }
        let contacts = frames.reduce(0) { $0 + $1.contacts.count }

        let engine = makeEngine()
        var emitted = 0
        let started = ProcessInfo.processInfo.systemUptime
        for frame in frames {
            emitted += engine.process(frame).count
            if let deadline = engine.nextDeadline, deadline <= frame.timestamp { emitted += engine.advance(to: deadline).count }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let perFrameMicroseconds = elapsed / Double(frames.count) * 1_000_000
        print(String(format: "[MFGestures performance] %d frames, %.2f contacts/frame, %d events, "
                        + "%.3f µs per process() call (%.1f ms total)",
                     frames.count, Double(contacts) / Double(frames.count), emitted, perFrameMicroseconds,
                     elapsed * 1000))
        XCTAssertGreaterThan(emitted, 0)
        // Very generous sanity bound (a frame arrives every ~10,000 µs).
        XCTAssertLessThan(perFrameMicroseconds, 500)
    }

    func testFalseActivationsOnNoiseCorpus() {
        var totalFrames = 0, totalSeconds = 0.0, activations = 0
        var byKind: [GestureKind: Int] = [:]
        for seed in UInt64(1)...10 {
            let duration = 60.0
            let frames = SyntheticTouch.render(SyntheticTouch.noisePaths(seed: seed, duration: duration), startTime: 100)
            totalFrames += frames.count
            totalSeconds += duration
            let engine = makeEngine(enabled: PerformanceAndCorpusTests.corpusKinds)
            for event in drive(engine, frames) {
                activations += 1
                byKind[event.kind, default: 0] += 1
            }
        }
        let breakdown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        print(String(format: "[MFGestures false activations] %d in %.0f s of synthetic noise (%d frames): %.2f per minute %@",
                     activations, totalSeconds, totalFrames, Double(activations) / totalSeconds * 60,
                     breakdown.isEmpty ? "" : "[" + breakdown.joined(separator: ", ") + "]"))
        // The corpus contains no deliberate gesture. Sanity bound only; the printed number is the result.
        XCTAssertLessThanOrEqual(Double(activations) / totalSeconds * 60, 3)
    }

    /// The same corpus as seen through an adapter that reports NO contact sizes: palm rejection
    /// and flat-contact classification are unavailable, so resting fingers and palms can only be
    /// told apart by time and movement. Reported for information; this is the hard case.
    func testFalseActivationsWithoutContactSizes() {
        var totalSeconds = 0.0, activations = 0
        var byKind: [GestureKind: Int] = [:]
        for seed in UInt64(1)...10 {
            var frames = SyntheticTouch.render(SyntheticTouch.noisePaths(seed: seed, duration: 60), startTime: 100)
            for frame in frames.indices {
                for contact in frames[frame].contacts.indices {
                    frames[frame].contacts[contact].size = 0
                    frames[frame].contacts[contact].majorAxis = 0
                    frames[frame].contacts[contact].minorAxis = 0
                }
            }
            totalSeconds += 60
            for event in drive(makeEngine(enabled: PerformanceAndCorpusTests.corpusKinds), frames) {
                activations += 1
                byKind[event.kind, default: 0] += 1
            }
        }
        let breakdown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        print(String(format: "[MFGestures false activations, sizes unknown] %d in %.0f s: %.2f per minute [%@]",
                     activations, totalSeconds, Double(activations) / totalSeconds * 60,
                     breakdown.joined(separator: ", ")))
        XCTAssertFalse(byKind.keys.contains { $0.category == .fallback })
    }
}
