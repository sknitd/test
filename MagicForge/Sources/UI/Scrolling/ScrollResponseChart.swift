import SwiftUI
import MFCore

/// Output vs. input scroll delta for the speed multipliers and inversion only. Acceleration
/// and smoothing depend on scroll speed and history, so they are described in words next to
/// the chart instead of being drawn with made-up numbers.
struct ScrollResponseChart: View {
    let settings: ScrollSettings

    /// Signed gain of an axis: multiplier, negative when inverted.
    static func gain(multiplier: Double, inverted: Bool) -> Double {
        let value: Double = multiplier.isFinite ? max(multiplier, 0) : 1
        return inverted ? -value : value
    }

    var body: some View {
        let vertical: Double = Self.gain(multiplier: settings.verticalMultiplier, inverted: settings.invertVertical)
        let horizontal: Double = Self.gain(multiplier: settings.horizontalMultiplier, inverted: settings.invertHorizontal)
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                ScrollResponseChart.draw(vertical: vertical, horizontal: horizontal, in: &context, size: size)
            }
            .frame(height: 180)
            .accessibilityLabel(Text(String(format: "Response chart. Vertical gain %.2f, horizontal gain %.2f.",
                                            vertical, horizontal)))
            HStack(spacing: 14) {
                legend("Vertical", color: Color.accentColor, gain: vertical)
                legend("Horizontal", color: Color.orange, gain: horizontal)
                legend("Unmodified", color: Color.secondary, gain: 1)
            }
            .font(.caption)
        }
    }

    private func legend(_ title: String, color: Color, gain: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 3)
            Text(String(format: "%@ ×%.2f", title, gain))
                .foregroundStyle(.secondary)
        }
    }

    private static func draw(vertical: Double, horizontal: Double, in context: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
        guard plot.width > 20, plot.height > 20 else { return }
        // Input runs −1…1 across the width. The output axis grows with the largest gain.
        let outputRange: Double = max(1, abs(vertical), abs(horizontal))
        func point(input: Double, gain: Double) -> CGPoint {
            let output: Double = input * gain
            return CGPoint(x: plot.midX + CGFloat(input) * plot.width / 2,
                           y: plot.midY - CGFloat(output / outputRange) * plot.height / 2)
        }
        var axes = Path()
        axes.move(to: CGPoint(x: plot.minX, y: plot.midY))
        axes.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
        axes.move(to: CGPoint(x: plot.midX, y: plot.minY))
        axes.addLine(to: CGPoint(x: plot.midX, y: plot.maxY))
        context.stroke(axes, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)

        func line(gain: Double) -> Path {
            var path = Path()
            path.move(to: point(input: -1, gain: gain))
            path.addLine(to: point(input: 1, gain: gain))
            return path
        }
        context.stroke(line(gain: 1), with: .color(Color.secondary.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        context.stroke(line(gain: horizontal), with: .color(Color.orange), lineWidth: 2)
        context.stroke(line(gain: vertical), with: .color(Color.accentColor), lineWidth: 2)

        let caption = Font.system(size: 10)
        context.draw(Text("input delta").font(caption).foregroundColor(Color.secondary),
                     at: CGPoint(x: plot.maxX, y: plot.midY + 3), anchor: .topTrailing)
        context.draw(Text("output delta").font(caption).foregroundColor(Color.secondary),
                     at: CGPoint(x: plot.midX + 4, y: plot.minY), anchor: .topLeading)
    }
}
