import Foundation

/// A one-click look for a widget: container style plus a light/dark appearance. Themes change only how a
/// widget is drawn; they never touch its layout, data or permissions.
struct WidgetTheme: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var style: WidgetStyle
    var appearance: WidgetAppearance

    static let all: [WidgetTheme] = [
        WidgetTheme(id: "glass", name: "Glass", symbol: "square.on.square.dashed",
                    style: WidgetStyle(background: "material", cornerRadius: 20, padding: 14, shadowRadius: 10, tint: "accent"), appearance: .system),
        WidgetTheme(id: "midnight", name: "Midnight", symbol: "moon.stars",
                    style: WidgetStyle(background: "#101018F2", cornerRadius: 18, padding: 14, borderColor: "#FFFFFF1F", borderWidth: 1, shadowRadius: 12, tint: "cyan"), appearance: .dark),
        WidgetTheme(id: "paper", name: "Paper", symbol: "doc.plaintext",
                    style: WidgetStyle(background: "#FBF8F1", cornerRadius: 10, padding: 14, borderColor: "#00000026", borderWidth: 1, shadowRadius: 4, tint: "orange"), appearance: .light),
        WidgetTheme(id: "neon", name: "Neon", symbol: "bolt.horizontal",
                    style: WidgetStyle(background: "#0B0B12EB", cornerRadius: 14, padding: 14, borderColor: "#39FF14", borderWidth: 1.5, shadowRadius: 14, tint: "#39FF14"), appearance: .dark),
        WidgetTheme(id: "graphite", name: "Graphite", symbol: "circle.lefthalf.filled",
                    style: WidgetStyle(background: "#2C2C2EF0", cornerRadius: 16, padding: 14, shadowRadius: 8, tint: "gray"), appearance: .dark),
        WidgetTheme(id: "minimal", name: "Minimal", symbol: "rectangle.dashed",
                    style: WidgetStyle(background: "clear", cornerRadius: 0, padding: 6, shadowRadius: 0, tint: "accent"), appearance: .system),
    ]

    static func named(_ id: String) -> WidgetTheme? { all.first { $0.id == id || $0.name.caseInsensitiveCompare(id) == .orderedSame } }

    func apply(to widget: inout WidgetInstance) {
        widget.definition.style = style
        widget.appearance = appearance
    }

    /// The theme a widget currently wears, if its style matches one exactly.
    static func matching(_ widget: WidgetInstance) -> WidgetTheme? {
        all.first { $0.style == widget.definition.style && $0.appearance == widget.appearance }
    }
}

/// How "Tidy Up" packs widgets on a display.
enum TileMode: String, CaseIterable, Sendable {
    case left, right, top, bottom

    var title: String {
        switch self {
        case .left: return "Stack on Left Edge"
        case .right: return "Stack on Right Edge"
        case .top: return "Flow Along Top"
        case .bottom: return "Flow Along Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        case .top: return "rectangle.topthird.inset.filled"
        case .bottom: return "rectangle.bottomthird.inset.filled"
        }
    }
}

extension LayoutEngine {
    /// Pack rectangles of the given sizes into `bounds` without overlap, keeping their order.
    /// `.left`/`.right` fill columns top to bottom; `.top`/`.bottom` fill rows left to right. When a column or
    /// row is full a new one starts beside it. Items that cannot fit at all are clamped into the bounds.
    static func tile(_ sizes: [WidgetSize], in bounds: Rect, mode: TileMode, gap: Double = 16, margin: Double = 24) -> [Rect] {
        let area = Rect(x: bounds.x + margin, y: bounds.y + margin, width: max(0, bounds.width - margin * 2), height: max(0, bounds.height - margin * 2))
        var result: [Rect] = []
        let vertical = mode == .left || mode == .right
        var along = 0.0       // position along the fill direction within the current line
        var across = 0.0      // offset of the current line from its edge
        var thickness = 0.0   // thickness of the current line
        for size in sizes {
            let length = vertical ? size.height : size.width
            let breadth = vertical ? size.width : size.height
            let limit = vertical ? area.height : area.width
            if along > 0, along + length > limit {
                across += thickness + gap
                along = 0
                thickness = 0
            }
            var rect: Rect
            switch mode {
            case .left: rect = Rect(x: area.minX + across, y: area.minY + along, width: size.width, height: size.height)
            case .right: rect = Rect(x: area.maxX - across - size.width, y: area.minY + along, width: size.width, height: size.height)
            case .top: rect = Rect(x: area.minX + along, y: area.minY + across, width: size.width, height: size.height)
            case .bottom: rect = Rect(x: area.minX + along, y: area.maxY - across - size.height, width: size.width, height: size.height)
            }
            rect = clamp(rect, to: bounds)
            result.append(rect)
            along += length + gap
            thickness = max(thickness, breadth)
        }
        return result
    }
}

extension WidgetStore {
    /// Tidy the visible, unlocked widgets on each display into non-overlapping rows or columns.
    func tidy(_ mode: TileMode, displays: [DisplayInfo]) {
        guard !displays.isEmpty else { return }
        for display in displays {
            let members = widgets.filter { !$0.hidden && !$0.locked && LayoutEngine.resolveDisplay(for: $0.placement, in: displays)?.id == display.id }
            let rects = LayoutEngine.tile(members.map { WidgetSize($0.placement.width, $0.placement.height) }, in: display.frame, mode: mode)
            for (widget, rect) in zip(members, rects) {
                update(widget.id) {
                    $0.placement.x = rect.x - display.frame.x
                    $0.placement.y = rect.y - display.frame.y
                    $0.placement.displayID = display.id
                }
            }
        }
    }

    func applyTheme(_ theme: WidgetTheme, to ids: [String]) {
        for id in ids { update(id) { theme.apply(to: &$0) } }
    }

    /// Replace everything with the contents of a backup.
    func replaceAll(widgets newWidgets: [WidgetInstance], layouts newLayouts: [SavedLayout]) {
        try? db.deleteAll(Collections.widgets)
        try? db.deleteAll(Collections.trash)
        try? db.deleteAll(Collections.layouts)
        for widget in newWidgets { try? db.save(widget, in: Collections.widgets, id: widget.id) }
        for layout in newLayouts { try? db.save(layout, in: Collections.layouts, id: layout.id) }
        load()
        onChange?([])
    }
}
