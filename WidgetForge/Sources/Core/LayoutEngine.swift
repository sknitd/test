import Foundation

/// A plain rectangle in points with a top-left origin. The overlay engine converts to and from AppKit's
/// bottom-left screen coordinates at the window boundary, so all layout math stays testable.
struct Rect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var maxX: Double { x + width }
    var midX: Double { x + width / 2 }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }

    func offset(dx: Double, dy: Double) -> Rect { Rect(x: x + dx, y: y + dy, width: width, height: height) }
    func intersects(_ o: Rect) -> Bool { minX < o.maxX && maxX > o.minX && minY < o.maxY && maxY > o.minY }
    func contains(x px: Double, y py: Double) -> Bool { px >= minX && px <= maxX && py >= minY && py <= maxY }

    static func union(_ rects: [Rect]) -> Rect? {
        guard let first = rects.first else { return nil }
        var minX = first.minX, minY = first.minY, maxX = first.maxX, maxY = first.maxY
        for r in rects.dropFirst() {
            minX = min(minX, r.minX); minY = min(minY, r.minY); maxX = max(maxX, r.maxX); maxY = max(maxY, r.maxY)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A connected display, described without AppKit types.
struct DisplayInfo: Codable, Hashable, Sendable {
    var id: String          // stable UUID of the display (survives reboots and re-plugging)
    var name: String
    var frame: Rect         // visible frame in global top-left coordinates
    var scale: Double
    var isMain: Bool
}

enum AlignMode: String, CaseIterable, Sendable {
    case left, right, top, bottom, centerHorizontally, centerVertically, distributeHorizontally, distributeVertically

    var title: String {
        switch self {
        case .left: return "Align Left"
        case .right: return "Align Right"
        case .top: return "Align Top"
        case .bottom: return "Align Bottom"
        case .centerHorizontally: return "Align Horizontal Centers"
        case .centerVertically: return "Align Vertical Centers"
        case .distributeHorizontally: return "Distribute Horizontally"
        case .distributeVertically: return "Distribute Vertically"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .bottom: return "align.vertical.bottom"
        case .centerHorizontally: return "align.horizontal.center"
        case .centerVertically: return "align.vertical.center"
        case .distributeHorizontally: return "distribute.horizontal.center"
        case .distributeVertically: return "distribute.vertical.center"
        }
    }
}

struct AlignmentGuide: Hashable, Sendable {
    enum Axis: Sendable { case vertical, horizontal }
    var axis: Axis
    var position: Double   // x for vertical guides, y for horizontal guides
}

enum ResizeHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
}

enum LayoutEngine {
    static func snap(_ value: Double, grid: Double) -> Double {
        grid > 0 ? (value / grid).rounded() * grid : value
    }

    static func snap(_ rect: Rect, grid: Double, snapSize: Bool = false) -> Rect {
        guard grid > 0 else { return rect }
        return Rect(x: snap(rect.x, grid: grid), y: snap(rect.y, grid: grid),
                    width: snapSize ? max(grid, snap(rect.width, grid: grid)) : rect.width,
                    height: snapSize ? max(grid, snap(rect.height, grid: grid)) : rect.height)
    }

    /// Keep a rectangle fully inside bounds where possible (it is shrunk only if larger than the bounds).
    static func clamp(_ rect: Rect, to bounds: Rect) -> Rect {
        var r = rect
        r.width = min(r.width, bounds.width)
        r.height = min(r.height, bounds.height)
        r.x = min(max(r.x, bounds.minX), bounds.maxX - r.width)
        r.y = min(max(r.y, bounds.minY), bounds.maxY - r.height)
        return r
    }

    static func align(_ rects: [Rect], mode: AlignMode) -> [Rect] {
        guard rects.count > 1, let box = Rect.union(rects) else { return rects }
        switch mode {
        case .left: return rects.map { Rect(x: box.minX, y: $0.y, width: $0.width, height: $0.height) }
        case .right: return rects.map { Rect(x: box.maxX - $0.width, y: $0.y, width: $0.width, height: $0.height) }
        case .top: return rects.map { Rect(x: $0.x, y: box.minY, width: $0.width, height: $0.height) }
        case .bottom: return rects.map { Rect(x: $0.x, y: box.maxY - $0.height, width: $0.width, height: $0.height) }
        case .centerHorizontally: return rects.map { Rect(x: box.midX - $0.width / 2, y: $0.y, width: $0.width, height: $0.height) }
        case .centerVertically: return rects.map { Rect(x: $0.x, y: box.midY - $0.height / 2, width: $0.width, height: $0.height) }
        case .distributeHorizontally, .distributeVertically:
            guard rects.count > 2 else { return rects }
            let horizontal = mode == .distributeHorizontally
            let order = rects.indices.sorted { horizontal ? rects[$0].minX < rects[$1].minX : rects[$0].minY < rects[$1].minY }
            let total = rects.reduce(0) { $0 + (horizontal ? $1.width : $1.height) }
            let span = horizontal ? box.width : box.height
            let gap = (span - total) / Double(rects.count - 1)
            var cursor = horizontal ? box.minX : box.minY
            var result = rects
            for i in order {
                if horizontal { result[i].x = cursor; cursor += rects[i].width + gap }
                else { result[i].y = cursor; cursor += rects[i].height + gap }
            }
            return result
        }
    }

    /// Snap a moving rectangle to the edges and centers of its neighbours and of the container.
    /// Returns the adjusted rectangle plus the guides that should be drawn.
    static func guides(moving: Rect, others: [Rect], container: Rect? = nil, threshold: Double = 6) -> (rect: Rect, guides: [AlignmentGuide]) {
        var xTargets: [Double] = []
        var yTargets: [Double] = []
        for o in others {
            xTargets += [o.minX, o.midX, o.maxX]
            yTargets += [o.minY, o.midY, o.maxY]
        }
        if let c = container {
            xTargets += [c.minX, c.midX, c.maxX]
            yTargets += [c.minY, c.midY, c.maxY]
        }
        var result = moving
        var guides: [AlignmentGuide] = []

        func best(_ anchors: [Double], _ targets: [Double]) -> (delta: Double, target: Double)? {
            var found: (delta: Double, target: Double)?
            for a in anchors {
                for t in targets where abs(t - a) <= threshold {
                    if found == nil || abs(t - a) < abs(found!.delta) { found = (t - a, t) }
                }
            }
            return found
        }
        if let hit = best([moving.minX, moving.midX, moving.maxX], xTargets) {
            result.x += hit.delta
            guides.append(AlignmentGuide(axis: .vertical, position: hit.target))
        }
        if let hit = best([moving.minY, moving.midY, moving.maxY], yTargets) {
            result.y += hit.delta
            guides.append(AlignmentGuide(axis: .horizontal, position: hit.target))
        }
        return (result, guides)
    }

    /// Apply a drag of a resize handle, honouring a minimum size.
    static func resize(_ rect: Rect, handle: ResizeHandle, dx: Double, dy: Double, minWidth: Double = 40, minHeight: Double = 24) -> Rect {
        var r = rect
        if handle.movesLeft {
            let d = min(dx, rect.width - minWidth)
            r.x += d; r.width -= d
        }
        if handle.movesRight { r.width = max(minWidth, rect.width + dx) }
        if handle.movesTop {
            let d = min(dy, rect.height - minHeight)
            r.y += d; r.height -= d
        }
        if handle.movesBottom { r.height = max(minHeight, rect.height + dy) }
        return r
    }

    /// Snap a resize to the grid by moving only the edges the handle controls; the opposite edges stay exactly
    /// where they were, even if they were not on the grid to begin with.
    static func snapResize(_ rect: Rect, from original: Rect, handle: ResizeHandle, grid: Double, minWidth: Double = 8, minHeight: Double = 8) -> Rect {
        guard grid > 0 else { return rect }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = min(snap(minX, grid: grid), original.maxX - minWidth) } else { minX = original.minX }
        if handle.movesRight { maxX = max(snap(maxX, grid: grid), original.minX + minWidth) } else if !handle.movesLeft { maxX = original.maxX } else { maxX = original.maxX }
        if handle.movesTop { minY = min(snap(minY, grid: grid), original.maxY - minHeight) } else { minY = original.minY }
        if handle.movesBottom { maxY = max(snap(maxY, grid: grid), original.minY + minHeight) } else { maxY = original.maxY }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Reposition a canvas child when its parent goes from `oldSize` to `newSize`.
    static func applyConstraints(_ frame: Rect, _ c: NodeConstraints, oldSize: WidgetSize, newSize: WidgetSize) -> Rect {
        var r = frame
        let dw = newSize.width - oldSize.width
        let dh = newSize.height - oldSize.height
        if c.pinLeft && c.pinRight { r.width = max(8, frame.width + dw) }
        else if c.pinRight { r.x = frame.x + dw }
        else if !c.pinLeft, oldSize.width > 0 { r.x = frame.midX / oldSize.width * newSize.width - frame.width / 2 }
        if c.pinTop && c.pinBottom { r.height = max(8, frame.height + dh) }
        else if c.pinBottom { r.y = frame.y + dh }
        else if !c.pinTop, oldSize.height > 0 { r.y = frame.midY / oldSize.height * newSize.height - frame.height / 2 }
        return r
    }

    // MARK: Displays

    /// Choose the display a placement belongs on. Falls back to the main display when the saved display is
    /// disconnected; the saved id is left untouched so the widget returns when the display comes back.
    static func resolveDisplay(for placement: Placement, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let id = placement.displayID, let match = displays.first(where: { $0.id == id }) { return match }
        return displays.first(where: \.isMain) ?? displays.first
    }

    /// Global rectangle for a placement (stored relative to its display's visible frame).
    static func globalRect(for placement: Placement, in displays: [DisplayInfo]) -> Rect? {
        guard let display = resolveDisplay(for: placement, in: displays) else { return nil }
        let local = Rect(x: display.frame.x + placement.x, y: display.frame.y + placement.y,
                         width: placement.width, height: placement.height)
        return clamp(local, to: display.frame)
    }

    /// Convert a global rectangle back to a placement, attaching it to the display containing its center.
    static func placement(forGlobal rect: Rect, in displays: [DisplayInfo]) -> Placement {
        let display = displays.first(where: { $0.frame.contains(x: rect.midX, y: rect.midY) })
            ?? displays.first(where: \.isMain) ?? displays.first
        guard let display else { return Placement(x: rect.x, y: rect.y, width: rect.width, height: rect.height, displayID: nil) }
        return Placement(x: rect.x - display.frame.x, y: rect.y - display.frame.y,
                         width: rect.width, height: rect.height, displayID: display.id)
    }

    /// First free slot for a new widget, scanning left-to-right, top-to-bottom on a coarse grid.
    static func freeSlot(size: WidgetSize, occupied: [Rect], in bounds: Rect, margin: Double = 24) -> Rect {
        var y = bounds.minY + margin
        while y + size.height <= bounds.maxY - margin {
            var x = bounds.minX + margin
            while x + size.width <= bounds.maxX - margin {
                let candidate = Rect(x: x, y: y, width: size.width, height: size.height)
                if !occupied.contains(where: { $0.intersects(candidate) }) { return candidate }
                x += 40
            }
            y += 40
        }
        return clamp(Rect(x: bounds.minX + margin, y: bounds.minY + margin, width: size.width, height: size.height), to: bounds)
    }
}
