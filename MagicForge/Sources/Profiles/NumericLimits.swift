import Foundation
import MFCore

/// Safe ranges for every numeric setting. Values outside are clamped; values that are not
/// finite numbers fall back to the default.
enum NumericLimits {
    static let sensitivity = 0.0...1.0
    static let bindingDuration = 0.05...5.0
    static let priority = -1000...1000
    static let scrollMultiplier = 0.1...10.0
    static let maxTimeout = 600.0
    static let radialDiameter = 160.0...600.0

    /// Returns true when the value had to change.
    @discardableResult
    static func clamp(_ value: inout Double, to range: ClosedRange<Double>, fallback: Double) -> Bool {
        let fixed = value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        guard fixed != value else { return false }
        value = fixed
        return true
    }

    /// For durations that must be strictly positive: zero, negative and non-finite values fall
    /// back to the default, large ones are capped at `maxTimeout`.
    @discardableResult
    static func clampTimeout(_ value: inout Double, fallback: Double) -> Bool {
        let fixed: Double = (value.isFinite && value > 0) ? min(value, maxTimeout) : fallback
        guard fixed != value else { return false }
        value = fixed
        return true
    }

    static func repair(_ binding: inout GestureBinding, owner: String, _ report: inout RepairReport) {
        var changed = clamp(&binding.sensitivity, to: sensitivity, fallback: 0.5)
        if var duration = binding.duration {
            if !duration.isFinite {
                binding.duration = nil
                changed = true
            } else if clamp(&duration, to: bindingDuration, fallback: 0.5) {
                binding.duration = duration
                changed = true
            }
        }
        let clampedPriority = min(max(binding.priority, priority.lowerBound), priority.upperBound)
        if clampedPriority != binding.priority {
            binding.priority = clampedPriority
            changed = true
        }
        if changed {
            report.add("\(owner): out-of-range tuning values of “\(GestureNaming.name(binding.trigger))” were corrected.")
        }
    }

    static func repair(_ scroll: inout ScrollSettings, owner: String, _ report: inout RepairReport) {
        var changed = clamp(&scroll.verticalMultiplier, to: scrollMultiplier, fallback: 1)
        changed = clamp(&scroll.horizontalMultiplier, to: scrollMultiplier, fallback: 1) || changed
        changed = clamp(&scroll.acceleration, to: 0...1, fallback: 0) || changed
        changed = clamp(&scroll.smoothing, to: 0...1, fallback: 0) || changed
        changed = clamp(&scroll.horizontalDeadZone, to: 0...1, fallback: 0) || changed
        if changed { report.add("\(owner): out-of-range scroll settings were corrected.") }
    }

    static func repair(_ workflow: inout Workflow, _ report: inout RepairReport) {
        var changed = clampTimeout(&workflow.timeout, fallback: 30)
        let steps = repair(workflow.steps, changed: &changed)
        if changed {
            workflow.steps = steps
            report.add("Workflow “\(workflow.name)”: out-of-range delays or timeouts were corrected.")
        }
    }

    private static func repair(_ steps: [WorkflowStep], changed: inout Bool) -> [WorkflowStep] {
        steps.map { step in
            switch step {
            case .delay(var seconds):
                if clamp(&seconds, to: 0...maxTimeout, fallback: 0) { changed = true }
                return .delay(seconds: seconds)
            case .waitForApp(let bundleID, var timeout):
                if clampTimeout(&timeout, fallback: 10) { changed = true }
                return .waitForApp(bundleID: bundleID, timeout: timeout)
            case .conditional(let condition, let then, let otherwise):
                return .conditional(condition, then: repair(then, changed: &changed),
                                    otherwise: repair(otherwise, changed: &changed))
            case .action, .notify:
                return step
            }
        }
    }

    static func repair(_ theme: inout RadialMenuTheme, owner: String, _ report: inout RepairReport) {
        if clamp(&theme.diameter, to: radialDiameter, fallback: 280) {
            report.add("\(owner): the menu size was out of range and has been corrected.")
        }
        if !theme.accentHex.isEmpty, !isHexColour(theme.accentHex) {
            theme.accentHex = ""
            report.add("\(owner): the accent colour was not a valid #RRGGBB value; the system accent is used.")
        }
    }

