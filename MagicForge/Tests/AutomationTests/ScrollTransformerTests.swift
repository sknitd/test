import XCTest
import MFCore
@testable import MFAutomation

final class ScrollTransformerTests: XCTestCase {
    private func settings(_ configure: (inout ScrollSettings) -> Void = { _ in }) -> ScrollSettings {
        var settings = ScrollSettings()
        settings.isEnabled = true
        configure(&settings)
        return settings
    }

    private func sample(_ dx: Double, _ dy: Double, at time: TimeInterval = 10, continuous: Bool = true,
                        magicMouse: Bool = true, momentum: Bool = false) -> ScrollSample {
        ScrollSample(deltaX: dx, deltaY: dy, isContinuous: continuous, isFromMagicMouse: magicMouse, isMomentum: momentum,
                     timestamp: time)
    }

    private func deltas(_ decision: ScrollDecision, file: StaticString = #filePath, line: UInt = #line) -> (x: Double, y: Double) {
        guard case .rewrite(let x, let y) = decision else {
            XCTFail("expected a rewrite, got \(decision)", file: file, line: line)
            return (.nan, .nan)
        }
        return (x, y)
    }

    // MARK: Pass-through

    func testDisabledAlwaysPassesThrough() {
        var transformer = ScrollTransformer()
        var disabled = settings { $0.verticalMultiplier = 3; $0.invertVertical = true; $0.acceleration = 1 }
        disabled.isEnabled = false
        for index in 0..<20 {
            XCTAssertEqual(transformer.decide(sample(3, Double(index), at: Double(index) * 0.01), settings: disabled), .passThrough)
        }
        XCTAssertEqual(transformer, ScrollTransformer(), "no state is kept while disabled")
    }

    func testIdentitySettingsPassThrough() {
        var transformer = ScrollTransformer()
        XCTAssertEqual(transformer.decide(sample(4, -9), settings: settings()), .passThrough)
        XCTAssertEqual(transformer.decide(sample(4, -9, continuous: false), settings: settings()), .passThrough)
        // Smoothing never applies to continuous (pixel) deltas, so it is an identity for them.
        XCTAssertEqual(transformer.decide(sample(4, -9), settings: settings { $0.smoothing = 1 }), .passThrough)
        XCTAssertEqual(transformer.decide(sample(4, -9, momentum: true), settings: settings()), .passThrough)
    }

    func testNonMagicMousePassesThroughWhenRestricted() {
        var transformer = ScrollTransformer()
        let doubled = settings { $0.verticalMultiplier = 2 }
        XCTAssertEqual(transformer.decide(sample(1, 5, magicMouse: false), settings: doubled), .passThrough)
        XCTAssertEqual(transformer, ScrollTransformer(), "other devices do not disturb gesture state")
        let everyDevice = settings { $0.verticalMultiplier = 2; $0.magicMouseOnly = false }
        let out = deltas(transformer.decide(sample(1, 5, magicMouse: false), settings: everyDevice))
        XCTAssertEqual(out.x, 1); XCTAssertEqual(out.y, 10)
    }

    func testZeroDeltaWithMultiplierIsUnchanged() {
        var transformer = ScrollTransformer()
        XCTAssertEqual(transformer.decide(sample(0, 0), settings: settings { $0.verticalMultiplier = 2 }), .passThrough)
    }

    // MARK: Multipliers and inversion

    func testMultipliers() {
        var transformer = ScrollTransformer()
        let scaled = settings { $0.verticalMultiplier = 2.5; $0.horizontalMultiplier = 0.5 }
        let out = deltas(transformer.decide(sample(8, -4), settings: scaled))
        XCTAssertEqual(out.x, 4, accuracy: 1e-12)
        XCTAssertEqual(out.y, -10, accuracy: 1e-12)
        let lines = deltas(transformer.decide(sample(2, 1, at: 20, continuous: false), settings: scaled))
        XCTAssertEqual(lines.x, 1, accuracy: 1e-12)
        XCTAssertEqual(lines.y, 2.5, accuracy: 1e-12)
    }

    func testInversion() {
        var transformer = ScrollTransformer()
        let vertical = deltas(transformer.decide(sample(3, 7), settings: settings { $0.invertVertical = true }))
        XCTAssertEqual(vertical.x, 3); XCTAssertEqual(vertical.y, -7)
        let horizontal = deltas(transformer.decide(sample(3, 7, at: 20), settings: settings { $0.invertHorizontal = true }))
        XCTAssertEqual(horizontal.x, -3); XCTAssertEqual(horizontal.y, 7)
        let both = settings { $0.invertVertical = true; $0.invertHorizontal = true; $0.verticalMultiplier = 2 }
        let out = deltas(transformer.decide(sample(-3, 7, at: 30), settings: both))
        XCTAssertEqual(out.x, 3); XCTAssertEqual(out.y, -14)
    }

