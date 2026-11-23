import Foundation
import MFCore

/// Deterministic synthetic touch-frame generator.
///
/// Everything here is SYNTHETIC input for tests, the Touch Lab demo and Gesture Studio
/// previews; it must always be labelled as such in the UI. No randomness is used unless a
/// caller passes an explicit seed to the `LCG`-driven builders.
public enum SyntheticTouch {
    /// Normalized surface position (x: 0 left … 1 right, y: 0 rear … 1 front).
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    public enum Easing: Sendable {
        case linear
        /// Smoothstep: slow start, fast middle, slow end, like a real finger stroke.
        case easeInOut

        public func apply(_ progress: Double) -> Double {
            let t = min(max(progress, 0), 1)
            switch self {
            case .linear: return t
            case .easeInOut: return t * t * (3 - 2 * t)
            }
        }
    }

    /// How a contact leaves the stream.
    public enum EndStyle: Sendable {
        /// One last sample with `ContactPhase.ended`.
        case endedPhase
        /// The contact is simply missing from the next frame (an empty frame when it was the last).
        case disappear
    }

    /// One finger's life on the surface: when it lands (seconds from the stream start), how
    /// long it stays, and where it is at each progress value 0…1.
    public struct ContactPath {
        public var id: Int
        public var start: TimeInterval
        public var duration: TimeInterval
        public var size: Double
        public var position: (Double) -> Point

        public init(id: Int, start: TimeInterval, duration: TimeInterval, size: Double = 0.6,
                    position: @escaping (Double) -> Point) {
            self.id = id; self.start = start; self.duration = duration; self.size = size
            self.position = position
        }

        public var end: TimeInterval { start + duration }
    }

    /// Simple 64-bit linear congruential generator (Knuth MMIX constants) for seeded streams.
    public struct LCG: Sendable {
        public private(set) var state: UInt64
        public init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }

        public mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        /// Uniform in 0 ..< 1.
        public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        public mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }

        public mutating func int(_ upperBound: Int) -> Int {
            upperBound > 0 ? Int(next() >> 33) % upperBound : 0
        }
    }

    // MARK: Rendering

    /// Samples the paths every `frameInterval` seconds. Frames exist only while something
    /// touches, plus one closing frame after each moment everything lifted (as real adapters do).
    public static func render(_ paths: [ContactPath], startTime: TimeInterval,
                              frameInterval: TimeInterval = 0.011,
                              endStyle: EndStyle = .endedPhase) -> [TouchFrame] {
        guard !paths.isEmpty, frameInterval > 0 else { return [] }
        let epsilon = 1e-9
        let totalEnd = paths.map(\.end).max() ?? 0
        let steps = Int((totalEnd / frameInterval).rounded(.up)) + 1
        var previous = [Point](repeating: Point(0, 0), count: paths.count)
        var wasTouching = [Bool](repeating: false, count: paths.count)
        var somethingTouched = false
        var frames: [TouchFrame] = []
        frames.reserveCapacity(steps + 1)

        for step in 0...steps {
            let offset = Double(step) * frameInterval
            var contacts: [TouchContact] = []
            var touchingNow = false
            for (index, path) in paths.enumerated() {
                let active = offset >= path.start - epsilon && offset < path.end - epsilon
                if active {
                    let progress = path.duration > 0 ? (offset - path.start) / path.duration : 0
                    let raw = path.position(min(max(progress, 0), 1))
                    let point = Point(min(max(raw.x, 0), 1), min(max(raw.y, 0), 1))
                    var contact = TouchContact(id: path.id, x: point.x, y: point.y, size: path.size)
                    if wasTouching[index] {
                        contact.vx = (point.x - previous[index].x) / frameInterval
                        contact.vy = (point.y - previous[index].y) / frameInterval
                        contact.phase = point == previous[index] ? .stationary : .moved
                    } else {
                        contact.phase = .began
                    }
                    contact.majorAxis = 9 * path.size / 0.6
                    contact.minorAxis = 7 * path.size / 0.6
                    contacts.append(contact)
                    previous[index] = point
                    wasTouching[index] = true
                    touchingNow = true
                } else if wasTouching[index] {
                    wasTouching[index] = false
                    if endStyle == .endedPhase {
                        contacts.append(TouchContact(id: path.id, x: previous[index].x, y: previous[index].y,
                                                     size: path.size, phase: .ended))
                    }
                }
            }
            // Skip silent stretches, but always deliver the frame that reports the last lift.
            if contacts.isEmpty && !somethingTouched { continue }
            frames.append(TouchFrame(timestamp: startTime + offset, deviceID: 0, contacts: contacts))
            somethingTouched = touchingNow
        }
        return frames
    }

    /// Removes every frame with `from <= timestamp < to`, simulating a contact interruption.
    public static func droppingFrames(_ frames: [TouchFrame], from: TimeInterval,
                                      to: TimeInterval) -> [TouchFrame] {
        frames.filter { $0.timestamp < from || $0.timestamp >= to }
    }

    /// Shifts ids so that streams built separately can be concatenated without id reuse issues.
    public static func concatenate(_ streams: [[TouchFrame]]) -> [TouchFrame] {
        streams.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
    }
}
