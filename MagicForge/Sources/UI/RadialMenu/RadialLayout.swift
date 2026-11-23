import Foundation
import MFCore

/// Geometry of the floating radial menu. Shared by the renderer and the hit testing so they can
/// never disagree. All points use a top-left origin (y grows downwards). No UI types in this file.
struct RadialOverlayLayout: Equatable {
    enum Hit: Equatable {
        case center
        case item(Int)
        case recent(Int)
        case searchResult(Int)
        case outside
    }

    static let padding: CGFloat = 24
    static let minimumDiameter: CGFloat = 200
    static let maximumDiameter: CGFloat = 480
    static let recentChipSize: CGFloat = 38
    static let recentSpacing: CGFloat = 8
    static let recentGap: CGFloat = 14
    static let maximumRecents = 5
    static let searchWidth: CGFloat = 300
    static let searchHeaderHeight: CGFloat = 36
    static let searchRowHeight: CGFloat = 30
    static let maximumSearchResults = 6

    var diameter: CGFloat
    var recentCount: Int

    init(diameter: Double, recentCount: Int) {
        let clamped: Double = min(max(diameter, Double(Self.minimumDiameter)), Double(Self.maximumDiameter))
        self.diameter = CGFloat(clamped)
        self.recentCount = min(max(recentCount, 0), Self.maximumRecents)
    }

    var outerRadius: CGFloat { diameter / 2 }
    var innerRadius: CGFloat { diameter * 0.19 }
    /// Radius at which item icons are centred.
    var itemRadius: CGFloat { (outerRadius + innerRadius) / 2 }

    var panelSize: CGSize {
        let width: CGFloat = max(diameter, Self.searchWidth) + Self.padding * 2
        var height: CGFloat = diameter + Self.padding * 2
        if recentCount > 0 { height += Self.recentChipSize + Self.recentGap }
        return CGSize(width: width, height: height)
    }

    var ringCenter: CGPoint {
        CGPoint(x: panelSize.width / 2, y: Self.padding + diameter / 2)
    }

    // MARK: Ring

    /// Angle (radians, clockwise from the positive x axis because y grows downwards) of the
    /// middle of wedge `index`. Wedge 0 is centred at the top.
    static func midAngle(of index: Int, count: Int) -> Double {
        guard count > 0 else { return -Double.pi / 2 }
        let step: Double = 2 * Double.pi / Double(count)
        return -Double.pi / 2 + Double(index) * step
    }

    static func wedgeAngles(of index: Int, count: Int) -> (start: Double, end: Double) {
        guard count > 0 else { return (0, 2 * Double.pi) }
        let step: Double = 2 * Double.pi / Double(count)
        let mid: Double = midAngle(of: index, count: count)
        return (mid - step / 2, mid + step / 2)
    }

    /// Index of the wedge that contains the direction (dx, dy) from the centre.
    static func wedgeIndex(dx: Double, dy: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let step: Double = 2 * Double.pi / Double(count)
        var relative: Double = atan2(dy, dx) + Double.pi / 2 + step / 2
        let full: Double = 2 * Double.pi
        relative = relative.truncatingRemainder(dividingBy: full)
        if relative < 0 { relative += full }
        let index: Int = Int(relative / step)
        return min(max(index, 0), count - 1)
    }

    func itemCenter(_ index: Int, count: Int) -> CGPoint {
        let angle: Double = Self.midAngle(of: index, count: count)
        return CGPoint(x: ringCenter.x + itemRadius * CGFloat(cos(angle)),
                       y: ringCenter.y + itemRadius * CGFloat(sin(angle)))
    }

    // MARK: Recent row

    func recentRect(_ index: Int) -> CGRect {
        let count: CGFloat = CGFloat(recentCount)
        let total: CGFloat = count * Self.recentChipSize + max(count - 1, 0) * Self.recentSpacing
        let startX: CGFloat = panelSize.width / 2 - total / 2
        let x: CGFloat = startX + CGFloat(index) * (Self.recentChipSize + Self.recentSpacing)
        let y: CGFloat = Self.padding + diameter + Self.recentGap
        return CGRect(x: x, y: y, width: Self.recentChipSize, height: Self.recentChipSize)
    }

    // MARK: Search list