    func testOutOfRangeSettingsAreSanitized() {
        var transformer = ScrollTransformer()
        let wild = settings {
            $0.verticalMultiplier = .infinity; $0.horizontalMultiplier = -5; $0.acceleration = .nan
            $0.smoothing = 99; $0.horizontalDeadZone = -.infinity
        }
        // vertical falls back to 1, horizontal clamps to 0, acceleration and dead zone fall back to 0.
        let out = deltas(transformer.decide(sample(6, 6), settings: wild))
        XCTAssertEqual(out.x, 0); XCTAssertEqual(out.y, 6)
        let huge = deltas(transformer.decide(sample(0, 10, at: 20), settings: settings { $0.verticalMultiplier = 1e9 }))
        XCTAssertEqual(huge.y, 200, "multiplier clamps to 20")
    }

    // MARK: Acceleration

    private func acceleratedOutput(interval: TimeInterval, delta: Double = 10, acceleration: Double = 1,
                                   continuous: Bool = true) -> Double {
        var transformer = ScrollTransformer()
        let accelerated = settings { $0.acceleration = acceleration }
        var last = 0.0
        for index in 0..<8 {
            let decision = transformer.decide(sample(0, delta, at: 5 + Double(index) * interval, continuous: continuous),
                                              settings: accelerated)
            if case .rewrite(_, let y) = decision { last = y } else { last = delta }
        }
        return last
    }

    func testAccelerationIsMonotonicInSpeed() {
        let intervals: [TimeInterval] = [0.1, 0.05, 0.03, 0.02, 0.012, 0.008, 0.005]
        let outputs = intervals.map { acceleratedOutput(interval: $0) }
        for (slower, faster) in zip(outputs, outputs.dropFirst()) { XCTAssertGreaterThan(faster, slower) }
        XCTAssertGreaterThan(outputs[0], 10, "acceleration never slows scrolling down")
        // Larger deltas at the same rate are faster too.
        let byDelta = [2.0, 5, 10, 30, 80].map { acceleratedOutput(interval: 0.016, delta: $0) / $0 }
        for (slower, faster) in zip(byDelta, byDelta.dropFirst()) { XCTAssertGreaterThan(faster, slower) }
        // Line-based deltas accelerate as well.
        XCTAssertGreaterThan(acceleratedOutput(interval: 0.01, delta: 1, continuous: false),
                             acceleratedOutput(interval: 0.08, delta: 1, continuous: false))
    }

    func testAccelerationIsMonotonicInStrengthAndBounded() {
        let strengths = [0.0, 0.25, 0.5, 0.75, 1.0].map { acceleratedOutput(interval: 0.01, acceleration: $0) }
        for (weaker, stronger) in zip(strengths, strengths.dropFirst()) { XCTAssertGreaterThan(stronger, weaker) }
        XCTAssertEqual(strengths[0], 10, "acceleration 0 is linear")
        let extreme = acceleratedOutput(interval: 0.0001, delta: 900)
        XCTAssertLessThanOrEqual(extreme, 900 * (1 + ScrollTransformer.maxExtraGain))
        XCTAssertLessThanOrEqual(extreme, ScrollTransformer.maxContinuousDelta)
    }

    func testAccelerationKeepsDirection() {
        var transformer = ScrollTransformer()
        let accelerated = settings { $0.acceleration = 1; $0.invertVertical = true }
        for index in 0..<30 {
            let dy = index % 2 == 0 ? 12.0 : -7.0
            let out = deltas(transformer.decide(sample(3, dy, at: 1 + Double(index) * 0.01), settings: accelerated))
            XCTAssertEqual(out.y.sign, (-dy).sign)
            XCTAssertGreaterThan(out.x, 0)
        }
    }

    // MARK: Momentum

