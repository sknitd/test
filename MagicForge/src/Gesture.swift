import CoreFoundation
import Foundation

/// Every gesture MagicForge can recognize. Raw values are persisted in profiles: never rename.
public enum GestureKind: String, Codable, Sendable, CaseIterable, Hashable {
    // One finger
    case oneFingerTap, oneFingerDoubleTap, oneFingerHold
    /// Slide along the left / right edge strip (vertical motion inside the edge zone).
    case leftEdgeSwipe, rightEdgeSwipe
    /// Slide along the front (top) / rear (bottom) edge strip (horizontal motion inside the zone).
    case topEdgeSwipe, bottomEdgeSwipe
    /// One-finger swipes outside the edge zones. These overlap native scrolling, so they are
    /// disabled by default and flagged by `overlapsNativeScrolling`.
    case oneFingerSwipeLeft, oneFingerSwipeRight, oneFingerSwipeUp, oneFingerSwipeDown
    // Two fingers
    case twoFingerTap, twoFingerDoubleTap, twoFingerHold
    case twoFingerSwipeLeft, twoFingerSwipeRight, twoFingerSwipeUp, twoFingerSwipeDown
    case pinchIn, pinchOut, rotateClockwise, rotateCounterclockwise
    // Three fingers
    case threeFingerTap, threeFingerHold
    case threeFingerSwipeLeft, threeFingerSwipeRight, threeFingerSwipeUp, threeFingerSwipeDown
    // Zones (one finger)
    case cornerTapTopLeft, cornerTapTopRight, cornerTapBottomLeft, cornerTapBottomRight
    /// Tap in the middle third of the surface (classic "middle click" trigger).
    case centerTap
    // Compound (one finger)
    case tapThenSwipeLeft, tapThenSwipeRight, tapThenSwipeUp, tapThenSwipeDown
    case holdThenSwipeLeft, holdThenSwipeRight, holdThenSwipeUp, holdThenSwipeDown
    // Public-API fallback triggers (no raw touch data needed; delivered by the event tap).
    /// Control+Option held while left / right clicking.
    case chordLeftClick, chordRightClick
    /// Control+Option held while scrolling in a direction (one event per scroll burst).
    case chordScrollUp, chordScrollDown, chordScrollLeft, chordScrollRight

    public enum Requirement: String, Codable, Sendable { case rawContacts, pointerEvents }
    public enum Category: String, Codable, Sendable, CaseIterable {
        case oneFinger, twoFinger, threeFinger, zones, compound, fallback
    }
    public enum Direction: String, Codable, Sendable { case left, right, up, down }

    public var requirement: Requirement {
        category == .fallback ? .pointerEvents : .rawContacts
    }

    /// Number of simultaneous contacts needed (0 for fallback triggers).
    public var fingerCount: Int {
        switch category {
        case .oneFinger, .zones, .compound: return 1
        case .twoFinger: return 2
        case .threeFinger: return 3
        case .fallback: return 0
        }
    }

    public var category: Category {
        switch self {
        case .oneFingerTap, .oneFingerDoubleTap, .oneFingerHold, .leftEdgeSwipe, .rightEdgeSwipe, .topEdgeSwipe,
             .bottomEdgeSwipe, .oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown:
            return .oneFinger
        case .twoFingerTap, .twoFingerDoubleTap, .twoFingerHold, .twoFingerSwipeLeft, .twoFingerSwipeRight,
             .twoFingerSwipeUp, .twoFingerSwipeDown, .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterclockwise:
            return .twoFinger
        case .threeFingerTap, .threeFingerHold, .threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp,
             .threeFingerSwipeDown:
            return .threeFinger
        case .cornerTapTopLeft, .cornerTapTopRight, .cornerTapBottomLeft, .cornerTapBottomRight, .centerTap:
            return .zones
        case .tapThenSwipeLeft, .tapThenSwipeRight, .tapThenSwipeUp, .tapThenSwipeDown, .holdThenSwipeLeft,
             .holdThenSwipeRight, .holdThenSwipeUp, .holdThenSwipeDown:
            return .compound
        case .chordLeftClick, .chordRightClick, .chordScrollUp, .chordScrollDown, .chordScrollLeft, .chordScrollRight:
            return .fallback
        }
    }

