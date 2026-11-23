import SwiftUI
import MFCore
import MFEngine

/// Creates or edits a `GestureTrigger.sequence` binding (2–4 gestures performed back-to-back).
/// Works on a local draft; nothing is written until "Save".
@MainActor
struct GestureSequenceBuilderSheet: View {
    static let minimumSteps = 2
    static let maximumSteps = 4

    let profileID: UUID
    let isNew: Bool
    @State private var draft: GestureBinding

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(profileID: UUID, binding: GestureBinding, isNew: Bool) {
        self.profileID = profileID
        self.isNew = isNew
        _draft = State(initialValue: binding)
    }

    /// A fresh two-step sequence draft.
    static func newDraft() -> GestureBinding {
        GestureBinding(trigger: .sequence([.oneFingerTap, .twoFingerTap]), action: .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Gesture Sequence" : "Edit Gesture Sequence")
                .font(.title3.weight(.semibold))
            Text(windowExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            stepsSection
            Divider()
            Text("Action")
                .font(.headline)
            ActionEditor(action: $draft.action)
            conflictsSection
            buttons
        }
        .padding(20)
        .frame(width: 520)
    }

    private var windowExplanation: String {
        let window: String = String(format: "%.2f", model.configuration.recognizer.sequenceWindow)
        return "Pick \(Self.minimumSteps) to \(Self.maximumSteps) gestures. The action runs when they are recognized "
            + "one after another, each within \(window) s of the previous one."
    }

    private var steps: [GestureKind] { draft.trigger.kinds }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.indices), id: \.self) { index in
                stepRow(index: index)
            }
            Button {
                var kinds = steps
                kinds.append(.oneFingerTap)
                draft.trigger = .sequence(kinds)
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .disabled(steps.count >= Self.maximumSteps)
            if let reason = GestureUI.unavailableReason(for: draft.trigger, model: model) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func stepRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            Picker("Step \(index + 1)", selection: stepBinding(index)) {
                ForEach(GestureKind.Category.allCases, id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(kinds(in: category), id: \.self) { kind in
                            Text(stepTitle(kind)).tag(kind)
                        }
                    }
                }
            }
            .labelsHidden()
            Button {
                var kinds = steps
                guard kinds.indices.contains(index) else { return }
                kinds.remove(at: index)
                draft.trigger = .sequence(kinds)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(steps.count <= Self.minimumSteps)
            .accessibilityLabel(Text("Remove step \(index + 1)"))
        }
    }

    private func kinds(in category: GestureKind.Category) -> [GestureKind] {
        GestureKind.allCases.filter { $0.category == category }
    }

    private func stepTitle(_ kind: GestureKind) -> String {
        if case .unavailable = model.availability(of: kind) { return "\(kind.displayName) (unavailable)" }
        return kind.displayName
    }

    private func stepBinding(_ index: Int) -> Binding<GestureKind> {
        Binding<GestureKind>(
            get: {
                let kinds = draft.trigger.kinds
                return kinds.indices.contains(index) ? kinds[index] : .oneFingerTap
            },
            set: { newValue in
                var kinds = draft.trigger.kinds
                guard kinds.indices.contains(index) else { return }
                kinds[index] = newValue
                draft.trigger = .sequence(kinds)
            }
        )
    }

    @ViewBuilder private var conflictsSection: some View {
        let conflicts: [BindingConflict] = model.conflicts(adding: draft, toProfile: profileID)
        if !conflicts.isEmpty {
            GestureConflictList(conflicts: conflicts)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                let binding: GestureBinding = draft
                let profileID: UUID = self.profileID
                model.update { configuration in
                    GestureUI.upsert(binding, inProfile: profileID, configuration: &configuration)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(steps.count < Self.minimumSteps || steps.count > Self.maximumSteps)
        }
    }
}