    func testMomentumReusesGestureFactorsAndNeverFlipsSign() {
        var transformer = ScrollTransformer()
        let tuned = settings { $0.acceleration = 0.8; $0.invertVertical = true; $0.verticalMultiplier = 1.5 }
        var lastFingerOutput = 0.0
        var time = 3.0
        for _ in 0..<10 {
            lastFingerOutput = deltas(transformer.decide(sample(0, 20, at: time), settings: tuned)).y
            time += 0.01
        }
        let factor = lastFingerOutput / 20
        XCTAssertLessThan(factor, -1.5, "inverted and accelerated")
        var previous = -Double.infinity
        for step in 0..<40 {
            let input = 20 * pow(0.9, Double(step + 1))
            let out = deltas(transformer.decide(sample(0, input, at: time, momentum: true), settings: tuned)).y
            XCTAssertEqual(out, input * factor, accuracy: 1e-9, "momentum uses the factor the gesture ended with")
            XCTAssertLessThan(out, 0, "sign never flips during the glide")
            XCTAssertGreaterThan(out, previous, "the glide decays smoothly")
            previous = out
            time += 0.016
        }
    }

    func testMomentumIgnoresSettingsChangedMidGlide() {
        var transformer = ScrollTransformer()
        let inverted = settings { $0.invertVertical = true }
        XCTAssertEqual(deltas(transformer.decide(sample(0, 10, at: 1), settings: inverted)).y, -10)
        let changed = settings { $0.verticalMultiplier = 3 }
        XCTAssertEqual(deltas(transformer.decide(sample(0, 8, at: 1.016, momentum: true), settings: changed)).y, -8)
        // The next finger-driven gesture picks up the new settings.
        XCTAssertEqual(deltas(transformer.decide(sample(0, 8, at: 2), settings: changed)).y, 24)
    }

    func testMomentumWithoutGestureUsesPlainFactors() {
        var transformer = ScrollTransformer()
        let tuned = settings { $0.acceleration = 1; $0.verticalMultiplier = 2 }
        XCTAssertEqual(deltas(transformer.decide(sample(0, 50, momentum: true), settings: tuned)).y, 100)
    }

    // MARK: Dead zone

    func testHorizontalDeadZone() {
        var transformer = ScrollTransformer()
        let locked = settings { $0.horizontalDeadZone = 0.5 }
        let suppressed = deltas(transformer.decide(sample(2, 10), settings: locked))
        XCTAssertEqual(suppressed.x, 0); XCTAssertEqual(suppressed.y, 10)
        let negative = deltas(transformer.decide(sample(-4.9, -10, at: 10.01), settings: locked))
        XCTAssertEqual(negative.x, 0); XCTAssertEqual(negative.y, -10)
        // At or beyond the threshold the horizontal delta is kept, so nothing changes.
        XCTAssertEqual(transformer.decide(sample(5, 10, at: 10.02), settings: locked), .passThrough)
        XCTAssertEqual(transformer.decide(sample(9, 1, at: 10.03), settings: locked), .passThrough)
        XCTAssertEqual(transformer.decide(sample(3, 0, at: 10.04), settings: locked), .passThrough)
        // Applies to momentum events of the same gesture as well.
        let glide = deltas(transformer.decide(sample(1, 10, at: 10.05, momentum: true), settings: locked))
        XCTAssertEqual(glide.x, 0); XCTAssertEqual(glide.y, 10)
    }

    // MARK: Smoothing

    func testSmoothingOnlyAffectsLineDeltas() {
        var transformer = ScrollTransformer()
        let smooth = settings { $0.smoothing = 1 }
        let inputs: [Double] = [1, 5, 1, 5, 1, 5, 1, 5]
        var outputs: [Double] = []
        for (index, input) in inputs.enumerated() {
            let decision = transformer.decide(sample(0, input, at: 1 + Double(index) * 0.02, continuous: false), settings: smooth)
            if case .rewrite(_, let y) = decision { outputs.append(y) } else { outputs.append(input) }
        }
        XCTAssertEqual(outputs[0], 1, "an isolated wheel notch is not altered")
        func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }
        XCTAssertLessThan(spread(Array(outputs.suffix(4))), spread(Array(inputs.suffix(4))) / 2)
        XCTAssertTrue(outputs.allSatisfy { $0 > 0 && $0 <= 5 })

