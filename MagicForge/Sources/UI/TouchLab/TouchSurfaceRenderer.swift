import SwiftUI
import MFCore

/// Draws a `TouchFeed.Snapshot` on the stylized mouse surface. Stateless; called once per
/// display frame from a Canvas. Only draws what the snapshot contains.
enum TouchSurfaceRenderer {
    struct Options: Equatable {
        var showZones: Bool
        var edgeFraction: Double
        var cornerFraction: Double
        var trailLifetime: TimeInterval
        /// False when no adapter delivers raw contacts: stale non-synthetic frames are then not drawn.
        var liveInputAvailable: Bool
        var isPaused: Bool
    }

    static func draw(_ snapshot: TouchFeed.Snapshot, now: TimeInterval, options: Options,
                     in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        guard bounds.width > 20, bounds.height > 20 else { return }
        let surface: CGRect = MouseSurfaceShape.surfaceRect(in: bounds)
        let outline: Path = MouseSurfaceShape.outline(for: surface)
        GesturePreviewRenderer.drawBody(outline, in: &context)
        if options.showZones { drawZones(surface: surface, outline: outline, options: options, in: &context) }

        let showsData: Bool = options.liveInputAvailable || snapshot.isSynthetic
        guard showsData else { return }
        // While paused the picture is frozen at the last frame instead of fading out.
        let reference: TimeInterval = options.isPaused ? (snapshot.latest?.timestamp ?? now) : now
        drawTrails(snapshot, reference: reference, surface: surface, lifetime: options.trailLifetime, in: &context)
        drawContacts(snapshot, surface: surface, in: &context)
        if snapshot.isSynthetic && snapshot.latest != nil { drawSyntheticBadge(surface: surface, in: &context) }
    }

    static func color(forContact id: Int) -> Color {
        let palette: [Color] = [Color.blue, Color.green, Color.orange, Color.purple, Color.pink, Color.teal]
        let index: Int = ((id % palette.count) + palette.count) % palette.count
        return palette[index]
    }

    private static func drawZones(surface: CGRect, outline: Path, options: Options, in context: inout GraphicsContext) {
        var clipped = context
        clipped.clip(to: outline)
        let dash = StrokeStyle(lineWidth: 1, dash: [4, 3])
        let edges: [GestureChoreography.Zone] = [.leftEdge, .rightEdge, .topEdge, .bottomEdge]
        for zone in edges {
            let rect = MouseSurfaceZones.rect(for: zone, in: surface, edgeFraction: options.edgeFraction,
                                              cornerFraction: options.cornerFraction)
            clipped.fill(Path(rect), with: .color(Color.accentColor.opacity(0.07)))
            clipped.stroke(Path(rect), with: .color(Color.accentColor.opacity(0.5)), style: dash)
        }
        let corners: [GestureChoreography.Zone] = [.cornerTopLeft, .cornerTopRight, .cornerBottomLeft, .cornerBottomRight]
        for zone in corners {
            let rect = MouseSurfaceZones.rect(for: zone, in: surface, edgeFraction: options.edgeFraction,
                                              cornerFraction: options.cornerFraction)
            clipped.stroke(Path(rect), with: .color(Color.orange.opacity(0.7)), style: dash)
        }
        let centre = MouseSurfaceZones.rect(for: .center, in: surface, edgeFraction: options.edgeFraction,
                                            cornerFraction: options.cornerFraction)
        clipped.stroke(Path(centre), with: .color(Color.secondary.opacity(0.7)), style: dash)
    }

    private static func drawTrails(_ snapshot: TouchFeed.Snapshot, reference: TimeInterval, surface: CGRect,
                                   lifetime: TimeInterval, in context: inout GraphicsContext) {
        guard lifetime > 0 else { return }
        for (id, trail) in snapshot.trails where trail.count > 1 {
            let colour: Color = color(forContact: id)
            for index in 1..<trail.count {
                let point = trail[index]
                let age: Double = reference - point.timestamp
                let alpha: Double = 1 - age / lifetime
                if alpha <= 0.02 { continue }
                let previous = trail[index - 1]
                var segment = Path()
                segment.move(to: MouseSurfaceShape.point(x: previous.x, y: previous.y, in: surface))
                segment.addLine(to: MouseSurfaceShape.point(x: point.x, y: point.y, in: surface))
                context.stroke(segment, with: .color(colour.opacity(min(alpha, 1) * 0.8)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }

    private static func drawContacts(_ snapshot: TouchFeed.Snapshot, surface: CGRect, in context: inout GraphicsContext) {
        guard let frame = snapshot.latest else { return }
        let baseRadius: CGFloat = surface.width * 0.07
        for contact in frame.contacts where contact.isTouching {
            let centre: CGPoint = MouseSurfaceShape.point(x: contact.x, y: contact.y, in: surface)
            // Radius follows the sensor's contact size (0 = unknown → neutral size).
            let scale: CGFloat = contact.size > 0 ? CGFloat(min(max(0.6 + contact.size * 0.5, 0.6), 2.2)) : 1
            let radius: CGFloat = baseRadius * scale
            let colour: Color = color(forContact: contact.id)
            let dot = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2,
                                             height: radius * 2))
            context.fill(dot, with: .color(colour.opacity(0.55)))
            context.stroke(dot, with: .color(colour), lineWidth: 1.5)

            var label: String = String(format: "#%d  %.2f, %.2f", contact.id, contact.x, contact.y)
            if let start = snapshot.contactStart[contact.id] {
                label += String(format: "  %.1f s", max(0, frame.timestamp - start))
            }
            let text = Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(Color.primary)
            // Keep the label on the surface side that has room.
            let placeLeft: Bool = centre.x > surface.midX
            let anchorPoint = CGPoint(x: centre.x + (placeLeft ? -(radius + 4) : radius + 4), y: centre.y)
            context.draw(text, at: anchorPoint, anchor: placeLeft ? .trailing : .leading)
        }
    }

    private static func drawSyntheticBadge(surface: CGRect, in context: inout GraphicsContext) {
        let text = Text("SYNTHETIC INPUT").font(.system(size: 11, weight: .bold)).foregroundColor(Color.white)
        let resolved = context.resolve(text)
        let textSize: CGSize = resolved.measure(in: CGSize(width: 400, height: 40))
        let rect = CGRect(x: surface.midX - textSize.width / 2 - 8, y: surface.minY + 10,
                          width: textSize.width + 16, height: textSize.height + 6)
        context.fill(Path(roundedRect: rect, cornerRadius: 5, style: .continuous), with: .color(Color.orange))
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}

/// The Canvas that polls the touch feed. `date` comes from the enclosing TimelineView so a new
/// frame is drawn on every tick without any SwiftUI state changing.
struct TouchSurfaceCanvas: View {
    let feed: TouchFeed
    let date: Date
    let options: TouchSurfaceRenderer.Options

    var body: some View {
        let feed: TouchFeed = self.feed
        let options: TouchSurfaceRenderer.Options = self.options
        Canvas { context, size in
            let snapshot: TouchFeed.Snapshot = feed.snapshot()
            TouchSurfaceRenderer.draw(snapshot, now: ProcessInfo.processInfo.systemUptime, options: options,
                                      in: &context, size: size)
        }
        .accessibilityLabel(Text("Mouse touch surface"))
    }
}
