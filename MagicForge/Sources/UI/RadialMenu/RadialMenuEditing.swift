import SwiftUI
import MFCore
import MFEngine

/// Mutations of radial menus, all funnelled through `AppModel.update`.
@MainActor
enum RadialMenuEditing {
    static func menu(_ id: UUID, in model: AppModel) -> RadialMenu? {
        model.configuration.radialMenus.first(where: { $0.id == id })
    }

    static func update(_ id: UUID, in model: AppModel, _ body: (inout RadialMenu) -> Void) {
        model.update { configuration in
            guard let index = configuration.radialMenus.firstIndex(where: { $0.id == id }) else { return }
            body(&configuration.radialMenus[index])
        }
    }

    private static func uniqueName(_ base: String, in model: AppModel) -> String {
        let names: [String] = model.configuration.radialMenus.map { $0.name }
        return WorkflowText.uniqueName(base, existing: names)
    }

    static func add(to model: AppModel) -> UUID {
        let menu = RadialMenu(name: uniqueName("New Menu", in: model))
        model.update { configuration in
            configuration.radialMenus.append(menu)
        }
        return menu.id
    }

    static func duplicate(_ id: UUID, in model: AppModel) -> UUID? {
        guard let original = menu(id, in: model) else { return nil }
        // The copy gets fresh item identifiers and no hot key (a shortcut can open only one menu).
        let copy = RadialMenu(id: UUID(), name: uniqueName(original.name + " Copy", in: model),
                              items: RadialItemTree.withFreshIdentifiers(original.items), theme: original.theme,
                              hotKey: nil)
        model.update { configuration in
            configuration.radialMenus.append(copy)
        }
        return copy.id
    }

    static func delete(_ id: UUID, in model: AppModel) {
        model.update { configuration in
            configuration.radialMenus.removeAll(where: { $0.id == id })
        }
    }

    static func itemBinding(menuID: UUID, path: [Int], fallback: RadialMenuItem, model: AppModel) -> Binding<RadialMenuItem> {
        Binding<RadialMenuItem>(
            get: {
                guard let menu = RadialMenuEditing.menu(menuID, in: model),
                      let item = RadialItemTree.item(at: path, in: menu.items) else { return fallback }
                return item
            },
            set: { newValue in
                RadialMenuEditing.update(menuID, in: model) { menu in
                    _ = RadialItemTree.updateItem(at: path, in: &menu.items) { item in
                        item = newValue
                    }
                }
            }
        )
    }
}
