import Foundation
import Observation
import MFCore
import MFEngine

/// Listens to recognized gestures while Gesture Studio's "Test gesture" is active.
/// Starting suppresses bound actions and takes over `AppModel.onGesture`; stopping restores both.
@MainActor
@Observable
final class GestureTestSession {
    struct Attempt: Identifiable, Equatable {
        let id: UUID
        let event: GestureEvent
        let matchesExpected: Bool
        /// True when the gesture came from "Play Synthetic" rather than a finger.
        let isSynthetic: Bool
        let date: Date
    }

    static let maximumAttempts = 8

    var expected: GestureKind = .oneFingerTap
    private(set) var attempts: [Attempt] = []
    private(set) var isListening: Bool = false
    /// Shown under the buttons, e.g. why synthetic playback did nothing.
    var notice: String?

    @ObservationIgnored private var savedHandler: ((GestureEvent) -> Void)?
    @ObservationIgnored private var savedSuppressActions: Bool = false
    @ObservationIgnored private var syntheticUntil: Date = .distantPast

    init() {}

    func start(model: AppModel) {
        guard !isListening else { return }
        savedHandler = model.onGesture
        savedSuppressActions = model.suppressActions
        model.suppressActions = true
        model.onGesture = { [weak self, weak model] event in
            self?.record(event, syntheticPlaybackActive: model?.isSyntheticInputActive ?? false)
        }
        isListening = true
    }

    func stop(model: AppModel) {
        guard isListening else { return }
        model.onGesture = savedHandler
        model.suppressActions = savedSuppressActions
        savedHandler = nil
        isListening = false
    }

    /// Gestures recognized until `seconds` from now are labelled synthetic (covers events the
    /// recognizer emits shortly after the last synthetic frame, such as a pending single tap).
    func expectSynthetic(for seconds: TimeInterval) {
        syntheticUntil = Date().addingTimeInterval(seconds)
    }

    func clear() {
        attempts.removeAll()
        notice = nil
    }

    private func record(_ event: GestureEvent, syntheticPlaybackActive: Bool) {
        let now = Date()
        let attempt = Attempt(id: UUID(), event: event, matchesExpected: event.kind == expected,
                              isSynthetic: syntheticPlaybackActive || now < syntheticUntil, date: now)
        attempts.insert(attempt, at: 0)
        if attempts.count > Self.maximumAttempts { attempts.removeLast(attempts.count - Self.maximumAttempts) }
    }
}
