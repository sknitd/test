import SwiftUI
import MFCore
import MFEngine
import MFProfiles

/// The bindings table of the profile being edited.
@MainActor
public struct GesturesView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    @State private var searchText: String = ""
    @State private var sequenceDraft: GestureBinding?
    @State private var isConfirmingReset: Bool = false
    @State private var scrollOverlapBinding: GestureBinding?
    @State private var factoryConfiguration: Configuration?

    public init() {}

    private var profileID: UUID {
        GestureUI.resolvedProfileID(navigation.editingProfileID, in: model.configuration)
    }

    private var profile: Profile? { GestureUI.profile(profileID, in: model.configuration) }

    private var isGlobal: Bool { profileID == model.configuration.globalProfileID }

    public var body: some View {
        MFPage("Gestures", subtitle: "What each gesture does in the selected profile.") {
            GesturesToolbar(
                searchText: $searchText,
                boundKinds: boundKinds,
                canReset: resetTemplate != nil,
                onAdd: { kind in openStudio(kind) },
                onNewSequence: { sequenceDraft = GestureSequenceBuilderSheet.newDraft() },
                onReset: { isConfirmingReset = true }
            )
            conflictSummary
            bindingSections
        }
        .onAppear {
            if factoryConfiguration == nil { factoryConfiguration = DefaultConfiguration.make() }
        }
        .sheet(item: $sequenceDraft) { draft in
            GestureSequenceBuilderSheet(profileID: profileID, binding: draft, isNew: !containsBinding(draft.id))
        }
        .confirmationDialog("Reset “\(profile?.name ?? "profile")” to defaults?", isPresented: $isConfirmingReset) {
            Button("Reset Profile", role: .destructive) { resetProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All bindings and the scrolling settings of this profile are replaced with the factory defaults.")
        }
        .confirmationDialog("This gesture overlaps native scrolling", isPresented: overlapDialogPresented) {
            Button("Enable Anyway") { confirmScrollOverlap() }
            Button("Cancel", role: .cancel) { scrollOverlapBinding = nil }
        } message: {
            Text("One-finger motion on a Magic Mouse is scrolling. With this binding enabled, every scroll in that "
                + "direction also runs its action.")
        }
    }

    // MARK: Derived data

    private var bindings: [GestureBinding] { profile?.bindings ?? [] }

    private var boundKinds: Set<GestureKind> {
        var result = Set<GestureKind>()
        for binding in bindings {
            if case .single(let kind) = binding.trigger { result.insert(kind) }
        }
        return result
    }

    private var filteredBindings: [GestureBinding] {
        let query: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return bindings }
        return bindings.filter { binding in
            binding.trigger.displayName.localizedCaseInsensitiveContains(query)
                || binding.action.displayName.localizedCaseInsensitiveContains(query)
                || binding.note.localizedCaseInsensitiveContains(query)
        }
    }

    private func singleBindings(in category: GestureKind.Category, from all: [GestureBinding]) -> [GestureBinding] {
        all.filter { binding in
            if case .single(let kind) = binding.trigger { return kind.category == category }
            return false
        }
    }

    private func sequenceBindings(from all: [GestureBinding]) -> [GestureBinding] {
        all.filter { binding in
            if case .sequence = binding.trigger { return true }
            return false
        }
    }

    private func containsBinding(_ id: UUID) -> Bool { bindings.contains { $0.id == id } }

    private var resetTemplate: Profile? {
        guard let profile, let factoryConfiguration else { return nil }
        return GestureDefaults.template(for: profile, isGlobal: isGlobal, defaults: factoryConfiguration)
    }

    // MARK: Sections

    @ViewBuilder private var conflictSummary: some View {
        let conflicts: [BindingConflict] = model.conflicts(inProfile: profileID)
        if !conflicts.isEmpty {
            MFCard("\(conflicts.count) binding \(conflicts.count == 1 ? "issue" : "issues")",
                   systemImage: "exclamationmark.triangle") {
                GestureConflictList(conflicts: conflicts)
            }
        }
    }

    @ViewBuilder private var bindingSections: some View {
        let visible: [GestureBinding] = filteredBindings
        let conflicts: [BindingConflict] = model.conflicts(inProfile: profileID)
        if bindings.isEmpty {
            MFEmptyState(systemImage: "hand.tap", title: "No bindings in this profile",
                         message: "Use Add Binding to assign an action to a gesture.")
        } else if visible.isEmpty {
            MFEmptyState(systemImage: "magnifyingglass", title: "No matching bindings",
                         message: "No gesture, action or note matches “\(searchText)”.")
        } else {
            ForEach(GestureKind.Category.allCases, id: \.self) { category in
                GestureBindingSection(
                    title: category.displayName,
                    systemImage: category.symbolName,
                    bindings: singleBindings(in: category, from: visible),
                    conflicts: conflicts,
                    onSetEnabled: { binding, isEnabled in setEnabled(isEnabled, binding: binding) },
                    onEdit: { binding in edit(binding) },
                    onDelete: { binding in delete(binding) }
                )
            }
            GestureBindingSection(
                title: "Sequences",
                systemImage: "list.number",
                bindings: sequenceBindings(from: visible),
                conflicts: conflicts,
                onSetEnabled: { binding, isEnabled in setEnabled(isEnabled, binding: binding) },
                onEdit: { binding in edit(binding) },
                onDelete: { binding in delete(binding) }
            )
        }
    }

    // MARK: Actions

    private func openStudio(_ kind: GestureKind) {
        navigation.selectedGesture = kind
        navigation.section = .gestureStudio
    }

    private func edit(_ binding: GestureBinding) {
        switch binding.trigger {
        case .single(let kind): openStudio(kind)
        case .sequence: sequenceDraft = binding
        }
    }

    private func delete(_ binding: GestureBinding) {
        let profileID: UUID = self.profileID
        model.update { configuration in
            GestureUI.removeBinding(binding.id, fromProfile: profileID, configuration: &configuration)
        }
    }

    private func setEnabled(_ isEnabled: Bool, binding: GestureBinding) {
        // Enabling a gesture that doubles as native scrolling needs an explicit confirmation.
        if isEnabled && binding.trigger.kinds.contains(where: { $0.overlapsNativeScrolling }) {
            scrollOverlapBinding = binding
            return
        }
        applyEnabled(isEnabled, bindingID: binding.id)
    }

    private func applyEnabled(_ isEnabled: Bool, bindingID: UUID) {
        let profileID: UUID = self.profileID
        model.update { configuration in
            GestureUI.setEnabled(isEnabled, bindingID: bindingID, inProfile: profileID, configuration: &configuration)
        }
    }

    private var overlapDialogPresented: Binding<Bool> {
        Binding<Bool>(
            get: { scrollOverlapBinding != nil },
            set: { isPresented in
                if !isPresented { scrollOverlapBinding = nil }
            }
        )
    }

    private func confirmScrollOverlap() {
        if let binding = scrollOverlapBinding { applyEnabled(true, bindingID: binding.id) }
        scrollOverlapBinding = nil
    }

    private func resetProfile() {
        guard let template = resetTemplate, let defaults = factoryConfiguration else { return }
        let profileID: UUID = self.profileID
        model.update { configuration in
            GestureDefaults.apply(template, from: defaults, toProfile: profileID, configuration: &configuration)
        }
    }
}

