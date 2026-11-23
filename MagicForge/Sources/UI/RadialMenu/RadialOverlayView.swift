import SwiftUI
import MFCore

/// Content of the floating radial menu panel. Rendering only: pointer and keyboard input is
/// handled in AppKit by `RadialMenuController` using the same `RadialOverlayLayout`.
@MainActor
struct RadialOverlayView: View {
    let model: RadialOverlayModel

    var body: some View {
        let size: CGSize = model.layout.panelSize
        ZStack(alignment: .topLeading) {
            if model.isSearching {
                RadialSearchListView(model: model)
            } else {
                ring
                if model.showsRecents {
                    RadialRecentRow(model: model)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(model.isVisible ? 1 : 0.82)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: model.isVisible)
        .onAppear { model.isVisible = true }
    }

    private var ring: some View {
        let center: CGPoint = model.layout.ringCenter
        return RadialRingView(items: model.currentItems, highlightedIndex: model.highlightedIndex,
                              layout: model.layout, accent: RadialThemeColor.accent(for: model.menu.theme),
                              showLabels: model.menu.theme.showLabels, centerSymbolName: model.centerSymbolName,
                              centerLabel: model.centerLabel)
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 3)
            .position(x: center.x, y: center.y)
    }
}

/// Row of recently used items under the root ring.
@MainActor
struct RadialRecentRow: View {
    let model: RadialOverlayModel

    var body: some View {
        ForEach(model.recent.indices, id: \.self) { index in
            chip(index)
        }
    }

    private func chip(_ index: Int) -> some View {
        let rect: CGRect = model.layout.recentRect(index)
        let item: RadialMenuItem = model.recent[index]
        return Image(systemName: item.symbolName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: rect.width, height: rect.height)
            .background(Circle().fill(.ultraThinMaterial))
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.72)))
            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            .position(x: rect.midX, y: rect.midY)
            .accessibilityLabel(Text("Recent: \(item.title)"))
    }
}

/// Flat list of search matches shown instead of the ring while the user types.
@MainActor
struct RadialSearchListView: View {
    let model: RadialOverlayModel

    var body: some View {
        let results: [RadialItemTree.SearchResult] = model.shownSearchResults
        let total: Int = model.searchResults.count
        let box: CGRect = model.layout.searchRect(resultCount: total)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 3)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
            header
                .frame(width: box.width - 20, height: RadialOverlayLayout.searchHeaderHeight, alignment: .leading)
                .position(x: box.midX, y: box.minY + RadialOverlayLayout.searchHeaderHeight / 2)
            if results.isEmpty {
                Text("No matching items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .position(x: box.midX, y: box.minY + RadialOverlayLayout.searchHeaderHeight + RadialOverlayLayout.searchRowHeight / 2)
            }
            ForEach(results.indices, id: \.self) { index in
                row(results[index], index: index, total: total)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(model.searchText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("↩ choose · esc back")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ result: RadialItemTree.SearchResult, index: Int, total: Int) -> some View {
        let rect: CGRect = model.layout.searchRowRect(index, resultCount: total)
        let isHighlighted: Bool = index == model.searchHighlight
        let accent: Color = RadialThemeColor.accent(for: model.menu.theme)
        return HStack(spacing: 8) {
            Image(systemName: result.item.symbolName)
                .frame(width: 20)
            Text(result.item.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(result.trail)
                .font(.caption)
                .lineLimit(1)
                .opacity(0.7)
        }
        .padding(.horizontal, 8)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .frame(width: rect.width, height: rect.height - 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? accent.opacity(0.85) : Color.clear))
        .position(x: rect.midX, y: rect.midY)
    }
}
