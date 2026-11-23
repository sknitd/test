import SwiftUI
import MFCore

/// Draws one phase of a `GestureChoreography` into a Canvas. Stateless.
enum GesturePreviewRenderer {
    static func draw(_ choreography: GestureChoreography, phase: Double, in context: inout GraphicsContext,
                     size: CGSize, edgeFraction: Double, cornerFraction: Double) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        guard bounds.width > 8, bounds.height > 8 else { return }
        if let chord = choreography.chord {
            drawChord(chord, phase: phase, in: &context, bounds: bounds)
            return
        }
        let surface: CGRect = MouseSurfaceShape.surfaceRect(in: bounds)
        let outline: Path = MouseSurfaceShape.outline(for: surface)
        drawBody(outline, in: &context)

        var zoneContext = context
        zoneContext.clip(to: outline)
        for zone in choreography.zones {
            let rect = MouseSurfaceZones.rect(for: zone, in: surface, edgeFraction: edgeFraction,
                                              cornerFraction: cornerFraction)
            zoneContext.fill(Path(rect), with: .color(Color.accentColor.opacity(0.22)))
        }
        for guide in choreography.guides {
            let from = MouseSurfaceShape.point(x: guide.from.x, y: guide.from.y, in: surface)
            let to = MouseSurfaceShape.point(x: guide.to.x, y: guide.to.y, in: surface)
            context.stroke(arrow(from: from, to: to, headLength: surface.width * 0.07),
                           with: .color(Color.secondary.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3]))
        }
        let radius: CGFloat = surface.width * 0.085
        for track in choreography.fingers {
            guard let sample = track.sample(at: phase) else { continue }
            let centre = MouseSurfaceShape.point(x: sample.position.x, y: sample.position.y, in: surface)
            drawFinger(sample, at: centre, radius: radius, in: &context)
        }
    }

    static func drawBody(_ outline: Path, in context: inout GraphicsContext) {
        context.fill(outline, with: .color(Color.primary.opacity(0.06)))
        context.stroke(outline, with: .color(Color.secondary.opacity(0.7)), lineWidth: 1.5)
    }

    private static func drawFinger(_ sample: GestureChoreography.FingerSample, at centre: CGPoint, radius: CGFloat,
                                   in context: inout GraphicsContext) {
        if let ripple = sample.rippleProgress {
            let rippleRadius: CGFloat = radius * (1 + 1.6 * CGFloat(ripple))
            let ring = Path(ellipseIn: CGRect(x: centre.x - rippleRadius, y: centre.y - rippleRadius,
                                              width: rippleRadius * 2, height: rippleRadius * 2))
            context.stroke(ring, with: .color(Color.accentColor.opacity(0.8 * (1 - ripple))), lineWidth: 2)
        }
        let dot = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        context.fill(dot, with: .color(Color.accentColor.opacity(0.85)))
        if let hold = sample.holdProgress {
            let ringRadius: CGFloat = radius * 1.7
            var track = Path()
            track.addArc(center: centre, radius: ringRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(Color.secondary.opacity(0.3)), lineWidth: 3)
            var progress = Path()
            progress.addArc(center: centre, radius: ringRadius, startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * hold), clockwise: false)
            context.stroke(progress, with: .color(Color.accentColor),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// A straight arrow with a two-stroke head at `to`.
    static func arrow(from: CGPoint, to: CGPoint, headLength: CGFloat) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let angle: CGFloat = atan2(to.y - from.y, to.x - from.x)
        let spread: CGFloat = 0.5
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - headLength * cos(angle - spread), y: to.y - headLength * sin(angle - spread)))
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - headLength * cos(angle + spread), y: to.y - headLength * sin(angle + spread)))
        return path
    }

    // MARK: Fallback chords (Control + Option + click / scroll)

    private static func drawChord(_ chord: GestureChoreography.ChordInput, phase: Double,
                                  in context: inout GraphicsContext, bounds: CGRect) {
        let keySide: CGFloat = min(bounds.width * 0.3, bounds.height * 0.2)
        let keyTop: CGFloat = bounds.minY + 2
        let gap: CGFloat = keySide * 0.25
        let rowWidth: CGFloat = keySide * 2 + gap
        let firstKey = CGRect(x: bounds.midX - rowWidth / 2, y: keyTop, width: keySide, height: keySide)
        let secondKey = firstKey.offsetBy(dx: keySide + gap, dy: 0)
        drawKeycap("⌃", in: firstKey, context: &context)
        drawKeycap("⌥", in: secondKey, context: &context)

        let plusCentre = CGPoint(x: bounds.midX, y: firstKey.maxY + keySide * 0.3)
        context.draw(Text("+").font(.system(size: keySide * 0.42, weight: .semibold)).foregroundColor(Color.secondary),
                     at: plusCentre, anchor: .center)

        let mouseArea = CGRect(x: bounds.minX, y: plusCentre.y + keySide * 0.3, width: bounds.width,
                               height: max(bounds.maxY - plusCentre.y - keySide * 0.3, 1))
        let surface: CGRect = MouseSurfaceShape.surfaceRect(in: mouseArea)
        let outline: Path = MouseSurfaceShape.outline(for: surface)
        drawBody(outline, in: &context)
        // A soft pulse per loop.
        let pulse: Double = 0.5 - 0.5 * cos(phase * 2 * Double.pi)
        switch chord {
        case .leftClick, .rightClick:
            let isLeft: Bool = chord == .leftClick
            let half = CGRect(x: isLeft ? surface.minX : surface.midX, y: surface.minY, width: surface.width / 2,
                              height: surface.height * 0.42)
            var clipped = context
            clipped.clip(to: outline)
            clipped.fill(Path(half), with: .color(Color.accentColor.opacity(0.25 + 0.55 * pulse)))
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            let length: CGFloat = surface.width * 0.5
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if chord == .scrollUp { dy = -1 }
            if chord == .scrollDown { dy = 1 }
            if chord == .scrollLeft { dx = -1 }
            if chord == .scrollRight { dx = 1 }
            // The arrow drifts along its direction during the loop.
            let drift: CGFloat = (CGFloat(phase) - 0.5) * length * 0.5
            let centre = CGPoint(x: surface.midX + dx * drift, y: surface.midY + dy * drift)
            let from = CGPoint(x: centre.x - dx * length / 2, y: centre.y - dy * length / 2)
            let to = CGPoint(x: centre.x + dx * length / 2, y: centre.y + dy * length / 2)
            context.stroke(arrow(from: from, to: to, headLength: surface.width * 0.16),
                           with: .color(Color.accentColor.opacity(0.45 + 0.5 * pulse)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawKeycap(_ glyph: String, in rect: CGRect, context: inout GraphicsContext) {
        let cap = Path(roundedRect: rect, cornerRadius: rect.width * 0.2, style: .continuous)
        context.fill(cap, with: .color(Color.primary.opacity(0.08)))
        context.stroke(cap, with: .color(Color.secondary.opacity(0.7)), lineWidth: 1)
        context.draw(Text(glyph).font(.system(size: rect.height * 0.5, weight: .medium)).foregroundColor(Color.primary),
                     at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}
