import Foundation
import MFCore

/// Structural description of a gesture kind: what the fingers do, how many there are and which
/// variant (direction, edge, corner…) it is. Drives the preview choreography and the
/// "same gesture, different finger count / direction" selectors in Gesture Studio.
struct GestureDescriptor: Equatable, Sendable {
    enum Base: Equatable, Sendable {
        case tap, doubleTap, hold, swipe, edgeSwipe, pinch, rotate, cornerTap, centerTap
        case tapThenSwipe, holdThenSwipe, chordClick, chordScroll
    }

    enum Variant: Equatable, Sendable {
        case none, left, right, up, down, top, bottom, inward, outward, clockwise, counterclockwise
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var base: Base
    var fingers: Int
    var variant: Variant

    init(base: Base, fingers: Int, variant: Variant) {
        self.base = base; self.fingers = fingers; self.variant = variant
    }

    // Exhaustive on purpose: adding a GestureKind must fail to compile here.
    init(_ kind: GestureKind) {
        switch kind {
        case .oneFingerTap: self.init(base: .tap, fingers: 1, variant: .none)
        case .oneFingerDoubleTap: self.init(base: .doubleTap, fingers: 1, variant: .none)
        case .oneFingerHold: self.init(base: .hold, fingers: 1, variant: .none)
        case .leftEdgeSwipe: self.init(base: .edgeSwipe, fingers: 1, variant: .left)
        case .rightEdgeSwipe: self.init(base: .edgeSwipe, fingers: 1, variant: .right)
        case .topEdgeSwipe: self.init(base: .edgeSwipe, fingers: 1, variant: .top)
        case .bottomEdgeSwipe: self.init(base: .edgeSwipe, fingers: 1, variant: .bottom)
        case .oneFingerSwipeLeft: self.init(base: .swipe, fingers: 1, variant: .left)
        case .oneFingerSwipeRight: self.init(base: .swipe, fingers: 1, variant: .right)
        case .oneFingerSwipeUp: self.init(base: .swipe, fingers: 1, variant: .up)
        case .oneFingerSwipeDown: self.init(base: .swipe, fingers: 1, variant: .down)
        case .twoFingerTap: self.init(base: .tap, fingers: 2, variant: .none)
        case .twoFingerDoubleTap: self.init(base: .doubleTap, fingers: 2, variant: .none)
        case .twoFingerHold: self.init(base: .hold, fingers: 2, variant: .none)
        case .twoFingerSwipeLeft: self.init(base: .swipe, fingers: 2, variant: .left)
        case .twoFingerSwipeRight: self.init(base: .swipe, fingers: 2, variant: .right)
        case .twoFingerSwipeUp: self.init(base: .swipe, fingers: 2, variant: .up)
        case .twoFingerSwipeDown: self.init(base: .swipe, fingers: 2, variant: .down)
        case .pinchIn: self.init(base: .pinch, fingers: 2, variant: .inward)
        case .pinchOut: self.init(base: .pinch, fingers: 2, variant: .outward)
        case .rotateClockwise: self.init(base: .rotate, fingers: 2, variant: .clockwise)
        case .rotateCounterclockwise: self.init(base: .rotate, fingers: 2, variant: .counterclockwise)
        case .threeFingerTap: self.init(base: .tap, fingers: 3, variant: .none)
        case .threeFingerHold: self.init(base: .hold, fingers: 3, variant: .none)
        case .threeFingerSwipeLeft: self.init(base: .swipe, fingers: 3, variant: .left)
        case .threeFingerSwipeRight: self.init(base: .swipe, fingers: 3, variant: .right)
        case .threeFingerSwipeUp: self.init(base: .swipe, fingers: 3, variant: .up)
        case .threeFingerSwipeDown: self.init(base: .swipe, fingers: 3, variant: .down)
        case .cornerTapTopLeft: self.init(base: .cornerTap, fingers: 1, variant: .topLeft)
        case .cornerTapTopRight: self.init(base: .cornerTap, fingers: 1, variant: .topRight)
        case .cornerTapBottomLeft: self.init(base: .cornerTap, fingers: 1, variant: .bottomLeft)
        case .cornerTapBottomRight: self.init(base: .cornerTap, fingers: 1, variant: .bottomRight)
        case .centerTap: self.init(base: .centerTap, fingers: 1, variant: .none)
        case .tapThenSwipeLeft: self.init(base: .tapThenSwipe, fingers: 1, variant: .left)
        case .tapThenSwipeRight: self.init(base: .tapThenSwipe, fingers: 1, variant: .right)
        case .tapThenSwipeUp: self.init(base: .tapThenSwipe, fingers: 1, variant: .up)
        case .tapThenSwipeDown: self.init(base: .tapThenSwipe, fingers: 1, variant: .down)
        case .holdThenSwipeLeft: self.init(base: .holdThenSwipe, fingers: 1, variant: .left)
        case .holdThenSwipeRight: self.init(base: .holdThenSwipe, fingers: 1, variant: .right)
        case .holdThenSwipeUp: self.init(base: .holdThenSwipe, fingers: 1, variant: .up)
        case .holdThenSwipeDown: self.init(base: .holdThenSwipe, fingers: 1, variant: .down)
        case .chordLeftClick: self.init(base: .chordClick, fingers: 0, variant: .left)
        case .chordRightClick: self.init(base: .chordClick, fingers: 0, variant: .right)
        case .chordScrollUp: self.init(base: .chordScroll, fingers: 0, variant: .up)
        case .chordScrollDown: self.init(base: .chordScroll, fingers: 0, variant: .down)
        case .chordScrollLeft: self.init(base: .chordScroll, fingers: 0, variant: .left)
        case .chordScrollRight: self.init(base: .chordScroll, fingers: 0, variant: .right)
        }
    }

    /// Which per-binding duration override means something for this gesture.
    enum DurationRole: Equatable, Sendable { case none, tap, hold }

    var durationRole: DurationRole {
        switch base {
        case .tap, .doubleTap, .cornerTap, .centerTap, .tapThenSwipe: return .tap
        case .hold, .holdThenSwipe: return .hold
        case .swipe, .edgeSwipe, .pinch, .rotate, .chordClick, .chordScroll: return .none
        }
    }

    var variantLabel: String {
        switch variant {
        case .none: return "Default"
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Up"
        case .down: return "Down"
        case .top: return "Front"
        case .bottom: return "Rear"
        case .inward: return "In"
        case .outward: return "Out"
        case .clockwise: return "Clockwise"
        case .counterclockwise: return "Counterclockwise"
        case .topLeft: return "Front left"
        case .topRight: return "Front right"
        case .bottomLeft: return "Rear left"
        case .bottomRight: return "Rear right"
        }
    }
}

/// Gestures that are the same movement with a different finger count or variant.
enum GestureFamily {
    /// Same movement and variant with 1 / 2 / 3 fingers, ordered by finger count (includes `kind`).
    static func fingerVariants(of kind: GestureKind) -> [GestureKind] {
        let own = GestureDescriptor(kind)
        return GestureKind.allCases
            .filter { candidate in
                let other = GestureDescriptor(candidate)
                return other.base == own.base && other.variant == own.variant
            }
            .sorted { GestureDescriptor($0).fingers < GestureDescriptor($1).fingers }
    }

    /// Same movement and finger count in another direction / edge / corner (includes `kind`).
    static func variantSiblings(of kind: GestureKind) -> [GestureKind] {
        let own = GestureDescriptor(kind)
        return GestureKind.allCases.filter { candidate in
            let other = GestureDescriptor(candidate)
            return other.base == own.base && other.fingers == own.fingers
        }
    }
}