    func searchRect(resultCount: Int) -> CGRect {
        let rows: Int = min(max(resultCount, 1), Self.maximumSearchResults)
        let height: CGFloat = Self.searchHeaderHeight + CGFloat(rows) * Self.searchRowHeight + 8
        return CGRect(x: ringCenter.x - Self.searchWidth / 2, y: ringCenter.y - height / 2,
                      width: Self.searchWidth, height: height)
    }

    func searchRowRect(_ index: Int, resultCount: Int) -> CGRect {
        let box: CGRect = searchRect(resultCount: resultCount)
        return CGRect(x: box.minX + 4, y: box.minY + Self.searchHeaderHeight + CGFloat(index) * Self.searchRowHeight,
                      width: box.width - 8, height: Self.searchRowHeight)
    }

    // MARK: Hit testing

    func hit(at point: CGPoint, itemCount: Int, showsRecents: Bool) -> Hit {
        if showsRecents {
            for index in 0..<recentCount where recentRect(index).contains(point) {
                return .recent(index)
            }
        }
        let dx: Double = Double(point.x - ringCenter.x)
        let dy: Double = Double(point.y - ringCenter.y)
        let distance: Double = (dx * dx + dy * dy).squareRoot()
        if distance <= Double(innerRadius) { return .center }
        if distance > Double(outerRadius) + 4 { return .outside }
        if let index = Self.wedgeIndex(dx: dx, dy: dy, count: itemCount) { return .item(index) }
        return .outside
    }

    func searchHit(at point: CGPoint, resultCount: Int) -> Hit {
        let shown: Int = min(resultCount, Self.maximumSearchResults)
        for index in 0..<shown where searchRowRect(index, resultCount: resultCount).contains(point) {
            return .searchResult(index)
        }
        if searchRect(resultCount: resultCount).contains(point) { return .center }
        return .outside
    }

    // MARK: Screen placement

