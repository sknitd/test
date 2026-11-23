import Foundation
import MFCore

/// Pure description of how a gesture is performed, used by `GesturePreview`.
///
/// Coordinates use the same convention as `TouchContact`: x 0 = left … 1 = right,
/// y 0 = rear edge (palm) … 1 = front edge. Every finger track is a function of the loop
/// phase 0…1 (`FingerTrack.sample(at:)`); nothing here depends on SwiftUI.
public struct GestureChoreography: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// State of one finger at one phase.
    public struct FingerSample: Equatable, Sendable {
        public var position: Point
        /// 0…1 while a tap ripple expands, nil otherwise.
        public var rippleProgress: Double?
        /// 0…1 while a hold ring fills, nil otherwise.
        public var holdProgress: Double?
    }

    /// One stretch of a finger's contact with the surface.
    public struct Segment: Equatable, Sendable {
        public enum Motion: Equatable, Sendable {
            case stay(Point)
            case line(from: Point, to: Point)
            /// Elliptical arc (radii in normalized units; angles in radians, counterclockwise positive).
            case arc(center: Point, radiusX: Double, radiusY: Double, startAngle: Double, sweep: Double)
        }
        public var start: Double
        public var end: Double
        public var motion: Motion
        public var showsRipple: Bool
        public var showsHoldRing: Bool

        public init(start: Double, end: Double, motion: Motion, showsRipple: Bool = false, showsHoldRing: Bool = false) {
            self.start = start; self.end = end; self.motion = motion
            self.showsRipple = showsRipple; self.showsHoldRing = showsHoldRing
        }
    }

    /// A finger: touching during its segments, lifted in between.
    public struct FingerTrack: Equatable, Sendable {
        public var segments: [Segment]
        public init(segments: [Segment]) { self.segments = segments }

        /// The finger at `phase` (0…1), or nil while it is lifted.
        public func sample(at phase: Double) -> FingerSample? {
            guard let segment = segments.first(where: { phase >= $0.start && phase < $0.end }) else { return nil }
            let span = max(segment.end - segment.start, 0.0001)
            let linear = min(max((phase - segment.start) / span, 0), 1)
            let eased = linear * linear * (3 - 2 * linear)
            let position: Point
            switch segment.motion {
            case .stay(let point):
                position = point
            case .line(let from, let to):
                position = Point(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
            case .arc(let center, let radiusX, let radiusY, let startAngle, let sweep):
                let angle = startAngle + sweep * eased
                position = Point(x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
            }
            return FingerSample(position: position, rippleProgress: segment.showsRipple ? linear : nil,
                                holdProgress: segment.showsHoldRing ? linear : nil)
        }
    }

    public enum Zone: Equatable, Sendable {
        case leftEdge, rightEdge, topEdge, bottomEdge
        case cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight
        case center
    }

    /// Static arrow hinting at the direction of travel.
    public struct Guide: Equatable, Sendable {
        public var from: Point
        public var to: Point
    }

    /// Fallback triggers: Control+Option plus a click or a scroll (no finger tracks).
    public enum ChordInput: Equatable, Sendable {
        case leftClick, rightClick, scrollUp, scrollDown, scrollLeft, scrollRight
    }

    public var fingers: [FingerTrack] = []
    public var zones: [Zone] = []
    public var guides: [Guide] = []
    public var chord: ChordInput?
    /// Seconds for one loop.
    public var loopDuration: TimeInterval = 2.0
    /// Representative phase drawn when the preview is not animating.
    public var posterPhase: Double = 0.3

    public init() {}

    /// Loop phase 0…1 for a wall-clock time.
    public func phase(at time: TimeInterval) -> Double {
        guard loopDuration > 0 else { return posterPhase }
        let value = (time / loopDuration).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }
}

// MARK: - Catalogue

extension GestureChoreography {
    public static func make(for kind: GestureKind) -> GestureChoreography {
        let descriptor = GestureDescriptor(kind)
        switch descriptor.base {
        case .tap:
            return taps(at: restingPoints(fingers: descriptor.fingers), windows: [(0.20, 0.42)])
        case .doubleTap:
            return taps(at: restingPoints(fingers: descriptor.fingers), windows: [(0.12, 0.28), (0.40, 0.56)])
        case .hold:
            var result = GestureChoreography()
            result.fingers = restingPoints(fingers: descriptor.fingers).map { point in
                FingerTrack(segments: [Segment(start: 0.10, end: 0.85, motion: .stay(point), showsHoldRing: true)])
            }
            result.loopDuration = 2.4
            result.posterPhase = 0.6
            return result
        case .swipe:
            return swipe(fingers: descriptor.fingers, variant: descriptor.variant)
        case .edgeSwipe:
            return edgeSwipe(variant: descriptor.variant)
        case .pinch:
            return pinch(outward: descriptor.variant == .outward)
        case .rotate:
            return rotate(clockwise: descriptor.variant == .clockwise)
        case .cornerTap:
            return cornerTap(variant: descriptor.variant)
        case .centerTap:
            var result = taps(at: [Point(x: 0.5, y: 0.5)], windows: [(0.20, 0.42)])
            result.zones = [.center]
            return result
        case .tapThenSwipe:
            return compound(variant: descriptor.variant, startsWithHold: false)
        case .holdThenSwipe:
            return compound(variant: descriptor.variant, startsWithHold: true)
        case .chordClick:
            var result = GestureChoreography()
            result.chord = descriptor.variant == .right ? .rightClick : .leftClick
            result.loopDuration = 1.6
            result.posterPhase = 0.25
            return result
        case .chordScroll:
            var result = GestureChoreography()
            result.chord = chordScroll(for: descriptor.variant)
            result.loopDuration = 1.6
            result.posterPhase = 0.5
            return result
        }
    }

    private static func chordScroll(for variant: GestureDescriptor.Variant) -> ChordInput {
        switch variant {
        case .down: return .scrollDown
        case .left: return .scrollLeft
        case .right: return .scrollRight
        default: return .scrollUp
        }
    }

    /// Where 1, 2 or 3 fingers rest (around the middle of the surface, slightly toward the front).
    private static func restingPoints(fingers: Int) -> [Point] {
        switch fingers {
        case 2: return [Point(x: 0.34, y: 0.60), Point(x: 0.66, y: 0.60)]
        case 3: return [Point(x: 0.24, y: 0.58), Point(x: 0.50, y: 0.64), Point(x: 0.76, y: 0.58)]
        default: return [Point(x: 0.50, y: 0.60)]
        }
    }

    private static func taps(at points: [Point], windows: [(Double, Double)]) -> GestureChoreography {
        var result = GestureChoreography()
        result.fingers = points.map { point in
            FingerTrack(segments: windows.map { window in
                Segment(start: window.0, end: window.1, motion: .stay(point), showsRipple: true)
            })
        }
        result.loopDuration = windows.count > 1 ? 1.8 : 1.5
        result.posterPhase = (windows[0].0 + windows[0].1) / 2
        return result
    }

    /// Unit travel for a direction. "Up" is toward the front edge (y grows).
    private static func travel(for variant: GestureDescriptor.Variant) -> Point {
        switch variant {
        case .left: return Point(x: -0.44, y: 0)
        case .right: return Point(x: 0.44, y: 0)
        case .down: return Point(x: 0, y: -0.36)
        default: return Point(x: 0, y: 0.36)
        }
    }

    private static func strokeSegments(from: Point, to: Point, start: Double, end: Double) -> [Segment] {
        let lead = (end - start) * 0.15
        return [
            Segment(start: start, end: start + lead, motion: .stay(from)),
            Segment(start: start + lead, end: end - lead, motion: .line(from: from, to: to)),
            Segment(start: end - lead, end: end, motion: .stay(to)),
        ]
    }

    private static func swipe(fingers: Int, variant: GestureDescriptor.Variant) -> GestureChoreography {
        var result = GestureChoreography()
        let delta = travel(for: variant)
        // Horizontal multi-finger swipes need narrower spacing to stay on the surface.
        let horizontal = delta.x != 0
        let scale = horizontal && fingers > 1 ? 0.6 : 1.0
        let vector = Point(x: delta.x * scale, y: delta.y)
        result.fingers = restingPoints(fingers: fingers).map { rest in
            let centre = Point(x: 0.5 + (rest.x - 0.5) * (horizontal ? 0.55 : 1), y: rest.y - 0.08)
            let from = Point(x: centre.x - vector.x / 2, y: centre.y - vector.y / 2)
            let to = Point(x: centre.x + vector.x / 2, y: centre.y + vector.y / 2)
            return FingerTrack(segments: strokeSegments(from: from, to: to, start: 0.12, end: 0.80))
        }
        let middle = Point(x: 0.5, y: 0.22)
        if horizontal {
            result.guides = [Guide(from: Point(x: middle.x - vector.x / 2, y: middle.y),
                                   to: Point(x: middle.x + vector.x / 2, y: middle.y))]
        } else {
            result.guides = [Guide(from: Point(x: 0.88, y: 0.5 - vector.y / 2), to: Point(x: 0.88, y: 0.5 + vector.y / 2))]
        }
        result.loopDuration = 1.9
        result.posterPhase = 0.46
        return result
    }

    private static func edgeSwipe(variant: GestureDescriptor.Variant) -> GestureChoreography {
        var result = GestureChoreography()
        let from: Point
        let to: Point
        switch variant {
        case .left:
            from = Point(x: 0.08, y: 0.30); to = Point(x: 0.08, y: 0.70); result.zones = [.leftEdge]
        case .right:
            from = Point(x: 0.92, y: 0.30); to = Point(x: 0.92, y: 0.70); result.zones = [.rightEdge]
        case .bottom:
            from = Point(x: 0.30, y: 0.08); to = Point(x: 0.70, y: 0.08); result.zones = [.bottomEdge]
        default:
            from = Point(x: 0.30, y: 0.92); to = Point(x: 0.70, y: 0.92); result.zones = [.topEdge]
        }
        // One stroke each way: the gesture is a slide along the strip.
        result.fingers = [FingerTrack(segments: strokeSegments(from: from, to: to, start: 0.06, end: 0.46)
            + strokeSegments(from: to, to: from, start: 0.54, end: 0.94))]
        result.loopDuration = 2.6
        result.posterPhase = 0.26
        return result
    }

    private static func pinch(outward: Bool) -> GestureChoreography {
        var result = GestureChoreography()
        let near: Double = 0.09
        let far: Double = 0.30
        let y: Double = 0.58
        let startOffset = outward ? near : far
        let endOffset = outward ? far : near
        result.fingers = [-1.0, 1.0].map { side in
            let from = Point(x: 0.5 + side * startOffset, y: y - side * startOffset * 0.25)
            let to = Point(x: 0.5 + side * endOffset, y: y - side * endOffset * 0.25)
            return FingerTrack(segments: strokeSegments(from: from, to: to, start: 0.12, end: 0.80))
        }
        result.loopDuration = 1.9
        result.posterPhase = 0.46
        return result
    }

    private static func rotate(clockwise: Bool) -> GestureChoreography {
        var result = GestureChoreography()
        let centre = Point(x: 0.5, y: 0.58)
        let radiusX: Double = 0.26
        // Keep the path circular in millimetres on the 52 × 90 mm surface.
        let radiusY: Double = radiusX * SurfaceGeometry.magicMouse.widthMM / SurfaceGeometry.magicMouse.heightMM
        let sweep: Double = (clockwise ? -1 : 1) * Double.pi * 0.45
        result.fingers = [0.0, Double.pi].map { offset in
            let startAngle = Double.pi * 0.25 + offset
            let begin = Point(x: centre.x + cos(startAngle) * radiusX, y: centre.y + sin(startAngle) * radiusY)
            let finish = Point(x: centre.x + cos(startAngle + sweep) * radiusX, y: centre.y + sin(startAngle + sweep) * radiusY)
            return FingerTrack(segments: [
                Segment(start: 0.12, end: 0.20, motion: .stay(begin)),
                Segment(start: 0.20, end: 0.72, motion: .arc(center: centre, radiusX: radiusX, radiusY: radiusY,
                                                             startAngle: startAngle, sweep: sweep)),
                Segment(start: 0.72, end: 0.80, motion: .stay(finish)),
            ])
        }
        result.loopDuration = 2.0
        result.posterPhase = 0.46
        return result
    }

    private static func cornerTap(variant: GestureDescriptor.Variant) -> GestureChoreography {
        let point: Point
        let zone: Zone
        switch variant {
        case .topRight: point = Point(x: 0.84, y: 0.86); zone = .cornerTopRight
        case .bottomLeft: point = Point(x: 0.16, y: 0.14); zone = .cornerBottomLeft
        case .bottomRight: point = Point(x: 0.84, y: 0.14); zone = .cornerBottomRight
        default: point = Point(x: 0.16, y: 0.86); zone = .cornerTopLeft
        }
        var result = taps(at: [point], windows: [(0.20, 0.42)])
        result.zones = [zone]
        return result
    }

    private static func compound(variant: GestureDescriptor.Variant, startsWithHold: Bool) -> GestureChoreography {
        var result = GestureChoreography()
        let delta = travel(for: variant)
        let centre = Point(x: 0.5, y: 0.52)
        let from = Point(x: centre.x - delta.x / 2, y: centre.y - delta.y / 2)
        let to = Point(x: centre.x + delta.x / 2, y: centre.y + delta.y / 2)
        if startsWithHold {
            // Hold, then slide without lifting.
            result.fingers = [FingerTrack(segments: [
                Segment(start: 0.06, end: 0.46, motion: .stay(from), showsHoldRing: true),
                Segment(start: 0.46, end: 0.80, motion: .line(from: from, to: to)),
                Segment(start: 0.80, end: 0.88, motion: .stay(to)),
            ])]
            result.posterPhase = 0.30
        } else {
            // Tap, lift, then touch again and slide.
            result.fingers = [FingerTrack(segments: [Segment(start: 0.06, end: 0.20, motion: .stay(from), showsRipple: true)]
                + strokeSegments(from: from, to: to, start: 0.32, end: 0.86))]
            result.posterPhase = 0.13
        }
        result.guides = [Guide(from: from, to: to)]
        result.loopDuration = 2.4
        return result
    }
}
