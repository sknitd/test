import CoreGraphics
import Foundation

/// A display in *global top-left coordinates*: origin at the top-left corner of the primary
/// display, x to the right, y downwards. This is the coordinate space of the Accessibility API
/// (`kAXPositionAttribute`) and of Quartz events.
struct DisplayArea: Equatable, Sendable {
    /// The whole display.
    var frame: CGRect
    /// The display minus menu bar and Dock.
    var visibleFrame: CGRect
}

/// Where a window should go.
enum WindowPlacement: Equatable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize
    case center
    /// Grow (positive) or shrink (negative) by this fraction of the display, keeping the centre.
    case resize(byFraction: Double)
    case nextDisplay
}

/// Pure window-frame arithmetic. No AppKit, no side effects.
enum WindowGeometry {
    /// Windows are never made smaller than this (or the visible frame, if that is smaller).
    static let minimumSize = CGSize(width: 320, height: 200)

    /// Converts an AppKit screen rectangle (origin at the bottom-left corner of the primary
    /// display, y upwards) to global top-left coordinates.
    ///
    /// AppKit: a rect's `minY` is the distance of its *bottom* edge above the primary display's
    /// bottom edge. Top-left space: `minY` is the distance of its *top* edge below the primary
    /// display's top edge. Hence `y' = primaryHeight - (y + height)`. This holds for every
    /// display in the arrangement, because both spaces share the primary display as reference;
    /// displays above the primary get negative y', displays left of it keep their negative x.
    static func topLeftRect(fromAppKit rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the display showing most of the window; when the window is entirely off-screen,
    /// the display whose centre is nearest to the window's centre.
    static func displayIndex(containing window: CGRect, in displays: [DisplayArea]) -> Int? {
        guard !displays.isEmpty else { return nil }
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, display) in displays.enumerated() {
            let overlap = display.frame.intersection(window)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if let bestIndex { return bestIndex }

        var nearestIndex = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (index, display) in displays.enumerated() {
            let dx = display.frame.midX - window.midX
            let dy = display.frame.midY - window.midY
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    /// Target frame for a placement, or nil when it cannot apply (no displays, or `.nextDisplay`
    /// with a single display).
    static func frame(for placement: WindowPlacement, window: CGRect, displays: [DisplayArea]) -> CGRect? {
        guard let index = displayIndex(containing: window, in: displays) else { return nil }
        let visible = displays[index].visibleFrame
        guard visible.width > 0, visible.height > 0 else { return nil }

        switch placement {
        case .leftHalf:
            let width = (visible.width / 2).rounded(.down)
            return rounded(CGRect(x: visible.minX, y: visible.minY, width: width, height: visible.height))
        case .rightHalf:
            let leftWidth = (visible.width / 2).rounded(.down)
            return rounded(CGRect(x: visible.minX + leftWidth, y: visible.minY,
                                  width: visible.width - leftWidth, height: visible.height))
        case .topHalf:
            let height = (visible.height / 2).rounded(.down)
            return rounded(CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: height))
        case .bottomHalf:
            let topHeight = (visible.height / 2).rounded(.down)
            return rounded(CGRect(x: visible.minX, y: visible.minY + topHeight,
                                  width: visible.width, height: visible.height - topHeight))
        case .maximize:
            return rounded(visible)
        case .center:
            let size = clampedSize(window.size, in: visible)
            return rounded(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                  width: size.width, height: size.height))
        case .resize(let fraction):
            guard fraction.isFinite else { return nil }
            let proposed = CGSize(width: window.width + visible.width * CGFloat(fraction),
                                  height: window.height + visible.height * CGFloat(fraction))
            let size = clampedSize(proposed, in: visible)
            let resized = CGRect(x: window.midX - size.width / 2, y: window.midY - size.height / 2,
                                 width: size.width, height: size.height)
            return rounded(moved(resized, inside: visible))
        case .nextDisplay:
            guard displays.count > 1 else { return nil }
            let target = displays[(index + 1) % displays.count].visibleFrame
            guard target.width > 0, target.height > 0 else { return nil }
            // Keep the window's frame relative to the visible area (same fractions of width and height).
            let relativeX = (window.minX - visible.minX) / visible.width
            let relativeY = (window.minY - visible.minY) / visible.height
            let size = clampedSize(CGSize(width: window.width / visible.width * target.width,
                                          height: window.height / visible.height * target.height), in: target)
            let placed = CGRect(x: target.minX + relativeX * target.width, y: target.minY + relativeY * target.height,
                                width: size.width, height: size.height)
            return rounded(moved(placed, inside: target))
        }
    }

    /// True when two frames are equal within `tolerance` points on every edge.
    static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    // MARK: Helpers

    /// Clamps a size between the minimum size and the bounds (the bounds win when they are smaller).
    static func clampedSize(_ size: CGSize, in bounds: CGRect) -> CGSize {
        let minimumWidth = min(minimumSize.width, bounds.width)
        let minimumHeight = min(minimumSize.height, bounds.height)
        return CGSize(width: min(max(size.width, minimumWidth), bounds.width),
                      height: min(max(size.height, minimumHeight), bounds.height))
    }

    /// Translates a rect (no larger than `bounds`) so that it lies entirely inside `bounds`.
    static func moved(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        var origin = rect.origin
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - rect.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: origin, size: rect.size)
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }
}