        var pixel = ScrollTransformer()
        for (index, input) in inputs.enumerated() {
            XCTAssertEqual(pixel.decide(sample(0, input, at: 1 + Double(index) * 0.02), settings: smooth), .passThrough)
        }
    }

    func testSmoothingNeverOpposesTheInputDirection() {
        var transformer = ScrollTransformer()
        let smooth = settings { $0.smoothing = 1 }
        let inputs: [Double] = [3, 3, 3, -1, -1, 0, 2, -4, 0, 0, 1]
        for (index, input) in inputs.enumerated() {
            let decision = transformer.decide(sample(0, input, at: 1 + Double(index) * 0.02, continuous: false), settings: smooth)
            let output: Double
            if case .rewrite(_, let y) = decision { output = y } else { output = input }
            if input == 0 { XCTAssertEqual(output, 0) } else { XCTAssertEqual(output.sign, input.sign); XCTAssertNotEqual(output, 0) }
        }
    }

    func testGestureGapResetsSmoothingAndSpeed() {
        var transformer = ScrollTransformer()
        let smooth = settings { $0.smoothing = 1 }
        _ = transformer.decide(sample(0, 5, at: 1, continuous: false), settings: smooth)
        _ = transformer.decide(sample(0, 5, at: 1.02, continuous: false), settings: smooth)
        // After a pause the first notch of the new gesture is untouched.
        XCTAssertEqual(transformer.decide(sample(0, 1, at: 2, continuous: false), settings: smooth), .passThrough)
    }

    // MARK: Robustness

    func testNonFiniteSamplesPassThrough() {
        var transformer = ScrollTransformer()
        let tuned = settings { $0.verticalMultiplier = 2; $0.acceleration = 1 }
        XCTAssertEqual(transformer.decide(sample(.nan, 1), settings: tuned), .passThrough)
        XCTAssertEqual(transformer.decide(sample(1, .infinity), settings: tuned), .passThrough)
        XCTAssertEqual(transformer.decide(sample(1, 1, at: .nan), settings: tuned), .passThrough)
        XCTAssertEqual(deltas(transformer.decide(sample(0, 1, at: 5), settings: tuned)).y, 2 * (1 + 3 * 60 / 1560.0), accuracy: 1e-9)
    }

    func testOutputIsAlwaysFiniteAndClamped() {
        var transformer = ScrollTransformer()
        var generator = SystemRandomNumberGenerator()
        let extremes: [Double] = [0, 1e-300, -1e-300, 1, -1, 1e6, -1e6, 1e300, -1e300, .greatestFiniteMagnitude,
                                  -.greatestFiniteMagnitude, .leastNonzeroMagnitude]
        let numbers: [Double] = extremes + [.nan, .infinity, -.infinity]
        var time = 0.0
        for _ in 0..<5000 {
            let tuned = settings {
                $0.verticalMultiplier = numbers.randomElement(using: &generator) ?? 1
                $0.horizontalMultiplier = numbers.randomElement(using: &generator) ?? 1
                $0.acceleration = numbers.randomElement(using: &generator) ?? 0
                $0.smoothing = numbers.randomElement(using: &generator) ?? 0
                $0.horizontalDeadZone = numbers.randomElement(using: &generator) ?? 0
                $0.invertVertical = Bool.random(using: &generator)
                $0.invertHorizontal = Bool.random(using: &generator)
            }
            // Timestamps repeat, jump and go backwards.
            time += [0, 0, 1e-9, 0.01, 0.3, -5, 1e12].randomElement(using: &generator) ?? 0
            let continuous = Bool.random(using: &generator)
            let input = ScrollSample(deltaX: numbers.randomElement(using: &generator) ?? 0,
                                     deltaY: numbers.randomElement(using: &generator) ?? 0, isContinuous: continuous,
                                     isFromMagicMouse: true, isMomentum: Bool.random(using: &generator), timestamp: time)
            if case .rewrite(let x, let y) = transformer.decide(input, settings: tuned) {
                let limit = continuous ? ScrollTransformer.maxContinuousDelta : ScrollTransformer.maxLineDelta
                XCTAssertTrue(x.isFinite && y.isFinite)
                XCTAssertLessThanOrEqual(abs(x), limit)
                XCTAssertLessThanOrEqual(abs(y), limit)
            }
        }
    }

    func testDeterminism() {
        let tuned = settings { $0.acceleration = 0.6; $0.smoothing = 0.4; $0.horizontalDeadZone = 0.2; $0.verticalMultiplier = 1.3 }
        func run() -> [ScrollDecision] {
            var transformer = ScrollTransformer()
            return (0..<200).map { index in
                let value = Double((index * 37) % 23) - 11
                return transformer.decide(sample(value / 3, value, at: Double(index) * 0.013, continuous: index % 3 != 0,
                                                 momentum: index % 7 == 6), settings: tuned)
            }
        }
        XCTAssertEqual(run(), run())
    }

    func testResetForgetsGesture() {
        var transformer = ScrollTransformer()
        _ = transformer.decide(sample(0, 10), settings: settings { $0.acceleration = 1 })
        XCTAssertNotEqual(transformer, ScrollTransformer())
        transformer.reset()
        XCTAssertEqual(transformer, ScrollTransformer())
    }
}
