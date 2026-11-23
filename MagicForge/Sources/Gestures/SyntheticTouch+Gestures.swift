import Foundation
import MFCore

/// Canonical synthetic stream for every raw-contact gesture kind.
extension SyntheticTouch {
    /// A realistic frame stream that performs `kind` once. Fallback (pointer-event) kinds have
    /// no touch representation and return an empty array.
    public static func frames(for kind: GestureKind, startTime: TimeInterval,
                              surface: SurfaceGeometry = .magicMouse,
                              frameInterval: TimeInterval = 0.011) -> [TouchFrame] {
        render(paths(for: kind, surface: surface), startTime: startTime, frameInterval: frameInterval)
    }

    /// The contact paths behind `frames(for:)`, for callers that want to add resting fingers,
    /// palms or other building blocks before rendering.
    public static func paths(for kind: GestureKind, surface: SurfaceGeometry = .magicMouse) -> [ContactPath] {
        let plainSpot = Point(0.5, 0.80)   // outside the corner and centre zones
        let pairLeft = Point(0.38, 0.6), pairRight = Point(0.62, 0.6)
        let trio = [Point(0.27, 0.58), Point(0.5, 0.62), Point(0.73, 0.58)]
        let tapGap = 0.11, tapLength = 0.07

        switch kind {
        case .oneFingerTap:
            return [tapPath(id: 1, at: plainSpot, surface: surface)]
        case .oneFingerDoubleTap:
            return [tapPath(id: 1, at: plainSpot, surface: surface),
                    tapPath(id: 2, at: plainSpot, start: tapLength + tapGap, surface: surface)]
        case .oneFingerHold:
            return [holdPath(id: 1, at: plainSpot, surface: surface)]
        case .leftEdgeSwipe:
            return [linePath(id: 1, from: Point(0.08, 0.30), to: Point(0.08, 0.70), duration: 0.22)]
        case .rightEdgeSwipe:
            return [linePath(id: 1, from: Point(0.92, 0.70), to: Point(0.92, 0.30), duration: 0.22)]
        case .topEdgeSwipe:
            return [linePath(id: 1, from: Point(0.22, 0.92), to: Point(0.78, 0.92), duration: 0.2)]
        case .bottomEdgeSwipe:
            return [linePath(id: 1, from: Point(0.78, 0.08), to: Point(0.22, 0.08), duration: 0.2)]
        case .oneFingerSwipeLeft, .oneFingerSwipeRight, .oneFingerSwipeUp, .oneFingerSwipeDown:
            let ends = strokeEnds(for: kind.strokeDirection, surface: surface)
            return [linePath(id: 1, from: ends.from, to: ends.to)]
        case .twoFingerTap:
            return [tapPath(id: 1, at: pairLeft, surface: surface), tapPath(id: 2, at: pairRight, surface: surface)]
        case .twoFingerDoubleTap:
            let second = tapLength + tapGap
            return [tapPath(id: 1, at: pairLeft, surface: surface), tapPath(id: 2, at: pairRight, surface: surface),
                    tapPath(id: 3, at: pairLeft, start: second, surface: surface),
                    tapPath(id: 4, at: pairRight, start: second, surface: surface)]
        case .twoFingerHold:
            return [holdPath(id: 1, at: pairLeft, surface: surface), holdPath(id: 2, at: pairRight, surface: surface)]
        case .twoFingerSwipeLeft, .twoFingerSwipeRight, .twoFingerSwipeUp, .twoFingerSwipeDown:
            return parallelStrokes(direction: kind.strokeDirection, offsets: [-0.12, 0.12], surface: surface)
        case .pinchIn:
            return [linePath(id: 1, from: Point(0.5, 0.72), to: Point(0.5, 0.59), duration: 0.25),
                    linePath(id: 2, from: Point(0.5, 0.28), to: Point(0.5, 0.41), duration: 0.25)]
        case .pinchOut:
            return [linePath(id: 1, from: Point(0.5, 0.59), to: Point(0.5, 0.72), duration: 0.25),
                    linePath(id: 2, from: Point(0.5, 0.41), to: Point(0.5, 0.28), duration: 0.25)]
        case .rotateClockwise, .rotateCounterclockwise:
            let sweep: Double = kind == .rotateCounterclockwise ? 40 : -40
            let center = Point(0.5, 0.5)
            return [arcPath(id: 1, center: center, radiusMM: 12, fromDegrees: 20, toDegrees: 20 + sweep,
                            surface: surface),
                    arcPath(id: 2, center: center, radiusMM: 12, fromDegrees: 200, toDegrees: 200 + sweep,
                            surface: surface)]
        case .threeFingerTap:
            return trio.enumerated().map { tapPath(id: $0.offset + 1, at: $0.element, surface: surface) }
        case .threeFingerHold:
            return trio.enumerated().map { holdPath(id: $0.offset + 1, at: $0.element, surface: surface) }
        case .threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp, .threeFingerSwipeDown:
            return parallelStrokes(direction: kind.strokeDirection, offsets: [-0.19, 0, 0.19], surface: surface)
        case .cornerTapTopLeft:
            return [tapPath(id: 1, at: Point(0.12, 0.88), surface: surface)]
        case .cornerTapTopRight:
            return [tapPath(id: 1, at: Point(0.88, 0.88), surface: surface)]
        case .cornerTapBottomLeft:
            return [tapPath(id: 1, at: Point(0.12, 0.12), surface: surface)]
        case .cornerTapBottomRight:
            return [tapPath(id: 1, at: Point(0.88, 0.12), surface: surface)]
        case .centerTap:
            return [tapPath(id: 1, at: Point(0.5, 0.5), surface: surface)]
        case .tapThenSwipeLeft, .tapThenSwipeRight, .tapThenSwipeUp, .tapThenSwipeDown:
            let ends = strokeEnds(for: kind.strokeDirection, surface: surface)
            return [tapPath(id: 1, at: ends.from, surface: surface),
                    linePath(id: 2, from: ends.from, to: ends.to, start: tapLength + tapGap)]
        case .holdThenSwipeLeft, .holdThenSwipeRight, .holdThenSwipeUp, .holdThenSwipeDown:
            let ends = strokeEnds(for: kind.strokeDirection, surface: surface)
            return [holdThenLinePath(id: 1, from: ends.from, to: ends.to)]
        case .chordLeftClick, .chordRightClick, .chordScrollUp, .chordScrollDown, .chordScrollLeft,
             .chordScrollRight:
            return []
        }
    }

