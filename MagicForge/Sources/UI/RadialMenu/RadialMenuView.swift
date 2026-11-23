import SwiftUI
import MFCore
import MFEngine

/// Configuration of radial menus: list of menus, items, theme, hot key and a live preview.
@MainActor
public struct RadialMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation
    @State private var selectedMenuID: UUID?
    @State private var selectedItemPath: [Int]?
    @State private var pendingDeleteID: UUID?

    public init() {}

    private var effectiveSelection: UUID? {
        let menus: [RadialMenu] = model.configuration.radialMenus
        if let id = selectedMenuID, menus.contains(where: { $0.id == id }) { return id }
        return menus.first?.id
    }

    public var body: some View {
        MFPage("Radial Menu", subtitle: "A ring of actions that appears at the pointer. Open it from a gesture, a hot key or a workflow.") {
            HStack(alignment: .top, spacing: 16) {
                RadialMenuListPane(selectedID: effectiveSelection,
                                   onSelect: { id in select(id) },
                                   onAdd: { select(RadialMenuEditing.add(to: model)) },
                                   onDuplicate: { id in select(RadialMenuEditing.duplicate(id, in: model)) },
                                   onDelete: { id in pendingDeleteID = id })
                    .frame(width: 230)
                detail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("Delete Menu", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = effectiveSelection, let menu = RadialMenuEditing.menu(id, in: model) {
            RadialMenuDetailView(menu: menu, selectedItemPath: $selectedItemPath)
                .id(id)
        } else {
            MFEmptyState(systemImage: "circle.grid.cross", title: "No Radial Menus Yet",
                         message: "Add a menu with the + button, give it a few items, then bind “Show Radial Menu” to a gesture.")
        }
    }

    private func select(_ id: UUID?) {
        selectedItemPath = nil
        selectedMenuID = id
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingDeleteID != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteID = nil }
            }
        )
    }

    private var deleteTitle: String {
        guard let id = pendingDeleteID, let menu = RadialMenuEditing.menu(id, in: model) else { return "Delete menu?" }
        return "Delete “\(menu.name)”?"
    }

    private var deleteMessage: String {
        guard let id = pendingDeleteID else { return "" }
        let uses: Int = ActionUsage.locations(of: .radialMenu(id: id), in: model.configuration).count
        if uses == 0 { return "This cannot be undone." }
        return "It is used in \(uses) place\(uses == 1 ? "" : "s"), which will stop working. This cannot be undone."
    }

    private func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        selectedItemPath = nil
        RadialMenuEditing.delete(id, in: model)
    }
}

@MainActor
struct RadialMenuListPane: View {
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Menus", systemImage: "list.bullet") {
            VStack(alignment: .leading, spacing: 8) {
                rows
                Divider()
                controls
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let menus: [RadialMenu] = model.configuration.radialMenus
        if menus.isEmpty {
            Text("None yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(menus) { menu in
                    RadialMenuListRow(menu: menu, isSelected: menu.id == selectedID, onSelect: { onSelect(menu.id) })
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: { onAdd() }) {
                Image(systemName: "plus")
            }
            .accessibilityLabel(Text("Add menu"))
            .help("Add a radial menu")
            Button(action: { if let id = selectedID { onDuplicate(id) } }) {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(selectedID == nil)
            .accessibilityLabel(Text("Duplicate menu"))
            .help("Duplicate the selected menu")
            Button(action: { if let id = selectedID { onDelete(id) } }) {
                Image(systemName: "trash")
            }
            .disabled(selectedID == nil)
            .accessibilityLabel(Text("Delete menu"))
            .help("Delete the selected menu")
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
    }
}

@MainActor
struct RadialMenuListRow: View {
    let menu: RadialMenu
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: { onSelect() }) {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.cross")
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(menu.name.isEmpty ? "Untitled" : menu.name)
                        .lineLimit(1)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailText: String {
        let count: Int = menu.items.count
        let items: String = count == 1 ? "1 item" : "\(count) items"
        if let hotKey = menu.hotKey { return "\(items) · \(hotKey.displayString)" }
        return items
    }
}
