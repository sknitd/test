import Foundation
import MFCore

/// Restores a profile's bindings from the factory configuration (`DefaultConfiguration.make()`).
enum GestureDefaults {
    /// The factory profile that corresponds to `profile`: the factory global profile for the
    /// global profile; otherwise a factory app profile sharing a bundle identifier or the name.
    static func template(for profile: Profile, isGlobal: Bool, defaults: Configuration) -> Profile? {
        if isGlobal { return defaults.globalProfile }
        let bundleIDs = Set(profile.bundleIdentifiers)
        return defaults.profiles.first { candidate in
            guard candidate.id != defaults.globalProfileID else { return false }
            return !bundleIDs.isDisjoint(with: candidate.bundleIdentifiers) || candidate.name == profile.name
        }
    }

    /// Replaces bindings and scroll settings of `profileID` with the template's. Workflows, radial
    /// menus and AI templates that the factory bindings reference are added when missing so no
    /// restored binding points at nothing.
    static func apply(_ template: Profile, from defaults: Configuration, toProfile profileID: UUID,
                      configuration: inout Configuration) {
        guard let index = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        configuration.profiles[index].bindings = template.bindings.map { binding in
            var copy = binding
            copy.id = UUID()
            return copy
        }
        configuration.profiles[index].scroll = template.scroll
        for binding in template.bindings {
            switch binding.action {
            case .workflow(let id):
                if !configuration.workflows.contains(where: { $0.id == id }),
                   let workflow = defaults.workflows.first(where: { $0.id == id }) {
                    configuration.workflows.append(workflow)
                }
            case .radialMenu(let id):
                if !configuration.radialMenus.contains(where: { $0.id == id }),
                   let menu = defaults.radialMenus.first(where: { $0.id == id }) {
                    configuration.radialMenus.append(menu)
                }
            case .ai(let templateID):
                if !configuration.ai.templates.contains(where: { $0.id == templateID }),
                   let prompt = defaults.ai.templates.first(where: { $0.id == templateID }) {
                    configuration.ai.templates.append(prompt)
                }
            case .none, .system, .window, .app, .keyboard, .mouse, .text, .script, .control:
                break
            }
        }
    }
}
