import Foundation
import MFCore
import MFUtilities
import MFGestures
import MFProfiles
import MFAutomation

/// One recognized gesture (or completed sequence) together with the binding that was in effect
/// when it was recognized.
struct PipelineOutput: Sendable {
    var event: GestureEvent
    var binding: GestureBinding?
    /// Set when `event` completed a sequence trigger.
    var sequence: [GestureKind]?
    var profileName: String
    var isSynthetic: Bool
    /// Monotonic time at which the completing frame, deadline or chord reached the pipeline.
    var recognizedAt: TimeInterval
}

/// Measured counters kept by the pipeline; the model copies them into `EngineMetrics`.
struct PipelineStats: Sendable, Equatable {
    var frames = 0
    var processingTotal: TimeInterval = 0
    var processingMax: TimeInterval = 0
    /// Real (non-synthetic) frames, the only ones with a meaningful delivery latency.
    var realFrames = 0
    var deliveryTotal: TimeInterval = 0
}

/// Everything the input threads need from the configuration, pushed as one value.
struct PipelineSettings: Sendable {
    var profile: ResolvedProfile
    var recognizer: RecognizerConfig
    var calibration: DeviceCalibration
    /// Raw-contact kinds the recognizer may emit.
    var recognizerKinds: Set<GestureKind>
}

/// Input side of the engine: frames → `GestureEngine` → `SequenceMatcher` → binding lookup.
///
/// Threading: recognizer, matcher and the profile snapshot are confined to one serial queue.
/// Adapter threads enter with `queue.sync`, so a frame is processed before `onFrame` returns.
/// The event-tap callbacks only touch a lock-protected snapshot (`tap`) and never wait on the
/// queue. Results leave through the callbacks, which the model forwards to the main actor.
/// A single timer on the queue is re-armed from the recognizer's and the matcher's next
/// deadline; nothing polls.
final class GesturePipeline: @unchecked Sendable {
    struct Callbacks: Sendable {
        var onOutput: @Sendable (PipelineOutput) -> Void
        /// Frame statistics changed (coalesced: at most about twice per second).
        var onStatsChanged: @Sendable () -> Void
        /// Synthetic playback with this token ran to its end.
        var onSyntheticFinished: @Sendable (Int) -> Void
        var onHotKey: @Sendable (UUID) -> Void
    }

    /// State read on the event-tap thread.
    private struct TapState {
        var chordKinds: Set<GestureKind> = []
        var scroll = ScrollSettings()
        var transformer = ScrollTransformer()
    }

    static let statsInterval: TimeInterval = 0.5
    /// Longest wait for pending recognizer deadlines after the last synthetic frame.
    static let syntheticDrainLimit: TimeInterval = 2.0
    /// Smallest re-arm delay right after a deadline fired, so a deadline the recognizer keeps
    /// reporting as due can never spin the queue.
    static let minimumRearmDelay: TimeInterval = 0.005

    private let queue = DispatchQueue(label: "com.magicforge.engine.pipeline", qos: .userInteractive)
    private let timer: DispatchSourceTimer
    private let feed: TouchFeed
    private let tap = Locked(TapState())
    private let stats = Locked(PipelineStats())

    // Confined to `queue`.
    private let engine = GestureEngine()
    private let matcher = SequenceMatcher()
    private var profile: ResolvedProfile
    private var callbacks: Callbacks?
    private var armedDeadline: TimeInterval?
    private var statsFlushScheduled = false
    private var syntheticToken = 0
    private var syntheticActive = false
    private var syntheticDraining = false

