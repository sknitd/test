import Foundation
import MFCore

/// The contents of a profile export while it is being prepared for import.
struct ImportBundle {
    var profiles: [Profile]
    var workflows: [Workflow]
    var radialMenus: [RadialMenu]
    var templates: [PromptTemplate]

    /// Every distinct script anywhere in the bundle.
    var scripts: [ScriptAction] {
        var actions = profiles.flatMap(ActionTraversal.actions(in:))
        actions += workflows.flatMap { ActionTraversal.actions(in: $0.steps) }
        actions += radialMenus.flatMap { ActionTraversal.actions(in: $0.items) }
        return ScriptTrust.unique(actions.compactMap(\.script))
    }

    /// Identifiers of bundled prompts that are identical (apart from the id) to an existing
    /// prompt, mapped to that prompt's id.
    func templatesMatching(_ existing: [PromptTemplate]) -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for template in templates {
            if let match = existing.first(where: {
                $0.name == template.name && $0.systemPrompt == template.systemPrompt
                    && $0.userPrompt == template.userPrompt && $0.input == template.input
            }) {
                result[template.id] = match.id
            }
        }
        return result
    }

    /// Gives everything a new identifier and rewrites references inside the bundle to match.
    /// Prompts listed in `existingTemplates` are dropped and references to them point at the
    /// existing prompt instead. References to things outside the bundle are left alone.
    mutating func regenerateIdentifiers(reusing existingTemplates: [UUID: UUID]) {
        var workflowIDs: [UUID: UUID] = [:]
        var menuIDs: [UUID: UUID] = [:]
        var templateIDs = existingTemplates
        for index in workflows.indices {
            let fresh = UUID()
            if workflowIDs[workflows[index].id] == nil { workflowIDs[workflows[index].id] = fresh }
            workflows[index].id = fresh
        }
        for index in radialMenus.indices {
            let fresh = UUID()
            if menuIDs[radialMenus[index].id] == nil { menuIDs[radialMenus[index].id] = fresh }
            radialMenus[index].id = fresh
        }
        var keptTemplates: [PromptTemplate] = []
        for var template in templates where existingTemplates[template.id] == nil {
            let fresh = UUID()
            if templateIDs[template.id] == nil { templateIDs[template.id] = fresh }
            template.id = fresh
            keptTemplates.append(template)
        }
        templates = keptTemplates

        func remap(_ action: Action) -> Action {
            switch action {
            case .workflow(let id): return .workflow(id: workflowIDs[id] ?? id)
            case .radialMenu(let id): return .radialMenu(id: menuIDs[id] ?? id)
            case .ai(let id): return .ai(templateID: templateIDs[id] ?? id)
            case .none, .system, .window, .app, .keyboard, .mouse, .text, .script, .control: return action
            }
        }

        for profileIndex in profiles.indices {
            profiles[profileIndex].id = UUID()
            for bindingIndex in profiles[profileIndex].bindings.indices {
                profiles[profileIndex].bindings[bindingIndex].id = UUID()
                profiles[profileIndex].bindings[bindingIndex].action =
                    remap(profiles[profileIndex].bindings[bindingIndex].action)
            }
        }
        for index in workflows.indices {
            workflows[index].steps = ActionTraversal.mapActions(in: workflows[index].steps, remap)
        }
        for index in radialMenus.indices {
            radialMenus[index].items = ActionTraversal.mapItems(radialMenus[index].items) { item in
                var copy = item
                copy.id = UUID()
                copy.action = remap(item.action)
                return copy
            }
        }
    }

    /// Appends " (imported)" to names that already exist; returns one note per rename.
    mutating func resolveNameCollisions(with current: Configuration) -> [String] {
        var notes: [String] = []
        func rename(_ name: String, taken: inout Set<String>, what: String) -> String {
            var candidate = name
            var attempt = 1
            while taken.contains(candidate.lowercased()) {
                candidate = attempt == 1 ? "\(name) (imported)" : "\(name) (imported \(attempt))"
                attempt += 1
            }
            taken.insert(candidate.lowercased())
            if candidate != name { notes.append("A \(what) named “\(name)” already exists; the imported one is called “\(candidate)”.") }
            return candidate
        }
        var profileNames = Set(current.profiles.map { $0.name.lowercased() })
        for index in profiles.indices {
            profiles[index].name = rename(profiles[index].name, taken: &profileNames, what: "profile")
        }
        var workflowNames = Set(current.workflows.map { $0.name.lowercased() })
        for index in workflows.indices {
            workflows[index].name = rename(workflows[index].name, taken: &workflowNames, what: "workflow")
        }
        var menuNames = Set(current.radialMenus.map { $0.name.lowercased() })
        for index in radialMenus.indices {
            radialMenus[index].name = rename(radialMenus[index].name, taken: &menuNames, what: "radial menu")
        }
        var templateNames = Set(current.ai.templates.map { $0.name.lowercased() })
        for index in templates.indices {
            templates[index].name = rename(templates[index].name, taken: &templateNames, what: "AI prompt")
        }
        return notes
    }

    /// An imported menu must not take over a keyboard shortcut that is already in use.
    mutating func clearConflictingHotKeys(with current: Configuration) -> [String] {
        func signature(_ combo: KeyCombo) -> [Int] {
            [Int(combo.keyCode), combo.command ? 1 : 0, combo.option ? 1 : 0, combo.control ? 1 : 0,
             combo.shift ? 1 : 0, combo.function ? 1 : 0]
        }
        var used = Set(current.radialMenus.compactMap { $0.hotKey.map(signature) })
        var notes: [String] = []
        for index in radialMenus.indices {
            guard let hotKey = radialMenus[index].hotKey else { continue }
            if !used.insert(signature(hotKey)).inserted {
                radialMenus[index].hotKey = nil
                notes.append("The keyboard shortcut of radial menu “\(radialMenus[index].name)” is already in use and was removed.")
            }
        }
        return notes
    }

    /// True when any identifier in the bundle already exists in `configuration`.
    func collides(with configuration: Configuration) -> Bool {
        var existing = Set(configuration.profiles.map(\.id))
        existing.insert(configuration.globalProfileID)
        existing.formUnion(configuration.profiles.flatMap { $0.bindings.map(\.id) })
        existing.formUnion(configuration.workflows.map(\.id))
        existing.formUnion(configuration.radialMenus.map(\.id))
        existing.formUnion(configuration.radialMenus.flatMap { ActionTraversal.allItems(in: $0.items).map(\.id) })
        existing.formUnion(configuration.ai.templates.map(\.id))
        var mine = profiles.map(\.id) + profiles.flatMap { $0.bindings.map(\.id) } + workflows.map(\.id)
        mine += radialMenus.map(\.id) + radialMenus.flatMap { ActionTraversal.allItems(in: $0.items).map(\.id) }
        mine += templates.map(\.id)
        return mine.contains(where: existing.contains)
    }
}
