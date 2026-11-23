import SwiftUI
import MFCore
import MFEngine

/// Step 2: animated preview, how-to and availability.
@MainActor
struct GestureStudioPreviewCard: View {
    let kind: GestureKind
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard(kind.displayName, systemImage: kind.symbolName) {
            HStack(alignment: .top, spacing: 16) {
                GesturePreview(kind: kind, isAnimating: true)
                    .frame(height: 190)
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.summary)
                        .fixedSize(horizontal: false, vertical: true)
                    GestureAvailabilityBadge(trigger: .single(kind))
                    if case .unavailable(let reason) = model.availability(of: kind) {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if kind.overlapsNativeScrolling {
                        Label("One-finger motion is native scrolling: with this gesture enabled, every scroll in that "
                            + "direction also runs the action.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Switches the draft to the same movement with another finger count or direction.
@MainActor
struct GestureStudioFamilyCard: View {
    let kind: GestureKind
    let onRetarget: (GestureKind) -> Void

    var body: some View {
        let fingerVariants: [GestureKind] = GestureFamily.fingerVariants(of: kind)
        let siblings: [GestureKind] = GestureFamily.variantSiblings(of: kind)
        if fingerVariants.count > 1 || siblings.count > 1 {
            MFCard("Variant", systemImage: "hand.raised.fingers.spread") {
                if fingerVariants.count > 1 {
                    Picker("Fingers", selection: selection) {
                        ForEach(fingerVariants, id: \.self) { variant in
                            Text("\(GestureDescriptor(variant).fingers)").tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                if siblings.count > 1 {
                    Picker("Direction", selection: selection) {
                        ForEach(siblings, id: \.self) { sibling in
                            Text(GestureDescriptor(sibling).variantLabel).tag(sibling)
                        }
                    }
                    .frame(maxWidth: 260)
                }
                Text("Switching keeps the action and tuning and moves this binding to the chosen gesture when you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selection: Binding<GestureKind> {
        let kind: GestureKind = self.kind
        let onRetarget: (GestureKind) -> Void = self.onRetarget
        return Binding<GestureKind>(get: { kind }, set: { newValue in onRetarget(newValue) })
    }
}

/// Step 4a: sensitivity, duration and priority of the draft.
@MainActor
struct GestureStudioTuningCard: View {
    @Binding var draft: GestureBinding
    let kind: GestureKind
    @Environment(AppModel.self) private var model

    private var role: GestureDescriptor.DurationRole { GestureDescriptor(kind).durationRole }

    var body: some View {
        MFCard("Tuning", systemImage: "slider.horizontal.3") {
            sensitivityRow
            if role != .none { durationRows }
            Stepper(value: $draft.priority, in: -10...10) {
                Text("Priority: \(draft.priority)")
            }
            .help("When two enabled bindings share a trigger, the higher priority wins")
            Button("Reset Tuning to Defaults") {
                draft.sensitivity = 0.5
                draft.duration = nil
                draft.priority = 0
            }
            .disabled(draft.sensitivity == 0.5 && draft.duration == nil && draft.priority == 0)
        }
    }

    private var sensitivityRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: $draft.sensitivity, in: 0...1) {
                Text("Sensitivity")
            } minimumValueLabel: {
                Text("Deliberate").font(.caption)
            } maximumValueLabel: {
                Text("Sensitive").font(.caption)
            }
            Text("\(Int((draft.sensitivity * 100).rounded())) % — higher needs less movement; 50 % is the default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var durationRange: ClosedRange<Double> {
        role == .hold ? 0.2...2.0 : 0.08...0.6
    }

    private var defaultDuration: Double {
        let recognizer: RecognizerConfig = model.configuration.recognizer
        let value: Double = role == .hold ? recognizer.holdMinDuration : recognizer.tapMaxDuration
        return min(max(value, durationRange.lowerBound), durationRange.upperBound)
    }

    @ViewBuilder private var durationRows: some View {
        Toggle(role == .hold ? "Custom hold time" : "Custom maximum tap time", isOn: hasCustomDuration)
        if draft.duration != nil {
            Slider(value: durationValue, in: durationRange) {
                Text(role == .hold ? "Hold for at least" : "Tap no longer than")
            }
            Text(String(format: "%.2f s", draft.duration ?? defaultDuration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text(String(format: "Using the recognizer default (%.2f s).", defaultDuration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hasCustomDuration: Binding<Bool> {
        Binding<Bool>(
            get: { draft.duration != nil },
            set: { isOn in draft.duration = isOn ? defaultDuration : nil }
        )
    }

    private var durationValue: Binding<Double> {
        Binding<Double>(
            get: { draft.duration ?? defaultDuration },
            set: { newValue in draft.duration = newValue }
        )
    }
}

/// Step 4b: which profile the binding belongs to, enabled state and note.
@MainActor
struct GestureStudioScopeCard: View {
    @Binding var draft: GestureBinding

    var body: some View {
        MFCard("Scope", systemImage: "square.stack.3d.up") {
            GestureProfileScopePicker(title: "Applies to")
            Text("The global profile applies everywhere; an app profile only while one of its apps is frontmost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Enabled", isOn: $draft.isEnabled)
            TextField("Note", text: $draft.note, prompt: Text("Optional note"))
                .textFieldStyle(.roundedBorder)
        }
    }
}