    init(feed: TouchFeed, profile: ResolvedProfile) {
        self.feed = feed
        self.profile = profile
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .distantFuture)
        timer.setEventHandler { [weak self] in self?.timerFired() }
        timer.resume()
    }

    deinit {
        timer.setEventHandler {}
        timer.cancel()
    }

    func setCallbacks(_ callbacks: Callbacks) {
        queue.sync { self.callbacks = callbacks }
    }

    // MARK: Configuration (called on the main actor)

    /// Applies a new snapshot. Returns after both the tap snapshot and the recognizer are updated.
    func apply(_ settings: PipelineSettings) {
        tap.withLock { state in
            state.chordKinds = settings.profile.chordKinds
            if state.scroll != settings.profile.scroll {
                state.scroll = settings.profile.scroll
                state.transformer.reset()
            }
        }
        queue.sync {
            profile = settings.profile
            if engine.config != settings.recognizer { engine.config = settings.recognizer }
            if engine.calibration != settings.calibration { engine.calibration = settings.calibration }
            if engine.enabledKinds != settings.recognizerKinds { engine.enabledKinds = settings.recognizerKinds }
            if matcher.window != settings.recognizer.sequenceWindow { matcher.window = settings.recognizer.sequenceWindow }
            let sequences = settings.profile.sequences
            // Assigning discards held events, so only do it for a real change.
            if Set(matcher.sequences) != Set(sequences) { matcher.sequences = sequences }
            rearm()
        }
    }

    /// Forgets recognizer, matcher and scroll state (input restart, stop).
    func reset() {
        tap.withLock { $0.transformer.reset() }
        queue.sync {
            cancelSyntheticLocked()
            engine.reset()
            matcher.reset()
            rearm()
        }
    }

    func resetScroll() {
        tap.withLock { $0.transformer.reset() }
    }

    // MARK: Statistics

    var currentStats: PipelineStats { stats.current }

    func resetStats() {
        stats.withLock { $0 = PipelineStats() }
    }

    // MARK: Real input

    /// The adapter's `onFrame`. Processes the frame before returning.
    func ingest(_ frame: TouchFrame) {
        queue.sync {
            // Mixing two streams would only make the recognizer cancel both.
            guard !syntheticActive else { return }
            process(frame, isSynthetic: false)
        }
    }

    func makePointerHandlers() -> PointerEventHandlers {
        PointerEventHandlers(
            onButton: { [weak self] _, _, timestamp in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.engine.notePhysicalClick(at: timestamp)
                    self.rearm()
                }
            },
            onScroll: { [weak self] sample in
                guard let self else { return .passThrough }
                return self.tap.withLock { state in
                    state.transformer.decide(sample, settings: state.scroll)
                }
            },
            onChord: { [weak self] kind, timestamp in
                guard let self, kind.category == .fallback else { return false }
                let isBound = self.tap.withLock { $0.chordKinds.contains(kind) }
                self.queue.async { [weak self] in
                    guard let self else { return }
                    let event = GestureEvent(kind: kind, timestamp: timestamp, confidence: 1, fingerCount: 0)
                    self.handle([event], recognizedAt: MonotonicClock.now(), isSynthetic: false)
                    self.rearm()
                }
                return isBound
            },
            onHotKey: { [weak self] identifier in
                guard let self else { return }
                self.queue.async { [weak self] in self?.callbacks?.onHotKey(identifier) }
            })
    }

    // MARK: Synthetic input

    /// Plays `frames` (in timestamp order) through the recognizer and returns the playback token.
    /// Real frames are ignored until playback ends. With `realtime` the frames keep their
    /// spacing, starting now; otherwise they are fed at once with timestamps ending now, so
    /// recognizer deadlines are already due.
    func playSynthetic(_ frames: [TouchFrame], realtime: Bool) -> Int {
        queue.sync {
            cancelSyntheticLocked()
            let token = syntheticToken
            guard let first = frames.first, let last = frames.last else {
                callbacks?.onSyntheticFinished(token)
                return token
            }
            engine.reset()
            syntheticActive = true
            let now = MonotonicClock.now()
            if realtime {
                feedSynthetic(frames, from: 0, shift: now - first.timestamp, token: token)
            } else {
                let shift = now - last.timestamp
                for frame in frames { process(shifted(frame, by: shift), isSynthetic: true) }
                beginDrain(token: token)
            }
            return token
        }
    }

    func stopSynthetic() {
        queue.sync {
            let wasActive = syntheticActive
            cancelSyntheticLocked()
            if wasActive {
                engine.reset()
                rearm()
            }
        }
    }

    private func cancelSyntheticLocked() {
        syntheticToken += 1
        syntheticActive = false
        syntheticDraining = false
    }

    private func shifted(_ frame: TouchFrame, by shift: TimeInterval) -> TouchFrame {
        TouchFrame(timestamp: frame.timestamp + shift, deviceID: 0, contacts: frame.contacts)
    }

    private func feedSynthetic(_ frames: [TouchFrame], from start: Int, shift: TimeInterval, token: Int) {
        guard token == syntheticToken, syntheticActive else { return }
        var index = start
        let now = MonotonicClock.now()
        while index < frames.count, frames[index].timestamp + shift <= now + 0.0005 {
            process(shifted(frames[index], by: shift), isSynthetic: true)
            index += 1
        }
        guard index < frames.count else {
            beginDrain(token: token)
            return
        }
        let delay = max(0, frames[index].timestamp + shift - now)
        let next = index
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.feedSynthetic(frames, from: next, shift: shift, token: token)
        }
    }

    /// Playback stays "active" until gestures that only a deadline can complete (a pending
    /// single tap, a held sequence) have been resolved.
    private func beginDrain(token: Int) {
        guard hasPendingDeadline else {
            finishSynthetic(token: token)
            return
        }
        syntheticDraining = true
        queue.asyncAfter(deadline: .now() + GesturePipeline.syntheticDrainLimit) { [weak self] in
            self?.finishSynthetic(token: token)
        }
    }

    private func finishSynthetic(token: Int) {
        guard token == syntheticToken, syntheticActive else { return }
        syntheticActive = false
        syntheticDraining = false
        engine.reset()
        rearm()
        callbacks?.onSyntheticFinished(token)
    }

    // MARK: Recognition (queue only)

    private func process(_ frame: TouchFrame, isSynthetic: Bool) {
        let arrival = MonotonicClock.now()
        let events = engine.process(frame)
        let elapsed = MonotonicClock.now() - arrival
        feed.push(frame, live: engine.liveState, processingTime: elapsed, isSynthetic: isSynthetic, now: arrival)
        stats.withLock { stats in
            stats.frames += 1
            stats.processingTotal += elapsed
            stats.processingMax = max(stats.processingMax, elapsed)
            if !isSynthetic {
                stats.realFrames += 1
                stats.deliveryTotal += max(0, arrival - frame.timestamp)
            }
        }
        scheduleStatsFlush()
        handle(events, recognizedAt: arrival, isSynthetic: isSynthetic)
        rearm()
    }

    private func handle(_ events: [GestureEvent], recognizedAt: TimeInterval, isSynthetic: Bool) {
        for event in events {
            feed.noteGesture(event)
            dispatch(matcher.feed(event), recognizedAt: recognizedAt, isSynthetic: isSynthetic)
        }
    }

    private func dispatch(_ resolutions: [SequenceMatcher.Resolution], recognizedAt: TimeInterval, isSynthetic: Bool) {
        guard let callbacks else { return }
        for resolution in resolutions {
            switch resolution {
            case .single(let event):
                callbacks.onOutput(PipelineOutput(event: event, binding: profile.binding(for: event.kind), sequence: nil,
                                                  profileName: profile.profileName, isSynthetic: isSynthetic,
                                                  recognizedAt: recognizedAt))
            case .sequence(let kinds, let event):
                callbacks.onOutput(PipelineOutput(event: event, binding: profile.binding(for: .sequence(kinds)),
                                                  sequence: kinds, profileName: profile.profileName,
                                                  isSynthetic: isSynthetic, recognizedAt: recognizedAt))
            }
        }
    }

    // MARK: Deadline timer (queue only)

    private var hasPendingDeadline: Bool { engine.nextDeadline != nil || matcher.nextDeadline != nil }

    private func rearm(afterFiring: Bool = false) {
        let deadline: TimeInterval?
        switch (engine.nextDeadline, matcher.nextDeadline) {
        case let (first?, second?): deadline = min(first, second)
        case let (first?, nil): deadline = first
        case let (nil, second?): deadline = second
        case (nil, nil): deadline = nil
        }
        guard let deadline else {
            if armedDeadline != nil {
                timer.schedule(deadline: .distantFuture)
                armedDeadline = nil
            }
            if syntheticDraining { finishSynthetic(token: syntheticToken) }
            return
        }
        if !afterFiring, armedDeadline == deadline { return }
        var delay = max(0, deadline - MonotonicClock.now())
        if afterFiring { delay = max(delay, GesturePipeline.minimumRearmDelay) }
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(1))
        armedDeadline = deadline
    }

    private func timerFired() {
        guard armedDeadline != nil else { return }
        armedDeadline = nil
        let now = MonotonicClock.now()
        let isSynthetic = syntheticActive
        handle(engine.advance(to: now), recognizedAt: now, isSynthetic: isSynthetic)
        dispatch(matcher.advance(to: now), recognizedAt: now, isSynthetic: isSynthetic)
        rearm(afterFiring: true)
    }

    private func scheduleStatsFlush() {
        guard !statsFlushScheduled else { return }
        statsFlushScheduled = true
        queue.asyncAfter(deadline: .now() + GesturePipeline.statsInterval) { [weak self] in
            guard let self else { return }
            self.statsFlushScheduled = false
            self.callbacks?.onStatsChanged()
        }
    }
}
