import Foundation
import MFCore

/// Matches streams of recognized gestures against `GestureTrigger.sequence` bindings.
///
/// Semantics (deterministic, no clocks: time comes from event timestamps and `advance(to:)`):
/// - Registered sequences have 2…4 kinds; anything else is ignored.
/// - The matcher HOLDS events while they form a prefix of at least one sequence. Every event
///   fed in comes back out exactly once: either as `.single` (run its single-gesture binding)
///   or as part of a `.sequence` (run the sequence binding instead of the single bindings).
/// - Longest match wins. When the held events complete a sequence that is itself a prefix of
///   a longer one, the match is deferred until the next event or the window decides:
///   continuing toward the longer sequence keeps holding; anything else (or the window
///   elapsing) resolves the shorter sequence first.
/// - Consecutive events belong together only when each arrives no more than `window` after
///   the previous one. When the window elapses the held events are resolved front to back:
///   the longest complete sequence at the front, otherwise the first event as `.single`.
/// - On a mismatch the same front-to-back resolution runs until what remains is a prefix
///   again, so `a a b` still matches `[a, b]` (the first `a` is released as a single).
/// - Consequently a single-gesture binding is delayed (by at most `window`) exactly when
///   `delaysSingle(kind)` is true, i.e. the kind is the first element of a registered sequence.
public final class SequenceMatcher {
    public enum Resolution: Equatable {
        /// The event is not part of a sequence: run its single-gesture binding now.
        case single(GestureEvent)
        /// A registered sequence completed with this event as its last element.
        case sequence([GestureKind], completedBy: GestureEvent)
    }

    public static let minimumLength = 2
    public static let maximumLength = 4

    /// Maximum gap between consecutive events of one sequence (`RecognizerConfig.sequenceWindow`).
    public var window: TimeInterval
    /// Registered sequences. Invalid lengths and duplicates are dropped. Changing this discards
    /// any events currently held.
    public var sequences: [[GestureKind]] {
        didSet {
            let cleaned = SequenceMatcher.normalized(sequences)
            if cleaned != sequences { sequences = cleaned }
            held.removeAll()
        }
    }
    /// Events currently held back because they may still become a sequence.
    public private(set) var held: [GestureEvent] = []

    public init(sequences: [[GestureKind]] = [], window: TimeInterval = RecognizerConfig().sequenceWindow) {
        self.sequences = SequenceMatcher.normalized(sequences)
        self.window = window
    }

    /// Convenience: registers every `.sequence` trigger and uses `config.sequenceWindow`.
    public convenience init(triggers: [GestureTrigger], config: RecognizerConfig = .init()) {
        var found: [[GestureKind]] = []
        for trigger in triggers {
            if case .sequence(let kinds) = trigger { found.append(kinds) }
        }
        self.init(sequences: found, window: config.sequenceWindow)
    }

    public var isHolding: Bool { !held.isEmpty }

    /// When `advance(to:)` will release the held events, if any are held.
    public var nextDeadline: TimeInterval? {
        held.last.map { $0.timestamp + window }
    }

    /// True when a single-gesture binding for `kind` has to wait for the sequence window,
    /// because `kind` starts at least one registered sequence.
    public func delaysSingle(_ kind: GestureKind) -> Bool {
        sequences.contains { $0.first == kind }
    }

    /// True when `kinds` is the beginning of a strictly longer registered sequence.
    public func isProperPrefix(_ kinds: [GestureKind]) -> Bool {
        sequences.contains { $0.count > kinds.count && $0.starts(with: kinds) }
    }

    public func isComplete(_ kinds: [GestureKind]) -> Bool { sequences.contains(kinds) }

    /// Feed the next recognized gesture. Returns what the host should act on, in order.
    public func feed(_ event: GestureEvent) -> [Resolution] {
        var out: [Resolution] = []
        if let last = held.last, event.timestamp - last.timestamp > window {
            while !held.isEmpty { resolveFront(&out) }
        }
        held.append(event)
        while !held.isEmpty {
            let kinds = held.map(\.kind)
            if isProperPrefix(kinds) { break }                 // may still grow (possibly deferred)
            resolveFront(&out)                                 // complete, or a dead end
        }
        return out
    }

    /// Releases held events once the window after the last one has elapsed.
    public func advance(to now: TimeInterval) -> [Resolution] {
        var out: [Resolution] = []
        guard let deadline = nextDeadline, now >= deadline else { return out }
        while !held.isEmpty { resolveFront(&out) }
        return out
    }

    public func reset() { held.removeAll() }

    /// Removes the longest complete sequence from the front of `held`, or else its first event.
    private func resolveFront(_ out: inout [Resolution]) {
        var length = min(held.count, SequenceMatcher.maximumLength)
        while length >= SequenceMatcher.minimumLength {
            let kinds = held.prefix(length).map(\.kind)
            if isComplete(kinds) {
                out.append(.sequence(kinds, completedBy: held[length - 1]))
                held.removeFirst(length)
                return
            }
            length -= 1
        }
        out.append(.single(held.removeFirst()))
    }

    private static func normalized(_ sequences: [[GestureKind]]) -> [[GestureKind]] {
        var result: [[GestureKind]] = []
        for sequence in sequences
        where sequence.count >= minimumLength && sequence.count <= maximumLength && !result.contains(sequence) {
            result.append(sequence)
        }
        return result
    }
}
