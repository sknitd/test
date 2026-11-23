import SwiftUI
import MFCore
import MFEngine

/// One row of the bindings table.
@MainActor
struct GestureBindingRow: View {
    let binding: GestureBinding
    /// Conflicts that involve this binding.
    let conflicts: [BindingConflict]
    let onSetEnabled: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let reason: String? = GestureUI.unavailableReason(for: binding.trigger, model: model)
        HStack(spacing: 10) {
            enableToggle(isUnavailable: reason != nil)
            Image(systemName: GestureUI.symbolName(for: binding.trigger))
                .frame(width: 22)
                .foregroundStyle(reason == nil ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            titles(unavailableReason: reason)
            Spacer(minLength: 8)
            ActionLabel(action: binding.action)
                .lineLimit(1)
            GestureAvailabilityBadge(trigger: binding.trigger)
            conflictIndicator
            rowButtons
        }
        .padding(.vertical, 4)
        .opacity(reason == nil ? 1 : 0.75)
    }

    private func enableToggle(isUnavailable: Bool) -> some View {
        let onSetEnabled: (Bool) -> Void = self.onSetEnabled
        let isOn = Binding<Bool>(get: { binding.isEnabled }, set: { newValue in onSetEnabled(newValue) })
        // An unavailable gesture cannot be switched on; one that is already on can still be switched off.
        return Toggle("Enable \(binding.trigger.displayName)", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isUnavailable && !binding.isEnabled)
    }

    private func titles(unavailableReason: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(binding.trigger.displayName)
                .font(.body)
                .lineLimit(1)
            if let unavailableReason {
                Text(unavailableReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !binding.note.isEmpty {
                Text(binding.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var conflictIndicator: some View {
        if let severity = GestureUI.worstSeverity(conflicts) {
            let messages: String = conflicts.map(\.message).joined(separator: "\n")
            Image(systemName: GestureUI.symbolName(for: severity))
                .foregroundStyle(GestureUI.statusStyle(for: severity).color)
                .help(messages)
                .accessibilityLabel(Text("\(GestureUI.title(for: severity)): \(messages)"))
        }
    }

    private var rowButtons: some View {
        HStack(spacing: 4) {
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Edit in Gesture Studio")
            .accessibilityLabel(Text("Edit \(binding.trigger.displayName)"))
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete this binding")
            .accessibilityLabel(Text("Delete \(binding.trigger.displayName)"))
        }
        .buttonStyle(.borderless)
    }
}
