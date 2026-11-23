import SwiftUI
import MFCore
import MFEngine

/// Everything about one radial menu.
@MainActor
struct RadialMenuDetailView: View {
    let menu: RadialMenu
    @Binding var selectedItemPath: [Int]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RadialMenuGeneralCard(menu: menu)
            HStack(alignment: .top, spacing: 16) {
                RadialMenuItemsCard(menu: menu, selectedItemPath: $selectedItemPath)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                RadialMenuPreviewCard(menu: menu, selectedItemPath: selectedItemPath)
                    .frame(width: 320)
            }
            RadialMenuItemEditorCard(menu: menu, selectedItemPath: $selectedItemPath)
            RadialMenuThemeCard(menu: menu)
        }
    }
}

/// Name, hot key and the "Show Now" test button.
@MainActor
struct RadialMenuGeneralCard: View {
    let menu: RadialMenu
    @Environment(AppModel.self) private var model

    private var name: Binding<String> {
        let id: UUID = menu.id
        return Binding<String>(
            get: { RadialMenuEditing.menu(id, in: model)?.name ?? "" },
            set: { newValue in RadialMenuEditing.update(id, in: model) { $0.name = newValue } }
        )
    }

    private var hotKey: Binding<KeyCombo?> {
        let id: UUID = menu.id
        return Binding<KeyCombo?>(
            get: { RadialMenuEditing.menu(id, in: model)?.hotKey },
            set: { newValue in RadialMenuEditing.update(id, in: model) { $0.hotKey = newValue } }
        )
    }

    /// Another menu that already uses the same shortcut, if any.
    private var hotKeyConflict: String? {
        guard let combo = menu.hotKey else { return nil }
        for other in model.configuration.radialMenus where other.id != menu.id {
            if let otherCombo = other.hotKey, otherCombo.keyCode == combo.keyCode, otherCombo.command == combo.command,
               otherCombo.option == combo.option, otherCombo.control == combo.control, otherCombo.shift == combo.shift,
               otherCombo.function == combo.function {
                return other.name
            }
        }
        return nil
    }

    var body: some View {
        MFCard("Menu", systemImage: "circle.grid.cross") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Name")
                    TextField("Name", text: name, prompt: Text("Menu name"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(Text("Menu name"))
                }
                HStack(spacing: 8) {
                    Text("Hot key")
                    KeyComboRecorder(combo: hotKey)
                    Spacer(minLength: 8)
                    Button(action: { model.showRadialMenu(menu.id) }) {
                        Label("Show Now", systemImage: "play.fill")
                    }
                    .disabled(menu.items.isEmpty)
                    .help("Opens this menu at the pointer")
                }
                Text("The hot key works in every app and needs Accessibility permission. Pressing it again closes the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let conflict = hotKeyConflict {
                    Label("“\(conflict)” uses the same hot key; only one of them can open.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }
}

/// Non-interactive rendering of the ring that contains the selected item (or the root ring).
@MainActor
struct RadialMenuPreviewCard: View {
    let menu: RadialMenu
    let selectedItemPath: [Int]?

    private var ringPath: [Int] {
        guard let path = selectedItemPath, !path.isEmpty else { return [] }
        return Array(path.dropLast())
    }

    var body: some View {
        let items: [RadialMenuItem] = Array((RadialItemTree.items(at: ringPath, in: menu.items) ?? menu.items)
            .prefix(RadialItemTree.maximumItemsPerRing))
        let layout = RadialOverlayLayout(diameter: min(menu.theme.diameter, 280), recentCount: 0)
        let isSubmenu: Bool = !ringPath.isEmpty
        MFCard("Preview", systemImage: "eye") {
            VStack(spacing: 8) {
                RadialRingView(items: items, highlightedIndex: selectedItemPath?.last, layout: layout,
                               accent: RadialThemeColor.accent(for: menu.theme), showLabels: menu.theme.showLabels,
                               centerSymbolName: isSubmenu ? "chevron.backward" : "xmark",
                               centerLabel: isSubmenu ? "Back" : "Close")
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(caption(itemCount: items.count, isSubmenu: isSubmenu))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func caption(itemCount: Int, isSubmenu: Bool) -> String {
        if itemCount == 0 { return "This ring is empty." }
        let ring: String = isSubmenu ? "Submenu ring" : "Root ring"
        let size: String = menu.theme.diameter > 280 ? " (shown smaller than the real \(Int(menu.theme.diameter)) pt)" : ""
        return "\(ring), not interactive\(size). Use Show Now to try the real menu."
    }
}