    /// Origin (AppKit screen coordinates, bottom-left based) for a panel of `panelSize` whose ring
    /// centre should sit on `mouse`, kept completely inside `visibleFrame`.
    func panelOrigin(mouse: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let size: CGSize = panelSize
        var x: CGFloat = mouse.x - ringCenter.x
        var y: CGFloat = mouse.y - (size.height - ringCenter.y)
        x = min(max(x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        y = min(max(y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}

/// Index-path helpers over the item tree of a radial menu. No UI types in this file.
enum RadialItemTree {
    static let maximumItemsPerRing = 12
    /// Root ring = level 1; submenus may go down to level 3.
    static let maximumDepth = 3

    struct FlatItem: Identifiable, Equatable {
        var path: [Int]
        var item: RadialMenuItem
        var id: UUID { item.id }
        var depth: Int { path.count }
    }

    static func items(at path: [Int], in root: [RadialMenuItem]) -> [RadialMenuItem]? {
        var current: [RadialMenuItem] = root
        for index in path {
            guard current.indices.contains(index) else { return nil }
            current = current[index].children
        }
        return current
    }

    static func item(at path: [Int], in root: [RadialMenuItem]) -> RadialMenuItem? {
        guard let last = path.last, let siblings = items(at: Array(path.dropLast()), in: root),
              siblings.indices.contains(last) else { return nil }
        return siblings[last]
    }

    /// Applies `body` to the sibling list addressed by `path` (empty = root ring).
    @discardableResult
    static func mutateItems(at path: [Int], in root: inout [RadialMenuItem],
                            _ body: (inout [RadialMenuItem]) -> Void) -> Bool {
        mutate(&root, path: path[...], body)
    }

    private static func mutate(_ list: inout [RadialMenuItem], path: ArraySlice<Int>,
                               _ body: (inout [RadialMenuItem]) -> Void) -> Bool {
        guard let first = path.first else {
            body(&list)
            return true
        }
        guard list.indices.contains(first) else { return false }
        return mutate(&list[first].children, path: path.dropFirst(), body)
    }

    @discardableResult
    static func updateItem(at path: [Int], in root: inout [RadialMenuItem], _ body: (inout RadialMenuItem) -> Void) -> Bool {
        guard let last = path.last else { return false }
        var updated: Bool = false
        mutateItems(at: Array(path.dropLast()), in: &root) { siblings in
            if siblings.indices.contains(last) {
                body(&siblings[last])
                updated = true
            }
        }
        return updated
    }

    /// Appends to the sibling list at `parentPath` when the ring is not full and the depth limit
    /// allows it. Returns the path of the new item.
    @discardableResult
    static func appendItem(_ item: RadialMenuItem, toChildrenOf parentPath: [Int], in root: inout [RadialMenuItem]) -> [Int]? {
        guard parentPath.count < maximumDepth else { return nil }
        var newIndex: Int?
        mutateItems(at: parentPath, in: &root) { siblings in
            if siblings.count < maximumItemsPerRing {
                siblings.append(item)
                newIndex = siblings.count - 1
            }
        }
        return newIndex.map { parentPath + [$0] }
    }

    @discardableResult
    static func removeItem(at path: [Int], in root: inout [RadialMenuItem]) -> RadialMenuItem? {
        guard let last = path.last else { return nil }
        var removed: RadialMenuItem?
        mutateItems(at: Array(path.dropLast()), in: &root) { siblings in
            if siblings.indices.contains(last) { removed = siblings.remove(at: last) }
        }
        return removed
    }

    /// Moves an item among its siblings. Returns the new path.
    @discardableResult
    static func moveItem(at path: [Int], by offset: Int, in root: inout [RadialMenuItem]) -> [Int]? {
        guard let last = path.last, offset != 0 else { return nil }
        let parent: [Int] = Array(path.dropLast())
        var destination: Int?
        mutateItems(at: parent, in: &root) { siblings in
            let target: Int = last + offset
            guard siblings.indices.contains(last), siblings.indices.contains(target) else { return }
            let item: RadialMenuItem = siblings.remove(at: last)
            siblings.insert(item, at: target)
            destination = target
        }
        return destination.map { parent + [$0] }
    }

    static func canMoveItem(at path: [Int], by offset: Int, in root: [RadialMenuItem]) -> Bool {
        guard let last = path.last, offset != 0, let siblings = items(at: Array(path.dropLast()), in: root) else { return false }
        return siblings.indices.contains(last) && siblings.indices.contains(last + offset)
    }

    /// Depth-first list of every item with its index path.
    static func flatten(_ root: [RadialMenuItem], prefix: [Int] = []) -> [FlatItem] {
        var result: [FlatItem] = []
        for (index, item) in root.enumerated() {
            let path: [Int] = prefix + [index]
            result.append(FlatItem(path: path, item: item))
            if !item.children.isEmpty {
                result.append(contentsOf: flatten(item.children, prefix: path))
            }
        }
        return result
    }

    /// Copies a tree giving every item a fresh identifier (used when duplicating a menu).
    static func withFreshIdentifiers(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        items.map { item in
            RadialMenuItem(id: UUID(), title: item.title, symbolName: item.symbolName, action: item.action,
                           children: withFreshIdentifiers(item.children))
        }
    }

    struct SearchResult: Identifiable, Equatable {
        var item: RadialMenuItem
        /// Titles of the submenus that contain the item, joined with " › ".
        var trail: String
        var id: UUID { item.id }
    }

    /// Case-insensitive title search over every selectable (leaf) item. Prefix matches first.
    static func search(_ query: String, in root: [RadialMenuItem]) -> [SearchResult] {
        let needle: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var prefixMatches: [SearchResult] = []
        var otherMatches: [SearchResult] = []
        collect(root, trail: "", needle: needle, prefixMatches: &prefixMatches, otherMatches: &otherMatches)
        return prefixMatches + otherMatches
    }

    private static func collect(_ items: [RadialMenuItem], trail: String, needle: String,
                                prefixMatches: inout [SearchResult], otherMatches: inout [SearchResult]) {
        for item in items {
            if item.children.isEmpty {
                let title: String = item.title.lowercased()
                if title.hasPrefix(needle) {
                    prefixMatches.append(SearchResult(item: item, trail: trail))
                } else if title.contains(needle) {
                    otherMatches.append(SearchResult(item: item, trail: trail))
                }
            } else {
                let nextTrail: String = trail.isEmpty ? item.title : trail + " › " + item.title
                collect(item.children, trail: nextTrail, needle: needle,
                        prefixMatches: &prefixMatches, otherMatches: &otherMatches)
            }
        }
    }
}
