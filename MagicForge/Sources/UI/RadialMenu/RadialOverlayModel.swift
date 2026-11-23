import SwiftUI
import Observation
import MFCore

/// State of the floating radial menu while it is open: the current ring, the highlight and the
/// search fallback. Pointer and key input is translated by `RadialMenuController` and fed in here.
@MainActor
@Observable
final class RadialOverlayModel {
    enum KeyInput {
        case escape, activate, deleteBackward
        case next, previous
        case digit(Int)
        case text(String)
    }

    let menu: RadialMenu
    let recent: [RadialMenuItem]
    let layout: RadialOverlayLayout

    /// Submenu items that were opened, outermost first. Empty = root ring.
    private(set) var stack: [RadialMenuItem] = []
    private(set) var highlightedIndex: Int?
    private(set) var searchText: String = ""
    private(set) var searchResults: [RadialItemTree.SearchResult] = []
    private(set) var searchHighlight: Int = 0
    /// Drives the appear / disappear animation.
    var isVisible: Bool = false

    @ObservationIgnored var onChoose: ((RadialMenuItem) -> Void)?
    @ObservationIgnored var onDismiss: (() -> Void)?

    init(menu: RadialMenu, recent: [RadialMenuItem]) {
        self.menu = menu
        let usableRecent: [RadialMenuItem] = menu.theme.showRecentActions
            ? Array(recent.prefix(RadialOverlayLayout.maximumRecents)) : []
        self.recent = usableRecent
        self.layout = RadialOverlayLayout(diameter: menu.theme.diameter, recentCount: usableRecent.count)
    }

    // MARK: Derived state

    var currentItems: [RadialMenuItem] {
        let items: [RadialMenuItem] = stack.last?.children ?? menu.items
        return Array(items.prefix(RadialItemTree.maximumItemsPerRing))
    }

    var isSearching: Bool { !searchText.isEmpty }
    var isInSubmenu: Bool { !stack.isEmpty }
    var showsRecents: Bool { !isSearching && !isInSubmenu && !recent.isEmpty }

    var shownSearchResults: [RadialItemTree.SearchResult] {
        Array(searchResults.prefix(RadialOverlayLayout.maximumSearchResults))
    }

    var centerSymbolName: String { isInSubmenu ? "chevron.backward" : "xmark" }
    var centerLabel: String { isInSubmenu ? "Back" : "Close" }

    // MARK: Pointer

    /// `point` is in the panel's top-left based coordinate space.
    func pointerMoved(to point: CGPoint) {
        if isSearching {
            if case .searchResult(let index) = layout.searchHit(at: point, resultCount: searchResults.count) {
                searchHighlight = index
            }
            return
        }
        switch layout.hit(at: point, itemCount: currentItems.count, showsRecents: showsRecents) {
        case .item(let index):
            if highlightedIndex != index { highlightedIndex = index }
        case .center, .recent, .searchResult, .outside:
            if highlightedIndex != nil { highlightedIndex = nil }
        }
    }

    func pointerExited() {
        if !isSearching && highlightedIndex != nil { highlightedIndex = nil }
    }

    func clicked(at point: CGPoint) {
        if isSearching {
            switch layout.searchHit(at: point, resultCount: searchResults.count) {
            case .searchResult(let index):
                chooseSearchResult(index)
            case .outside:
                onDismiss?()
            case .center, .item, .recent:
                break
            }
            return
        }
        switch layout.hit(at: point, itemCount: currentItems.count, showsRecents: showsRecents) {
        case .item(let index):
            activate(index)
        case .recent(let index):
            if recent.indices.contains(index) { onChoose?(recent[index]) }
        case .center:
            if isInSubmenu { goBack() } else { onDismiss?() }
        case .outside:
            onDismiss?()
        case .searchResult:
            break
        }
    }

    // MARK: Keyboard

    func handle(_ input: KeyInput) {
        switch input {
        case .escape:
            if isSearching { setSearch("") } else { onDismiss?() }
        case .activate:
            if isSearching {
                chooseSearchResult(searchHighlight)
            } else if let index = highlightedIndex {
                activate(index)
            }
        case .deleteBackward:
            if isSearching {
                setSearch(String(searchText.dropLast()))
            } else if isInSubmenu {
                goBack()
            }
        case .next:
            moveHighlight(by: 1)
        case .previous:
            moveHighlight(by: -1)
        case .digit(let number):
            if isSearching {
                setSearch(searchText + String(number))
            } else if number >= 1 && number <= currentItems.count {
                activate(number - 1)
            }
        case .text(let text):
            if isSearching || text != " " {
                setSearch(searchText + text)
            }
        }
    }

    private func moveHighlight(by offset: Int) {
        if isSearching {
            let count: Int = shownSearchResults.count
            guard count > 0 else { return }
            searchHighlight = (searchHighlight + offset + count) % count
            return
        }
        let count: Int = currentItems.count
        guard count > 0 else { return }
        if let current = highlightedIndex {
            highlightedIndex = (current + offset + count) % count
        } else {
            highlightedIndex = offset > 0 ? 0 : count - 1
        }
    }

    private func setSearch(_ text: String) {
        searchText = text
        searchResults = RadialItemTree.search(text, in: menu.items)
        searchHighlight = 0
        if !text.isEmpty { highlightedIndex = nil }
    }

    private func chooseSearchResult(_ index: Int) {
        let results: [RadialItemTree.SearchResult] = shownSearchResults
        guard results.indices.contains(index) else { return }
        onChoose?(results[index].item)
    }

    // MARK: Navigation

    private func activate(_ index: Int) {
        let items: [RadialMenuItem] = currentItems
        guard items.indices.contains(index) else { return }
        let item: RadialMenuItem = items[index]
        // Level 1 is the root ring; submenus are only followed down to the depth limit.
        if !item.children.isEmpty && stack.count + 1 < RadialItemTree.maximumDepth {
            stack.append(item)
            highlightedIndex = nil
        } else {
            onChoose?(item)
        }
    }

    private func goBack() {
        if !stack.isEmpty {
            stack.removeLast()
            highlightedIndex = nil
        }
    }
}
