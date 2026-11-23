import Foundation
import MFCore

/// Building blocks: single-contact paths that tests and demos combine and `render`.
extension SyntheticTouch {
    /// A quick fingertip tap. Moves a deterministic 0.3 mm toward the front (no jitter).
    public static func tapPath(id: Int = 1, at point: Point, start: TimeInterval = 0, duration: TimeInterval = 0.07,
                               size: Double = 0.6, driftMM: Double = 0.3,
                               surface: SurfaceGeometry = .magicMouse) -> ContactPath {
        let drift = driftMM / max(surface.heightMM, 1)
        return ContactPath(id: id, start: start, duration: duration, size: size) { progress in
            Point(point.x, point.y + drift * progress)
        }
    }

    /// A straight stroke between two points.
    public static func linePath(id: Int = 1, from: Point, to: Point, start: TimeInterval = 0,
                                duration: TimeInterval = 0.2, easing: Easing = .easeInOut,
                                size: Double = 0.6) -> ContactPath {
        ContactPath(id: id, start: start, duration: duration, size: size) { progress in
            let t = easing.apply(progress)
            return Point(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t)
        }
    }

    /// A deliberate fingertip hold: stays put apart from a 0.2 mm settle.
    public static func holdPath(id: Int = 1, at point: Point, start: TimeInterval = 0, duration: TimeInterval = 0.65,
                                size: Double = 0.6, surface: SurfaceGeometry = .magicMouse) -> ContactPath {
        let settle = 0.2 / max(surface.heightMM, 1)
        return ContactPath(id: id, start: start, duration: duration, size: size) { progress in
            Point(point.x, point.y - settle * min(progress * 4, 1))
        }
    }

    /// Holds still for `holdDuration`, then strokes to `to` (hold-then-swipe).
    public static func holdThenLinePath(id: Int = 1, from: Point, to: Point, start: TimeInterval = 0,
                                        holdDuration: TimeInterval = 0.62, strokeDuration: TimeInterval = 0.2,
                                        size: Double = 0.6) -> ContactPath {
        let total = holdDuration + strokeDuration
        return ContactPath(id: id, start: start, duration: total, size: size) { progress in
            let elapsed = progress * total
            guard elapsed > holdDuration, strokeDuration > 0 else { return from }
            let t = Easing.easeInOut.apply((elapsed - holdDuration) / strokeDuration)
            return Point(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t)
        }
    }

    /// A finger gripping / resting on the shell: a flat (large) contact that wobbles by a
    /// fraction of a millimetre for a long time.
    public static func restingPath(id: Int, at point: Point, start: TimeInterval = 0, duration: TimeInterval = 3,
                                   size: Double = 1.3, wobbleMM: Double = 0.3,
                                   surface: SurfaceGeometry = .magicMouse) -> ContactPath {
        let rx = wobbleMM / max(surface.widthMM, 1), ry = wobbleMM / max(surface.heightMM, 1)
        return ContactPath(id: id, start: start, duration: duration, size: size) { progress in
            let angle = progress * duration / 1.5 * 2 * Double.pi
            return Point(point.x + rx * sin(angle), point.y + ry * (1 - cos(angle)))
        }
    }

    /// A palm-sized contact near the rear of the mouse.
    public static func palmPath(id: Int, at point: Point = Point(0.5, 0.1), start: TimeInterval = 0,
                                duration: TimeInterval = 1.0, size: Double = 2.8,
                                surface: SurfaceGeometry = .magicMouse) -> ContactPath {
        restingPath(id: id, at: point, start: start, duration: duration, size: size, wobbleMM: 0.6,
                    surface: surface)
    }

    /// A finger creeping at constant speed, far too slowly to be a swipe.
    public static func slowDriftPath(id: Int = 1, from: Point, to: Point, start: TimeInterval = 0,
                                     duration: TimeInterval = 2.5, size: Double = 0.6) -> ContactPath {
        linePath(id: id, from: from, to: to, start: start, duration: duration, easing: .linear, size: size)
    }

    /// A contact travelling on a circle around `center` (used for rotate gestures).
    /// Angles are degrees, counterclockwise seen from above, 0° = toward the right edge.
    public static func arcPath(id: Int, center: Point, radiusMM: Double, fromDegrees: Double, toDegrees: Double,
                               start: TimeInterval = 0, duration: TimeInterval = 0.25, easing: Easing = .easeInOut,
                               size: Double = 0.6, surface: SurfaceGeometry = .magicMouse) -> ContactPath {
        let rx = radiusMM / max(surface.widthMM, 1), ry = radiusMM / max(surface.heightMM, 1)
        return ContactPath(id: id, start: start, duration: duration, size: size) { progress in
            let degrees = fromDegrees + (toDegrees - fromDegrees) * easing.apply(progress)
            let radians = degrees * Double.pi / 180
            return Point(center.x + rx * cos(radians), center.y + ry * sin(radians))
        }
    }