    /// Several different gestures separated by pauses, for the Touch Lab demo.
    public static func demoReel(startTime: TimeInterval) -> [TouchFrame] {
        let reel: [GestureKind] = [.oneFingerTap, .oneFingerDoubleTap, .twoFingerTap, .twoFingerSwipeLeft,
                                   .twoFingerSwipeRight, .pinchOut, .pinchIn, .rotateClockwise,
                                   .threeFingerSwipeUp, .leftEdgeSwipe, .cornerTapTopRight, .oneFingerHold,
                                   .tapThenSwipeRight, .holdThenSwipeDown]
        var frames: [TouchFrame] = []
        var cursor = startTime
        for kind in reel {
            let segment = self.frames(for: kind, startTime: cursor)
            frames.append(contentsOf: segment)
            cursor = (segment.last?.timestamp ?? cursor) + 0.9
        }
        return frames
    }

    // MARK: Layout helpers

    /// Start and end of a one-finger stroke through the middle of the surface: about 26 mm
    /// horizontally or 36 mm vertically on the default geometry, clear of the edge strips.
    static func strokeEnds(for direction: GestureKind.Direction, surface: SurfaceGeometry) -> (from: Point, to: Point) {
        let half = travel(for: direction, surface: surface) / 2
        switch direction {
        case .left: return (Point(0.5 + half, 0.5), Point(0.5 - half, 0.5))
        case .right: return (Point(0.5 - half, 0.5), Point(0.5 + half, 0.5))
        case .up: return (Point(0.5, 0.5 - half), Point(0.5, 0.5 + half))
        case .down: return (Point(0.5, 0.5 + half), Point(0.5, 0.5 - half))
        }
    }

    /// Normalized stroke length: 26 mm across, 36 mm along, capped to stay on the surface.
    private static func travel(for direction: GestureKind.Direction, surface: SurfaceGeometry) -> Double {
        switch direction {
        case .left, .right: return min(26 / max(surface.widthMM, 1), 0.5)
        case .up, .down: return min(36 / max(surface.heightMM, 1), 0.5)
        }
    }

    /// Fingers side by side (offsets across the stroke) all making the same stroke.
    private static func parallelStrokes(direction: GestureKind.Direction, offsets: [Double],
                                        surface: SurfaceGeometry) -> [ContactPath] {
        let vertical = direction == .up || direction == .down
        // Horizontal multi-finger strokes are shorter so every finger stays on the surface.
        let length = vertical ? travel(for: direction, surface: surface)
                              : min(22 / max(surface.widthMM, 1), 0.44)
        let sign: Double = (direction == .right || direction == .up) ? 1 : -1
        var paths: [ContactPath] = []
        for (index, offset) in offsets.enumerated() {
            let from: Point, to: Point
            if vertical {
                from = Point(0.5 + offset, 0.5 - sign * length / 2)
                to = Point(0.5 + offset, 0.5 + sign * length / 2)
            } else {
                // Fingers sit side by side even for sideways strokes (as a hand does).
                let compressed = offset * 0.6
                from = Point(0.5 + compressed - sign * length / 2, 0.6)
                to = Point(0.5 + compressed + sign * length / 2, 0.6)
            }
            paths.append(linePath(id: index + 1, from: from, to: to))
        }
        return paths
    }
}

extension GestureKind {
    /// Direction of the stroke for directional kinds (`.right` for everything else).
    var strokeDirection: GestureKind.Direction {
        switch self {
        case .oneFingerSwipeLeft, .twoFingerSwipeLeft, .threeFingerSwipeLeft, .tapThenSwipeLeft, .holdThenSwipeLeft:
            return .left
        case .oneFingerSwipeUp, .twoFingerSwipeUp, .threeFingerSwipeUp, .tapThenSwipeUp, .holdThenSwipeUp:
            return .up
        case .oneFingerSwipeDown, .twoFingerSwipeDown, .threeFingerSwipeDown, .tapThenSwipeDown, .holdThenSwipeDown:
            return .down
        default:
            return .right
        }
    }
}
