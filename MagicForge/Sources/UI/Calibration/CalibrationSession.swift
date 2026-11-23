import Foundation
import Observation
import MFCore
import MFEngine

/// State machine of the guided calibration. Measures real contacts from `TouchFeed` snapshots
/// (finished trails) while bound actions are suppressed. Synthetic frames are never measured.
@MainActor
@Observable
final class CalibrationSession {
    enum Step: Equatable { case intro, taps, swipes, rest, review }

    static let restSeconds: TimeInterval = 3

    private(set) var step: Step = .intro
    private(set) var taps: [CalibrationContactSample] = []
    /// Accepted swipes, in `CalibrationMath.swipeOrder`.
    private(set) var swipes: [CalibrationContactSample] = []
    /// Seconds the hand has rested on the surface during the rest step.
    private(set) var restElapsed: TimeInterval = 0
    /// Largest contact size and contact count seen while resting (informational, not saved).
    private(set) var restMaxSize: Double?
    private(set) var restMaxContacts: Int = 0
    /// What happened with the last contact, for the user.
    private(set) var feedback: String?
    /// Last gesture the recognizer reported during calibration (informational).
    private(set) var lastRecognized: GestureKind?
    private(set) var sawSyntheticInput: Bool = false

    @ObservationIgnored var surface: SurfaceGeometry = .magicMouse
    @ObservationIgnored private var isActive: Bool = false
    @ObservationIgnored private var savedHandler: ((GestureEvent) -> Void)?
    @ObservationIgnored private var savedSuppressActions: Bool = false
    @ObservationIgnored private var savedFeedPaused: Bool = false
    @ObservationIgnored private var consumedTrails: Set<String> = []
    @ObservationIgnored private var sizeSamples: [Int: [Double]] = [:]
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1
    @ObservationIgnored private var stepStartedAt: TimeInterval = 0
    @ObservationIgnored private var lastPollTime: TimeInterval?

    init() {}

    var expectedSwipe: GestureKind.Direction? {
        swipes.count < CalibrationMath.swipeOrder.count ? CalibrationMath.swipeOrder[swipes.count] : nil
    }

    // MARK: Lifecycle

    /// Starts measuring: suppresses actions, listens for gestures and un-pauses the feed.
    func begin(model: AppModel, surface: SurfaceGeometry, now: TimeInterval) {
        self.surface = surface
        if !isActive {
            savedHandler = model.onGesture
            savedSuppressActions = model.suppressActions
            savedFeedPaused = model.touchFeed.isPaused
            model.suppressActions = true
            model.touchFeed.isPaused = false
            model.onGesture = { [weak self] event in
                self?.lastRecognized = event.kind
            }
            isActive = true
        }
        taps = []
        swipes = []
        restElapsed = 0
        restMaxSize = nil
        restMaxContacts = 0
        feedback = nil
        lastRecognized = nil
        sawSyntheticInput = false
        consumedTrails = []
        sizeSamples = [:]
        enter(.taps, now: now)
    }

    /// Restores everything `begin` changed. Safe to call repeatedly.
    func end(model: AppModel) {
        guard isActive else { return }
        model.onGesture = savedHandler
        model.suppressActions = savedSuppressActions
        model.touchFeed.isPaused = savedFeedPaused
        savedHandler = nil
        isActive = false
    }

    func skipRest(now: TimeInterval) {
        if step == .rest { enter(.review, now: now) }
    }

    private func enter(_ newStep: Step, now: TimeInterval) {
        step = newStep
        stepStartedAt = now
        lastPollTime = nil
    }

    // MARK: Measuring

    /// Call a few dozen times per second with a fresh snapshot.
    func poll(_ snapshot: TouchFeed.Snapshot, now: TimeInterval) {
        guard step == .taps || step == .swipes || step == .rest else { return }
        if snapshot.isSynthetic {
            // Generated frames must never end up in a calibration.
            if snapshot.latest != nil && (snapshot.latest?.timestamp ?? 0) >= stepStartedAt { sawSyntheticInput = true }
            lastPollTime = now
            return
        }
        var touchingCount: Int = 0
        if let frame = snapshot.latest {
            let touching: [TouchContact] = frame.touching
            touchingCount = touching.count
            if frame.timestamp != lastFrameTimestamp {
                lastFrameTimestamp = frame.timestamp
                for contact in touching {
                    sizeSamples[contact.id, default: []].append(contact.size)
                    if step == .rest && contact.size > 0 { restMaxSize = max(restMaxSize ?? 0, contact.size) }
                }
            }
        }
        if step == .rest {
            restMaxContacts = max(restMaxContacts, touchingCount)
            if touchingCount > 0, let previous = lastPollTime { restElapsed += max(0, now - previous) }
            if restElapsed >= Self.restSeconds { enter(.review, now: now) }
        }
        lastPollTime = now
        collectFinishedContacts(snapshot)
    }

    /// A trail whose contact is no longer touching is one complete contact (landing → lift).
    private func collectFinishedContacts(_ snapshot: TouchFeed.Snapshot) {
        for (id, trail) in snapshot.trails where snapshot.contactStart[id] == nil {
            guard let first = trail.first else { continue }
            let key: String = "\(id)@\(first.timestamp)"
            guard !consumedTrails.contains(key) else { continue }
            consumedTrails.insert(key)
            let sizes: [Double] = sizeSamples.removeValue(forKey: id) ?? []
            // Contacts that began before the current step do not belong to it.
            guard first.timestamp >= stepStartedAt else { continue }
            guard let sample = CalibrationMath.sample(from: trail, sizes: sizes, surface: surface) else { continue }
            handle(sample)
        }
    }

    private func handle(_ sample: CalibrationContactSample) {
        switch step {
        case .taps:
            guard CalibrationMath.isTap(sample) else {
                feedback = sample.duration > CalibrationMath.tapMaxDuration
                    ? "Not counted: the finger stayed down too long for a tap."
                    : "Not counted: the finger moved too far for a tap."
                return
            }
            taps.append(sample)
            feedback = "Tap \(taps.count) of \(CalibrationMath.requiredTaps) recorded."
            if taps.count >= CalibrationMath.requiredTaps { enter(.swipes, now: stepStartedAt) }
        case .swipes:
            guard let expected = expectedSwipe else { return }
            guard let direction = CalibrationMath.direction(of: sample) else {
                feedback = "Not counted: that movement was too short for a swipe."
                return
            }
            guard direction == expected else {
                feedback = "Not counted: that was a swipe \(direction.rawValue); please swipe \(expected.rawValue)."
                return
            }
            swipes.append(sample)
            feedback = String(format: "Swipe %@ recorded (%.1f mm).", expected.rawValue, sample.netDistanceMM)
            if swipes.count >= CalibrationMath.swipeOrder.count { enter(.rest, now: stepStartedAt) }
        case .intro, .rest, .review:
            break
        }
    }

    /// The calibration these samples produce (medians; see `CalibrationMath`).
    func result(base: DeviceCalibration) -> DeviceCalibration {
        CalibrationMath.calibration(taps: taps, swipes: swipes, surface: surface, base: base, date: Date())
    }
}
