import SwiftUI
import MFCore
import MFEngine

/// The action library: browse every built-in action, try it, see where it is used and manage
/// script approvals.
@MainActor
public struct ActionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation
    @State private var selectedCategory: ActionCategory?
    @State private var searchText: String = ""
    @State private var selectedTemplateID: String?
    @State private var scratchAction: Action = .none

    public init() {}

    public var body: some View {
        MFPage("Actions", subtitle: "Everything a gesture, radial menu item or workflow step can do. Pick one to try it.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ActionLibraryList(templates: filteredTemplates, selectedCategory: $selectedCategory,
                                      searchText: $searchText, selectedTemplateID: selectedTemplateID,
                                      onSelect: { template in select(template) })
                        .frame(width: 300)
                    ActionLibraryDetail(scratchAction: $scratchAction, templateName: selectedTemplateName)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                ActionScriptsCard()
            }
        }
    }

    private var filteredTemplates: [ActionTemplate] {
        let needle: String = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [ActionTemplate] = []
        for template in ActionCatalog.templates {
            if let category = selectedCategory, template.category != category { continue }
            if !needle.isEmpty && !template.name.lowercased().contains(needle)
                && !template.category.displayName.lowercased().contains(needle) { continue }
            result.append(template)
        }
        return result
    }

    private var selectedTemplateName: String? {
        guard let id = selectedTemplateID else { return nil }
        return ActionCatalog.templates.first(where: { $0.id == id })?.name
    }

    private func select(_ template: ActionTemplate) {
        selectedTemplateID = template.id
        scratchAction = template.action
    }
}

/// Category filter, search field and the list of templates.
@MainActor
struct ActionLibraryList: View {
    let templates: [ActionTemplate]
    @Binding var selectedCategory: ActionCategory?
    @Binding var searchText: String
    let selectedTemplateID: String?
    let onSelect: (ActionTemplate) -> Void

    var body: some View {
        MFCard("Library", systemImage: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(ActionCategory?.none)
                    Divider()
                    ForEach(ActionCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.symbolName)
                            .tag(ActionCategory?.some(category))
                    }
                }
                .labelsHidden()
                .accessibilityLabel(Text("Category filter"))
                TextField("Search", text: $searchText, prompt: Text("Search actions"))
                    .textFieldStyle(.roundedBorder)
                Divider()
                rows
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if templates.isEmpty {
            Text("No actions match.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(templates) { template in
                    ActionLibraryRow(template: template, isSelected: template.id == selectedTemplateID) {
                        onSelect(template)
                    }
                }
            }
        }
    }
}

@MainActor
struct ActionLibraryRow: View {
    let template: ActionTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: template.symbolName)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(template.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                availabilityBadge
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

    @ViewBuilder
    private var availabilityBadge: some View {
        switch model.availability(of: template.action) {
        case .available:
            EmptyView()
        case .needsPermission(let kind):
            MFStatusBadge("Needs \(kind.displayName)", style: .warning)
        case .unavailable:
            MFStatusBadge("Unavailable", style: .bad)
        }
    }
}

/// Scratch editor for the selected template plus the places that use an equal action.
@MainActor
struct ActionLibraryDetail: View {
    @Binding var scratchAction: Action
    let templateName: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MFCard(templateName ?? "Try an Action", systemImage: "play.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This is a scratch copy: changing it here does not change any gesture. Assign actions in Gestures, Radial Menu or Automation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionEditor(action: $scratchAction)
                }
            }
            MFCard("Where It Is Used", systemImage: "link") {
                ActionUsageList(action: scratchAction)
            }
        }
    }
}

@MainActor
struct ActionUsageList: View {
    let action: Action
    @Environment(AppModel.self) private var model

    var body: some View {
        let locations: [ActionUsageLocation] = ActionUsage.locations(of: action, in: model.configuration)
        VStack(alignment: .leading, spacing: 6) {
            if action == .none {
                Text("Pick an action to see which gestures, menus and workflows use it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if locations.isEmpty {
                Text("Nothing uses exactly this action (same parameters) yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(locations) { location in
                    ActionUsageRow(location: location)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct ActionUsageRow: View {
    let location: ActionUsageLocation

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(kindTitle)
                .foregroundStyle(.secondary)
            Text(location.container)
                .fontWeight(.medium)
            Text(location.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch location.kind {
        case .binding: return "hand.tap"
        case .radialMenu: return "circle.grid.cross"
        case .workflow: return "flowchart"
        }
    }

    private var kindTitle: String {
        switch location.kind {
        case .binding: return "Profile"
        case .radialMenu: return "Radial menu"
        case .workflow: return "Workflow"
        }
    }
}