    /// The touch that accompanies a physical click: the finger presses the shell, the contact
    /// grows as the shell gives way, and it lifts again. `clickTime` is when the button goes
    /// down; pass it to `GestureRecognizing.notePhysicalClick(at:)`.
    public static func physicalClickTouch(startTime: TimeInterval, at point: Point = Point(0.4, 0.8),
                                          duration: TimeInterval = 0.14, frameInterval: TimeInterval = 0.011)
        -> (frames: [TouchFrame], clickTime: TimeInterval) {
        let path = tapPath(id: 1, at: point, start: 0, duration: duration, size: 0.9, driftMM: 0.5)
        return (render([path], startTime: startTime, frameInterval: frameInterval), startTime + duration * 0.4)
    }

    /// Seeded scroll-like motion of one fingertip: many strokes up and down the middle of the
    /// surface at varied speeds, each starting to move immediately and travelling at least 6 mm.
    public static func scrollPaths(seed: UInt64, duration: TimeInterval, firstID: Int = 100,
                                   surface: SurfaceGeometry = .magicMouse) -> [ContactPath] {
        var generator = LCG(seed: seed)
        var paths: [ContactPath] = []
        var cursor = 0.0
        var id = firstID
        while cursor < duration {
            let travelMM = generator.range(6, 34)
            let speed = generator.range(15, 240)
            let strokeDuration = max(travelMM / speed, 0.04)
            let x = generator.range(0.36, 0.64)
            let wobble = generator.range(-1.5, 1.5) / max(surface.widthMM, 1)
            let travel = travelMM / max(surface.heightMM, 1)
            let up = generator.unit() < 0.5
            let startY = up ? generator.range(0.25, 0.75 - travel) : generator.range(0.25 + travel, 0.75)
            let endY = up ? startY + travel : startY - travel
            paths.append(linePath(id: id, from: Point(x, startY), to: Point(x + wobble, endY), start: cursor,
                                  duration: strokeDuration, easing: generator.unit() < 0.5 ? .linear : .easeInOut))
            id += 1
            cursor += strokeDuration + generator.range(0.08, 0.6)
        }
        return paths
    }

    /// Seeded "hand on the mouse" noise with no deliberate gesture in it: resting fingers that
    /// land and lift on the sides, scroll strokes in the middle, palm contacts at the rear,
    /// slow creeping flat contacts and single-frame sensor blips, freely overlapping.
    public static func noisePaths(seed: UInt64, duration: TimeInterval, frameInterval: TimeInterval = 0.011,
                                  surface: SurfaceGeometry = .magicMouse) -> [ContactPath] {
        var generator = LCG(seed: seed)
        var paths: [ContactPath] = scrollPaths(seed: seed ^ 0x9E3779B97F4A7C15, duration: duration,
                                               firstID: 100_000, surface: surface)
        var cursor = 0.0
        var id = 1
        while cursor < duration {
            let start = cursor + generator.range(0, 0.4)
            switch generator.int(10) {
            case 0, 1, 2, 3:
                let leftSide = generator.unit() < 0.5
                let x = leftSide ? generator.range(0.08, 0.22) : generator.range(0.78, 0.92)
                paths.append(restingPath(id: id, at: Point(x, generator.range(0.3, 0.7)), start: start,
                                         duration: generator.range(0.5, 4), size: generator.range(1.15, 1.6),
                                         surface: surface))
            case 4, 5:
                paths.append(palmPath(id: id, at: Point(generator.range(0.2, 0.8), generator.range(0.03, 0.18)),
                                      start: start, duration: generator.range(0.3, 1.5),
                                      size: generator.range(2.5, 3.0), surface: surface))
            case 6, 7:
                let from = Point(generator.range(0.2, 0.8), generator.range(0.3, 0.7))
                let dx = generator.range(-6, 6) / max(surface.widthMM, 1)
                let dy = generator.range(-8, 8) / max(surface.heightMM, 1)
                paths.append(slowDriftPath(id: id, from: from, to: Point(from.x + dx, from.y + dy), start: start,
                                           duration: generator.range(1.5, 3), size: generator.range(1.15, 1.5)))
            default:
                // Sensor blip: present in exactly one frame.
                let aligned = (start / frameInterval).rounded() * frameInterval
                paths.append(tapPath(id: id, at: Point(generator.range(0.05, 0.95), generator.range(0.05, 0.95)),
                                     start: aligned, duration: frameInterval * 0.9, size: 0.3, driftMM: 0,
                                     surface: surface))
            }
            id += 1
            cursor += generator.range(0.15, 0.9)
        }
        return paths
    }
}
