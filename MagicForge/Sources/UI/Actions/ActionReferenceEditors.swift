import SwiftUI
import MFCore
import MFEngine

// Pickers for actions that reference something else in the configuration.

@MainActor
struct ActionWorkflowPicker: View {
    @Binding var action: Action
    @Environment(AppModel.self) private var model

    private var currentID: UUID? {
        if case .workflow(let id) = action { return id }
        return nil
    }

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { currentID },
            set: { newValue in
                if let id = newValue { action = .workflow(id: id) }
            }
        )
    }

    var body: some View {
        let workflows: [Workflow] = model.configuration.workflows
        let isMissing: Bool = currentID != nil && !workflows.contains(where: { $0.id == currentID })
        VStack(alignment: .leading, spacing: 6) {
            if workflows.isEmpty && currentID == nil {
                Text("There are no workflows yet. Create one in the Automation section, then pick it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Workflow", selection: selection) {
                    if currentID == nil {
                        Text("Choose…").tag(UUID?.none)
                    }
                    if isMissing {
                        Text("Missing workflow").tag(currentID)
                    }
                    ForEach(workflows) { workflow in
                        Text(workflow.name).tag(UUID?.some(workflow.id))
                    }
                }
                if isMissing {
                    Text("The workflow this action pointed to was deleted. Pick another one.")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }
}

@MainActor
struct ActionRadialMenuPicker: View {
    @Binding var action: Action
    @Environment(AppModel.self) private var model

    private var currentID: UUID? {
        if case .radialMenu(let id) = action { return id }
        return nil
    }

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { currentID },
            set: { newValue in
                if let id = newValue { action = .radialMenu(id: id) }
            }
        )
    }

    var body: some View {
        let menus: [RadialMenu] = model.configuration.radialMenus
        let isMissing: Bool = currentID != nil && !menus.contains(where: { $0.id == currentID })
        VStack(alignment: .leading, spacing: 6) {
            if menus.isEmpty && currentID == nil {
                Text("There are no radial menus yet. Create one in the Radial Menu section, then pick it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Radial menu", selection: selection) {
                    if currentID == nil {
                        Text("Choose…").tag(UUID?.none)
                    }
                    if isMissing {
                        Text("Missing menu").tag(currentID)
                    }
                    ForEach(menus) { menu in
                        Text(menu.name).tag(UUID?.some(menu.id))
                    }
                }
                if isMissing {
                    Text("The menu this action pointed to was deleted. Pick another one.")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }
}

@MainActor
struct ActionAITemplatePicker: View {
    @Binding var action: Action
    @Environment(AppModel.self) private var model

    private var currentID: UUID? {
        if case .ai(let id) = action { return id }
        return nil
    }

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { currentID },
            set: { newValue in
                if let id = newValue { action = .ai(templateID: id) }
            }
        )
    }

    var body: some View {
        let templates: [PromptTemplate] = model.configuration.ai.templates
        let isMissing: Bool = currentID != nil && !templates.contains(where: { $0.id == currentID })
        VStack(alignment: .leading, spacing: 6) {
            if templates.isEmpty && currentID == nil {
                Text("There are no prompt templates yet. Add one in the AI section, then pick it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Prompt template", selection: selection) {
                    if currentID == nil {
                        Text("Choose…").tag(UUID?.none)
                    }
                    if isMissing {
                        Text("Missing template").tag(currentID)
                    }
                    ForEach(templates) { template in
                        Text(template.name).tag(UUID?.some(template.id))
                    }
                }
                if isMissing {
                    Text("The template this action pointed to was deleted. Pick another one.")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
            if !model.configuration.ai.isEnabled {
                Text("AI integration is turned off, so this action does nothing until you enable it in the AI section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
