import SwiftUI
import MFCore
import MFEngine

/// Visual editor for one gesture binding: pick a gesture, watch how it is performed, assign an
/// action, tune it, test it and review conflicts before saving. Edits live in a local draft
/// until "Save".
@MainActor
public struct GestureStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    @State private var draft = GestureBinding(trigger: .single(.oneFingerTap), action: .none)
    /// The saved binding the draft started from; nil while the draft is a new binding.
    @State private var baseline: GestureBinding?

    public init() {}

    private var profileID: UUID {
        GestureUI.resolvedProfileID(navigation.editingProfileID, in: model.configuration)
    }

    private var kind: GestureKind { draft.trigger.kinds.first ?? .oneFingerTap }

    private var isDirty: Bool {
        guard let baseline else { return true }
        return baseline != draft
    }

    private var boundKinds: Set<GestureKind> {
        var result = Set<GestureKind>()
        for binding in GestureUI.profile(profileID, in: model.configuration)?.bindings ?? [] {
            if case .single(let kind) = binding.trigger { result.insert(kind) }
        }
        return result
    }

    public var body: some View {
        MFPage("Gesture Studio", subtitle: "Design, tune and test one gesture at a time.") {
            HStack(alignment: .top, spacing: 16) {
                GestureStudioKindList(selection: kind, boundKinds: boundKinds, onSelect: { newKind in select(newKind) })
                    .frame(width: 250)
                editorColumn
            }
        }
        .onAppear { load(navigation.selectedGesture ?? kind) }
        .onChange(of: navigation.selectedGesture) { _, newValue in
            // Retargeting sets the selection to the draft's own kind; only reload for a real change.
            if let newValue, newValue != kind { load(newValue) }
        }
        .onChange(of: navigation.editingProfileID) { _, _ in scopeChanged() }
    }

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            GestureStudioPreviewCard(kind: kind)
            GestureStudioFamilyCard(kind: kind, onRetarget: { newKind in retarget(to: newKind) })
            actionCard
            GestureStudioTuningCard(draft: $draft, kind: kind)
            GestureStudioScopeCard(draft: $draft)
            conflictCard
            GestureStudioTestPanel(kind: kind)
            saveBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var actionCard: some View {
        MFCard("Action", systemImage: "bolt") {
            ActionEditor(action: $draft.action)
            if draft.action == .none {
                Label("No action assigned: the gesture would be recognized but do nothing.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Conflicts the draft would cause, shown before anything is saved.
    @ViewBuilder private var conflictCard: some View {
        let conflicts: [BindingConflict] = model.conflicts(adding: draft, toProfile: profileID)
        if conflicts.isEmpty {
            MFCard("Conflicts", systemImage: "checkmark.shield") {
                Text("No conflicts with the other bindings of this profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            MFCard("Conflicts", systemImage: "exclamationmark.triangle") {
                GestureConflictList(conflicts: conflicts)
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            if baseline == nil {
                MFStatusBadge("New binding — not saved", style: .info)
            } else if isDirty {
                MFStatusBadge("Unsaved changes", style: .warning)
            } else {
                MFStatusBadge("Saved", style: .good)
            }
            Spacer()
            if baseline != nil {
                Button("Remove Binding", role: .destructive) { removeBinding() }
            }
            Button("Revert") { revert() }
                .disabled(baseline != nil && !isDirty)
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
        }
    }

    // MARK: Draft management

    private func existingBinding(for kind: GestureKind) -> GestureBinding? {
        GestureUI.profile(profileID, in: model.configuration)?.bindings.first { $0.trigger == .single(kind) }
    }

    private func load(_ kind: GestureKind) {
        if let existing = existingBinding(for: kind) {
            draft = existing
            baseline = existing
        } else {
            draft = GestureBinding(trigger: .single(kind), action: .none)
            baseline = nil
        }
        if navigation.selectedGesture != kind { navigation.selectedGesture = kind }
    }

    private func select(_ newKind: GestureKind) {
        guard newKind != kind else { return }
        load(newKind)
    }

    /// Keeps action and tuning, changes which gesture the binding listens for.
    private func retarget(to newKind: GestureKind) {
        guard newKind != kind else { return }
        draft.trigger = .single(newKind)
        navigation.selectedGesture = newKind
    }

    /// Another profile was chosen: load its binding for this gesture, or carry the draft over
    /// as a new binding for that profile.
    private func scopeChanged() {
        if let existing = existingBinding(for: kind) {
            draft = existing
            baseline = existing
        } else {
            draft.id = UUID()
            baseline = nil
        }
    }

    private func save() {
        let binding: GestureBinding = draft
        let profileID: UUID = self.profileID
        model.update { configuration in
            GestureUI.upsert(binding, inProfile: profileID, configuration: &configuration)
        }
        baseline = binding
    }

    private func revert() {
        if let baseline {
            draft = baseline
            if let savedKind = baseline.trigger.kinds.first { navigation.selectedGesture = savedKind }
        } else {
            draft = GestureBinding(trigger: .single(kind), action: .none)
        }
    }

    private func removeBinding() {
        guard let baseline else { return }
        let profileID: UUID = self.profileID
        model.update { configuration in
            GestureUI.removeBinding(baseline.id, fromProfile: profileID, configuration: &configuration)
        }
        load(kind)
    }
}