/// A card with the bindings of one category; hidden when it has none.
@MainActor
private struct GestureBindingSection: View {
    let title: String
    let systemImage: String
    let bindings: [GestureBinding]
    let conflicts: [BindingConflict]
    let onSetEnabled: (GestureBinding, Bool) -> Void
    let onEdit: (GestureBinding) -> Void
    let onDelete: (GestureBinding) -> Void

    var body: some View {
        if !bindings.isEmpty {
            MFCard(title, systemImage: systemImage) {
                VStack(spacing: 0) {
                    ForEach(bindings) { binding in
                        GestureBindingRow(
                            binding: binding,
                            conflicts: conflicts.filter { $0.bindingIDs.contains(binding.id) },
                            onSetEnabled: { isEnabled in onSetEnabled(binding, isEnabled) },
                            onEdit: { onEdit(binding) },
                            onDelete: { onDelete(binding) }
                        )
                        if binding.id != bindings.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// Profile picker, search and the add / reset controls above the table.
@MainActor
private struct GesturesToolbar: View {
    @Binding var searchText: String
    let boundKinds: Set<GestureKind>
    let canReset: Bool
    let onAdd: (GestureKind) -> Void
    let onNewSequence: () -> Void
    let onReset: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            GestureProfileScopePicker()
            searchField
            Spacer(minLength: 8)
            addMenu
            Button(action: onNewSequence) {
                Label("New Sequence…", systemImage: "list.number")
            }
            .help("Bind an action to 2–4 gestures performed back-to-back")
            Button(action: onReset) {
                Label("Reset…", systemImage: "arrow.counterclockwise")
            }
            .disabled(!canReset)
            .help(canReset ? "Replace this profile's bindings with the factory defaults"
                : "There are no factory defaults for this profile")
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search gestures and actions", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .frame(minWidth: 160, maxWidth: 260)
    }

    private var addMenu: some View {
        Menu {
            ForEach(GestureKind.Category.allCases, id: \.self) { category in
                Section(category.displayName) {
                    ForEach(unboundKinds(in: category), id: \.self) { kind in
                        Button(menuTitle(kind)) { onAdd(kind) }
                    }
                }
            }
        } label: {
            Label("Add Binding", systemImage: "plus")
        }
        .fixedSize()
        .help("Assign an action to a gesture that is not bound in this profile yet")
    }

    private func unboundKinds(in category: GestureKind.Category) -> [GestureKind] {
        GestureKind.allCases.filter { $0.category == category && !boundKinds.contains($0) }
    }

    private func menuTitle(_ kind: GestureKind) -> String {
        if case .unavailable = model.availability(of: kind) { return "\(kind.displayName) — unavailable now" }
        return kind.displayName
    }
}
