import SwiftUI
import AppKit
import MFCore

/// Colours of a radial menu derived from its theme.
@MainActor
enum RadialThemeColor {
    /// The theme accent, or the system accent colour when the hex string is empty or invalid.
    static func accent(for theme: RadialMenuTheme) -> Color {
        let trimmed: String = theme.accentHex.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return Color.accentColor }
        return Color(hex: trimmed) ?? Color.accentColor
    }

    /// "#RRGGBB" for a colour, converted to sRGB. Nil when the colour cannot be converted.
    static func hex(from color: Color) -> String? {
        guard let converted = NSColor(color).usingColorSpace(NSColorSpace.sRGB) else { return nil }
        let red: Int = Int((converted.redComponent * 255).rounded())
        let green: Int = Int((converted.greenComponent * 255).rounded())
        let blue: Int = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", min(max(red, 0), 255), min(max(green, 0), 255), min(max(blue, 0), 255))
    }
}

/// One wedge of the ring.
struct RadialWedgeShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    /// Gap between neighbouring wedges, in points along the arc.
    var gap: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // A full circle (single item) keeps no gap; otherwise shave half the gap off both sides.
        let isFullCircle: Bool = endAngle - startAngle >= 2 * Double.pi - 0.0001
        let outerInset: Double = isFullCircle ? 0 : Double(gap / 2 / max(outerRadius, 1))
        let innerInset: Double = isFullCircle ? 0 : Double(gap / 2 / max(innerRadius, 1))
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: Angle(radians: startAngle + outerInset),
                    endAngle: Angle(radians: endAngle - outerInset), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: Angle(radians: endAngle - innerInset),
                    endAngle: Angle(radians: startAngle + innerInset), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Pure rendering of one ring of items around a centre button. Used by the floating menu and by
/// the (non-interactive) preview in the configuration screen. Sized to `layout.diameter`.
struct RadialRingView: View {
    let items: [RadialMenuItem]
    let highlightedIndex: Int?
    let layout: RadialOverlayLayout
    let accent: Color
    let showLabels: Bool
    let centerSymbolName: String
    let centerLabel: String

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
            ForEach(items.indices, id: \.self) { index in
                wedge(index)
            }
            ForEach(items.indices, id: \.self) { index in
                RadialItemContent(item: items[index], number: index + 1, isHighlighted: index == highlightedIndex,
                                  showLabel: showLabels, maxWidth: labelWidth)
                    .position(itemPosition(index))
            }
            centerButton
        }
        .frame(width: layout.diameter, height: layout.diameter)
    }

    private var labelWidth: CGFloat {
        let count: Int = max(items.count, 1)
        let arc: CGFloat = 2 * CGFloat.pi * layout.itemRadius / CGFloat(count)
        return min(max(arc - 10, 34), layout.outerRadius - layout.innerRadius + 26)
    }

    private func wedge(_ index: Int) -> some View {
        let angles: (start: Double, end: Double) = RadialOverlayLayout.wedgeAngles(of: index, count: items.count)
        let isHighlighted: Bool = index == highlightedIndex
        return RadialWedgeShape(startAngle: angles.start, endAngle: angles.end,
                                innerRadius: layout.innerRadius + 3, outerRadius: layout.outerRadius - 2)
            .fill(isHighlighted ? accent.opacity(0.85) : Color.secondary.opacity(0.14))
    }

    /// Position inside the ring's own square (centre = diameter / 2).
    private func itemPosition(_ index: Int) -> CGPoint {
        let angle: Double = RadialOverlayLayout.midAngle(of: index, count: items.count)
        let half: CGFloat = layout.diameter / 2
        return CGPoint(x: half + layout.itemRadius * CGFloat(cos(angle)),
                       y: half + layout.itemRadius * CGFloat(sin(angle)))
    }

    private var centerButton: some View {
        VStack(spacing: 2) {
            Image(systemName: centerSymbolName)
                .font(.system(size: max(layout.innerRadius * 0.5, 12), weight: .medium))
            if showLabels && !centerLabel.isEmpty {
                Text(centerLabel)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: layout.innerRadius * 2 - 8, height: layout.innerRadius * 2 - 8)
        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

/// Icon (+ label) of one item inside its wedge.
struct RadialItemContent: View {
    let item: RadialMenuItem
    let number: Int
    let isHighlighted: Bool
    let showLabel: Bool
    let maxWidth: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 26, height: 24)
                if !item.children.isEmpty {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 9))
                        .offset(x: 7, y: -3)
                }
            }
            if showLabel {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxWidth)
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(number). \(item.title)"))
    }
}