    /// One-finger motion on a Magic Mouse is native scrolling; binding these means every scroll
    /// in that direction also fires the action. The UI must warn before enabling them.
    public var overlapsNativeScrolling: Bool {
        switch self {
        case .oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown: return true
        default: return false
        }
    }

    public func isAvailable(with capabilities: InputCapabilities) -> Bool {
        switch requirement {
        case .rawContacts: return capabilities.rawContacts && capabilities.maxContacts >= fingerCount
        case .pointerEvents: return capabilities.pointerEvents
        }
    }
}

/// What a binding listens for: one gesture, or several recognized back-to-back.
public enum GestureTrigger: Codable, Hashable, Sendable {
    case single(GestureKind)
    /// Two to four gestures recognized consecutively, each within `RecognizerConfig.sequenceWindow`
    /// of the previous one.
    case sequence([GestureKind])

    public var kinds: [GestureKind] {
        switch self {
        case .single(let kind): return [kind]
        case .sequence(let kinds): return kinds
        }
    }
}

/// A recognized gesture.
public struct GestureEvent: Codable, Sendable, Equatable {
    public var kind: GestureKind
    /// Timestamp (monotonic seconds) of the frame or deadline that completed the gesture.
    public var timestamp: TimeInterval
    /// 0…1. Events below `RecognizerConfig.minimumConfidence` are never emitted.
    public var confidence: Double
    public var fingerCount: Int
    /// Seconds from first contact to recognition.
    public var duration: TimeInterval
    /// Normalized centroid where the gesture started.
    public var originX: Double
    public var originY: Double
    /// Gesture specific: swipe distance (mm), pinch distance change (mm), rotation (degrees), else 0.
    public var magnitude: Double

    public init(kind: GestureKind, timestamp: TimeInterval, confidence: Double, fingerCount: Int,
                duration: TimeInterval = 0, originX: Double = 0.5, originY: Double = 0.5, magnitude: Double = 0) {
        self.kind = kind; self.timestamp = timestamp; self.confidence = confidence; self.fingerCount = fingerCount
        self.duration = duration; self.originX = originX; self.originY = originY; self.magnitude = magnitude
    }
}

/// Per-gesture tuning. `sensitivity` 0…1 (0.5 = defaults): higher means shorter distances /
/// looser thresholds, lower means the gesture must be more deliberate.
public struct GestureTuning: Codable, Sendable, Equatable {
    public var sensitivity: Double
    /// Overrides the hold / tap duration threshold for this gesture when set.
    public var duration: TimeInterval?
    public init(sensitivity: Double = 0.5, duration: TimeInterval? = nil) {
        self.sensitivity = sensitivity; self.duration = duration
    }
}

