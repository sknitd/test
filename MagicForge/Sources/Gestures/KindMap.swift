import Foundation
import MFCore

/// Lookup helpers from (finger count, direction) to gesture kinds.
enum KindMap {
    static func tap(_ fingers: Int) -> GestureKind? {
        switch fingers {
        case 1: return .oneFingerTap
        case 2: return .twoFingerTap
        case 3: return .threeFingerTap
        default: return nil
        }
    }

    static func doubleTap(_ fingers: Int) -> GestureKind? {
        switch fingers {
        case 1: return .oneFingerDoubleTap
        case 2: return .twoFingerDoubleTap
        default: return nil
        }
    }

    static func hold(_ fingers: Int) -> GestureKind? {
        switch fingers {
        case 1: return .oneFingerHold
        case 2: return .twoFingerHold
        case 3: return .threeFingerHold
        default: return nil
        }
    }

    static func swipe(_ fingers: Int, _ direction: GestureKind.Direction) -> GestureKind? {
        switch (fingers, direction) {
        case (1, .left): return .oneFingerSwipeLeft
        case (1, .right): return .oneFingerSwipeRight
        case (1, .up): return .oneFingerSwipeUp
        case (1, .down): return .oneFingerSwipeDown
        case (2, .left): return .twoFingerSwipeLeft
        case (2, .right): return .twoFingerSwipeRight
        case (2, .up): return .twoFingerSwipeUp
        case (2, .down): return .twoFingerSwipeDown
        case (3, .left): return .threeFingerSwipeLeft
        case (3, .right): return .threeFingerSwipeRight
        case (3, .up): return .threeFingerSwipeUp
        case (3, .down): return .threeFingerSwipeDown
        default: return nil
        }
    }

    static func tapThenSwipe(_ direction: GestureKind.Direction) -> GestureKind {
        switch direction {
        case .left: return .tapThenSwipeLeft
        case .right: return .tapThenSwipeRight
        case .up: return .tapThenSwipeUp
        case .down: return .tapThenSwipeDown
        }
    }

    static func holdThenSwipe(_ direction: GestureKind.Direction) -> GestureKind {
        switch direction {
        case .left: return .holdThenSwipeLeft
        case .right: return .holdThenSwipeRight
        case .up: return .holdThenSwipeUp
        case .down: return .holdThenSwipeDown
        }
    }

    static let tapThenSwipeKinds: [GestureKind] = [.tapThenSwipeLeft, .tapThenSwipeRight, .tapThenSwipeUp,
                                                   .tapThenSwipeDown]

    static func isTapKind(_ kind: GestureKind) -> Bool {
        switch kind {
        case .oneFingerTap, .oneFingerDoubleTap, .twoFingerTap, .twoFingerDoubleTap, .threeFingerTap,
             .cornerTapTopLeft, .cornerTapTopRight, .cornerTapBottomLeft, .cornerTapBottomRight, .centerTap:
            return true
        default:
            return false
        }
    }

    static func isHoldKind(_ kind: GestureKind) -> Bool {
        kind == .oneFingerHold || kind == .twoFingerHold || kind == .threeFingerHold
    }
}

/// Cardinal direction of a displacement plus how far it deviates from that axis.
struct StrokeDirection {
    let direction: GestureKind.Direction
    let deviationDegrees: Double

    /// `dx` grows to the right, `dy` grows toward the front of the mouse ("up").
    init(dx: Double, dy: Double) {
        let ax = abs(dx), ay = abs(dy)
        if ax >= ay {
            direction = dx >= 0 ? .right : .left
            deviationDegrees = atan2(ay, ax) * 180 / .pi
        } else {
            direction = dy >= 0 ? .up : .down
            deviationDegrees = atan2(ax, ay) * 180 / .pi
        }
    }

    var isVertical: Bool { direction == .up || direction == .down }
}
