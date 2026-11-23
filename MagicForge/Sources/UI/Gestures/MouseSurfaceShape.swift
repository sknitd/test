import SwiftUI
import MFCore

/// Stylized top view of a Magic Mouse: the touch-sensitive area (52 × 90 mm) with the
/// mouse's strongly rounded outline. The shape is fitted, centred, into the given rectangle.
public struct MouseSurfaceShape: Shape {
    /// Width ÷ height of the touch surface.
    public static let aspectRatio: CGFloat = 52.0 / 90.0

    public init() {}

    /// Largest rectangle with the surface's aspect ratio that fits, centred, in `rect`.
    /// Normalized touch coordinates map linearly onto this rectangle.
    public static func surfaceRect(in rect: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        var width: CGFloat = rect.width
        var height: CGFloat = width / aspectRatio
        if height > rect.height {
            height = rect.height
            width = height * aspectRatio
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// Converts a normalized touch position (x 0 = left, y 0 = rear edge … 1 = front edge) to
    /// view coordinates inside `surface`. The front edge is drawn at the top.
    public static func point(x: Double, y: Double, in surface: CGRect) -> CGPoint {
        CGPoint(x: surface.minX + CGFloat(x) * surface.width, y: surface.maxY - CGFloat(y) * surface.height)
    }

    /// The outline for an already fitted surface rectangle.
    public static func outline(for surface: CGRect) -> Path {
        Path(roundedRect: surface, cornerRadius: surface.width * 0.44, style: .continuous)
    }

    public func path(in rect: CGRect) -> Path {
        MouseSurfaceShape.outline(for: MouseSurfaceShape.surfaceRect(in: rect))
    }
}

/// Rectangles of the recognizer's edge / corner / centre zones in view coordinates.
enum MouseSurfaceZones {
    static func rect(for zone: GestureChoreography.Zone, in surface: CGRect, edgeFraction: Double,
                     cornerFraction: Double) -> CGRect {
        let edgeWidth: CGFloat = surface.width * CGFloat(edgeFraction)
        let edgeHeight: CGFloat = surface.height * CGFloat(edgeFraction)
        let cornerWidth: CGFloat = surface.width * CGFloat(cornerFraction)
        let cornerHeight: CGFloat = surface.height * CGFloat(cornerFraction)
        switch zone {
        case .leftEdge:
            return CGRect(x: surface.minX, y: surface.minY, width: edgeWidth, height: surface.height)
        case .rightEdge:
            return CGRect(x: surface.maxX - edgeWidth, y: surface.minY, width: edgeWidth, height: surface.height)
        case .topEdge:
            return CGRect(x: surface.minX, y: surface.minY, width: surface.width, height: edgeHeight)
        case .bottomEdge:
            return CGRect(x: surface.minX, y: surface.maxY - edgeHeight, width: surface.width, height: edgeHeight)
        case .cornerTopLeft:
            return CGRect(x: surface.minX, y: surface.minY, width: cornerWidth, height: cornerHeight)
        case .cornerTopRight:
            return CGRect(x: surface.maxX - cornerWidth, y: surface.minY, width: cornerWidth, height: cornerHeight)
        case .cornerBottomLeft:
            return CGRect(x: surface.minX, y: surface.maxY - cornerHeight, width: cornerWidth, height: cornerHeight)
        case .cornerBottomRight:
            return CGRect(x: surface.maxX - cornerWidth, y: surface.maxY - cornerHeight, width: cornerWidth,
                          height: cornerHeight)
        case .center:
            return CGRect(x: surface.minX + surface.width / 3, y: surface.minY + surface.height / 3,
                          width: surface.width / 3, height: surface.height / 3)
        }
    }
}