/// Recognition thresholds. Distances are millimetres on the surface, times are seconds.
public struct RecognizerConfig: Codable, Sendable, Equatable {
    public var tapMaxDuration: TimeInterval = 0.22
    public var tapMaxMovementMM: Double = 2.5
    public var doubleTapWindow: TimeInterval = 0.30
    public var holdMinDuration: TimeInterval = 0.50
    public var holdMaxMovementMM: Double = 3.0
    public var swipeMinDistanceMM: Double = 14
    public var swipeMinVelocityMMPerSecond: Double = 70
    /// Maximum deviation from the cardinal axis for a swipe, in degrees.
    public var directionToleranceDegrees: Double = 30
    /// Width of the edge strips as a fraction of the surface (per side).
    public var edgeZoneFraction: Double = 0.16
    /// Size of the corner zones as a fraction of width / height.
    public var cornerZoneFraction: Double = 0.28
    public var pinchMinChangeMM: Double = 8
    public var rotationMinDegrees: Double = 18
    /// Maximum gap between gestures of a `GestureTrigger.sequence` and between the parts of
    /// tap-then-swipe.
    public var sequenceWindow: TimeInterval = 0.60
    /// Events with lower confidence are dropped.
    public var minimumConfidence: Double = 0.60
    /// Minimum time between two emissions of the same gesture kind.
    public var cooldown: TimeInterval = 0.18
    /// Fingers must land within this window to count as one multi-finger gesture.
    public var multiFingerLandingWindow: TimeInterval = 0.09
    /// Contacts larger than this (sensor size units) are treated as a palm and ignored.
    public var palmSizeThreshold: Double = 2.2
    /// A contact that stays put longer than this without lifting is a resting finger: it stops
    /// counting toward the finger count of later gestures.
    public var restingFingerDuration: TimeInterval = 1.2
    /// Taps are suppressed for this long around a physical button press.
    public var physicalClickSuppression: TimeInterval = 0.25
    /// Multiplies every per-gesture sensitivity (0…1, 0.5 = neutral).
    public var globalSensitivity: Double = 0.5
    /// Keyed by `GestureKind.rawValue`.
    public var tuning: [String: GestureTuning] = [:]

    public init() {}

    public func tuning(for kind: GestureKind) -> GestureTuning { tuning[kind.rawValue] ?? GestureTuning() }
    public mutating func setTuning(_ value: GestureTuning, for kind: GestureKind) { tuning[kind.rawValue] = value }
}

/// Per-device calibration captured by the calibration UI.
public struct DeviceCalibration: Codable, Sendable, Equatable {
    public var surface: SurfaceGeometry = .magicMouse
    /// Typical contact size of a deliberate fingertip tap on this device / for this user.
    public var typicalTapSize: Double = 0.6
    /// Typical movement (mm) during the user's taps; scales `tapMaxMovementMM`.
    public var typicalTapMovementMM: Double = 0.8
    /// Typical tap duration for this user.
    public var typicalTapDuration: TimeInterval = 0.10
    /// Typical swipe length (mm) for this user; scales `swipeMinDistanceMM`.
    public var typicalSwipeDistanceMM: Double = 25
    public var calibratedAt: Date?
    public init() {}
}

/// What the recognizer currently believes, for the Touch Lab overlay.
public struct RecognizerLiveState: Codable, Sendable, Equatable {
    /// Contacts counted toward gestures (palms and resting fingers excluded).
    public var activeFingerCount: Int = 0
    public var restingFingerCount: Int = 0
    /// Best current guess while a gesture is in progress.
    public var candidate: GestureKind?
    public var candidateConfidence: Double = 0
    /// Human-readable state machine state, e.g. "idle", "tracking", "awaitingSecondTap".
    public var phase: String = "idle"
    public init() {}
}

/// Deterministic gesture recognizer. Not thread-safe: call from one serial context.
public protocol GestureRecognizing: AnyObject {
    var config: RecognizerConfig { get set }
    var calibration: DeviceCalibration { get set }
    /// Only these kinds may be emitted. Also drives conflict resolution: e.g. a single tap is
    /// emitted immediately unless a double tap / tap-then-swipe of the same finger count is enabled.
    var enabledKinds: Set<GestureKind> { get set }
    /// Feed the next frame; returns gestures completed by it.
    func process(_ frame: TouchFrame) -> [GestureEvent]
    /// Advance time without a frame (pending single taps, holds). Call when `nextDeadline` passes.
    func advance(to now: TimeInterval) -> [GestureEvent]
    /// Earliest monotonic time at which `advance(to:)` could emit something, if any.
    var nextDeadline: TimeInterval? { get }
    /// A physical mouse button went down / up; suppresses tap gestures around it.
    func notePhysicalClick(at timestamp: TimeInterval)
    func reset()
    var liveState: RecognizerLiveState { get }
}
