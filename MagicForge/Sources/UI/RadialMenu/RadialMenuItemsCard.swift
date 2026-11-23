import SwiftUI
import MFCore
import MFEngine

/// The item tree of a menu with add / reorder / delete controls.
@MainActor
struct RadialMenuItemsCard: View {
    let menu: RadialMenu
    @Binding var selectedItemPath: [Int]?
    @Environment(AppModel.self) private var model

    var body: some View {
        let flat: [RadialItemTree.FlatItem] = RadialItemTree.flatten(menu.items)
        MFCard("Items", systemImage: "list.bullet.indent") {
            VStack(alignment: .leading, spacing: 8) {
                if flat.isEmpty {
                    Text("No items yet. Add up to \(RadialItemTree.maximumItemsPerRing) per ring.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(flat) { entry in
                            RadialMenuItemRow(entry: entry, isSelected: entry.path == selectedItemPath,
                                              onSelect: { selectedItemPath = entry.path })
                        }
                    }
                }
                Divider()
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: { addItem(toChildrenOf: []) }) {
                Label("Add Item", systemImage: "plus")
            }
            .disabled(menu.items.count >= RadialItemTree.maximumItemsPerRing)
            .help("Add an item to the root ring")
            Button(action: { if let path = selectedItemPath { addItem(toChildrenOf: path) } }) {
                Label("Add Submenu Item", systemImage: "arrow.turn.down.right")
            }
            .disabled(!canAddChild)
            .help("Add an item inside the selected item, turning it into a submenu")
            Spacer(minLength: 4)
            Button(action: { move(by: -1) }) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMove(by: -1))
            .accessibilityLabel(Text("Move item earlier"))
            .help("Move earlier in its ring")
            Button(action: { move(by: 1) }) {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMove(by: 1))
            .accessibilityLabel(Text("Move item later"))
            .help("Move later in its ring")
            Button(action: { deleteSelected() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(selectedItemPath == nil)
            .accessibilityLabel(Text("Delete item"))
            .help("Delete the selected item and its submenu")
        }
        .controlSize(.small)
    }

    private var canAddChild: Bool {
        guard let path = selectedItemPath, path.count < RadialItemTree.maximumDepth,
              let item = RadialItemTree.item(at: path, in: menu.items) else { return false }
        return item.children.count < RadialItemTree.maximumItemsPerRing
    }

    private func canMove(by offset: Int) -> Bool {
        guard let path = selectedItemPath else { return false }
        return RadialItemTree.canMoveItem(at: path, by: offset, in: menu.items)
    }

    private func addItem(toChildrenOf parent: [Int]) {
        var created: [Int]?
        let item = RadialMenuItem(title: "New Item", symbolName: "circle")
        RadialMenuEditing.update(menu.id, in: model) { edited in
            created = RadialItemTree.appendItem(item, toChildrenOf: parent, in: &edited.items)
        }
        if let path = created { selectedItemPath = path }
    }

    private func move(by offset: Int) {
        guard let path = selectedItemPath else { return }
        var moved: [Int]?
        RadialMenuEditing.update(menu.id, in: model) { edited in
            moved = RadialItemTree.moveItem(at: path, by: offset, in: &edited.items)
        }
        if let destination = moved { selectedItemPath = destination }
    }

    private func deleteSelected() {
        guard let path = selectedItemPath else { return }
        selectedItemPath = nil
        RadialMenuEditing.update(menu.id, in: model) { edited in
            _ = RadialItemTree.removeItem(at: path, in: &edited.items)
        }
    }
}

@MainActor
struct RadialMenuItemRow: View {
    let entry: RadialItemTree.FlatItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: { onSelect() }) {
            HStack(spacing: 8) {
                Image(systemName: entry.item.symbolName)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(entry.item.title.isEmpty ? "Untitled" : entry.item.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .padding(.leading, CGFloat(max(entry.depth - 1, 0)) * 18)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var trailing: some View {
        if entry.item.children.isEmpty {
            ActionLabel(action: entry.item.action, showsSummary: false)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Submenu · \(entry.item.children.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Editor for the selected item.
@MainActor
struct RadialMenuItemEditorCard: View {
    let menu: RadialMenu
    @Binding var selectedItemPath: [Int]?
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Selected Item", systemImage: "pencil") {
            if let path = selectedItemPath, let item = RadialItemTree.item(at: path, in: menu.items) {
                RadialMenuItemEditor(item: RadialMenuEditing.itemBinding(menuID: menu.id, path: path, fallback: item,
                                                                         model: model))
                    .id(item.id)
            } else {
                Text("Select an item above to edit its title, symbol and action.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct RadialMenuItemEditor: View {
    @Binding var item: RadialMenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Title")
                TextField("Title", text: $item.title, prompt: Text("Shown under the icon"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(Text("Item title"))
            }
            ActionSymbolField(title: "Symbol", symbolName: $item.symbolName)
            Divider()
            if item.children.isEmpty {
                ActionEditor(action: $item.action)
            } else {
                Text("This item opens a submenu with \(item.children.count) item\(item.children.count == 1 ? "" : "s"), so it has no action of its own. Delete its submenu items to give it an action again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
