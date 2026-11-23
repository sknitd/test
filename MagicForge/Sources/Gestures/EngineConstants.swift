import Foundation

/// Fixed internal limits of the recognizer that are not part of `RecognizerConfig`.
/// They are deliberately conservative and documented in docs/GESTURES.md.
enum EngineConstants {
    /// A gap between two frames longer than this while contacts are tracked is a contact
    /// interruption: the in-progress episode is cancelled and surviving contacts are quarantined.
    static let maxFrameGap: TimeInterval = 0.10
    /// Contacts shorter than this (single-frame blips) never count as a tap (debounce).
    static let minContactDuration: TimeInterval = 0.015
    /// Centroid travel / pinch change below this is "not moving yet"; the stroke clock restarts.
    static let motionSlopMM: Double = 1.0
    /// Rotation below this is "not rotating yet".
    static let motionSlopDegrees: Double = 3.0
    /// Two-finger disambiguation: the winning measure (translation / pinch / rotation, each
    /// normalised by its own threshold) must exceed the runner-up by this factor.
    static let dominanceRatio: Double = 1.25
    /// Pinch and rotate must reach their threshold within this long after motion starts.
    static let maxPinchRotateStroke: TimeInterval = 0.8
    /// Below this finger separation the inter-finger angle is too noisy to measure rotation.
    static let minRotationSeparationMM: Double = 6.0
    /// In a pinch / rotate the less-moving finger must travel at least this share of the other
    /// finger's travel (rejects "one finger rests, one finger scrolls").
    static let minPartnerTravelShare: Double = 0.2
    /// The two taps of a double tap must start within this distance of each other.
    static let doubleTapMaxDistanceMM: Double = 12.0
    /// A contact that has not left its anchor for this long counts as "quiet" when another
    /// finger lands late (it is then demoted to resting instead of blocking the newcomer).
    static let quietDuration: TimeInterval = 0.25
    /// Contacts at least this many times larger than `DeviceCalibration.typicalTapSize` are
    /// "flat" (a finger lying on the shell rather than a fingertip).
    static let flatContactFactor: Double = 1.8
    /// Flat contacts become resting after this long without moving (instead of
    /// `RecognizerConfig.restingFingerDuration`), so they can never produce a hold.
    static let flatRestDuration: TimeInterval = 0.25
    /// Multi-finger swipes: every finger must travel at least this share of the centroid
    /// distance along the swipe direction.
    static let swipeCoherence: Double = 0.4
    /// A hold threshold is never allowed closer than this to the tap duration limit.
    static let minHoldOverTap: TimeInterval = 0.03
    /// Upper clamp for the direction tolerance (45° would make every stroke a valid swipe).
    static let maxDirectionToleranceDegrees: Double = 44
    static let maxFingers = 3
    /// Radius (mm) a contact may wander around its anchor and still count as "not moving"
    /// for resting-finger classification.
    static let restRadiusMM: Double = 3.0
}