    private static func isHexColour(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#" else { return false }
        let hexDigits = Set("0123456789abcdefABCDEF".unicodeScalars)
        return scalars.dropFirst().allSatisfy(hexDigits.contains)
    }

    static func repair(_ ai: inout AISettings, _ report: inout RepairReport) {
        if clampTimeout(&ai.timeout, fallback: 30) {
            report.add("The AI request timeout was out of range and has been corrected.")
        }
    }

    static func repair(_ config: inout RecognizerConfig, _ report: inout RepairReport) {
        let defaults = RecognizerConfig()
        var changed = false
        func fix(_ keyPath: WritableKeyPath<RecognizerConfig, Double>, _ range: ClosedRange<Double>) {
            if clamp(&config[keyPath: keyPath], to: range, fallback: defaults[keyPath: keyPath]) { changed = true }
        }
        fix(\.tapMaxDuration, 0.05...1.0)
        fix(\.tapMaxMovementMM, 0.5...10)
        fix(\.doubleTapWindow, 0.1...1.0)
        fix(\.holdMinDuration, 0.15...3.0)
        fix(\.holdMaxMovementMM, 0.5...10)
        fix(\.swipeMinDistanceMM, 3...60)
        fix(\.swipeMinVelocityMMPerSecond, 5...500)
        // Above 45° the four swipe directions would overlap.
        fix(\.directionToleranceDegrees, 5...45)
        fix(\.edgeZoneFraction, 0.05...0.35)
        fix(\.cornerZoneFraction, 0.10...0.45)
        fix(\.pinchMinChangeMM, 2...40)
        fix(\.rotationMinDegrees, 5...90)
        fix(\.sequenceWindow, 0.15...3.0)
        fix(\.minimumConfidence, 0...0.99)
        fix(\.cooldown, 0...2.0)
        fix(\.multiFingerLandingWindow, 0.02...0.5)
        fix(\.palmSizeThreshold, 0.5...10)
        fix(\.restingFingerDuration, 0.3...10)
        fix(\.physicalClickSuppression, 0...2.0)
        fix(\.globalSensitivity, sensitivity)
        for (key, original) in config.tuning {
            var tuning = original
            var tuningChanged = clamp(&tuning.sensitivity, to: sensitivity, fallback: 0.5)
            if var duration = tuning.duration {
                if !duration.isFinite {
                    tuning.duration = nil
                    tuningChanged = true
                } else if clamp(&duration, to: bindingDuration, fallback: 0.5) {
                    tuning.duration = duration
                    tuningChanged = true
                }
            }
            if tuningChanged {
                config.tuning[key] = tuning
                changed = true
            }
        }
        if changed { report.add("Out-of-range gesture recognition settings were corrected.") }
    }

    static func repair(_ calibrations: inout [String: DeviceCalibration], _ report: inout RepairReport) {
        let defaults = DeviceCalibration()
        var changed = false
        for (key, original) in calibrations {
            var calibration = original
            var fixed = clamp(&calibration.surface.widthMM, to: 10...300, fallback: defaults.surface.widthMM)
            fixed = clamp(&calibration.surface.heightMM, to: 10...300, fallback: defaults.surface.heightMM) || fixed
            fixed = clamp(&calibration.typicalTapSize, to: 0.05...5, fallback: defaults.typicalTapSize) || fixed
            fixed = clamp(&calibration.typicalTapMovementMM, to: 0...10, fallback: defaults.typicalTapMovementMM) || fixed
            fixed = clamp(&calibration.typicalTapDuration, to: 0.02...1, fallback: defaults.typicalTapDuration) || fixed
            fixed = clamp(&calibration.typicalSwipeDistanceMM, to: 3...90, fallback: defaults.typicalSwipeDistanceMM) || fixed
            if fixed {
                calibrations[key] = calibration
                changed = true
            }
        }
        if changed { report.add("Out-of-range device calibration values were corrected.") }
    }
}
