import SwiftUI
import MFCore
import MFEngine

/// Step 1 of Gesture Studio: every gesture kind, grouped by category, with availability and
/// whether it is already bound in the edited profile.
@MainActor
struct GestureStudioKindList: View {
    let selection: GestureKind
    let boundKinds: Set<GestureKind>
    let onSelect: (GestureKind) -> Void

    var body: some View {
        MFCard("Gesture", systemImage: "hand.tap") {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(GestureKind.Category.allCases, id: \.self) { category in
                        GestureStudioKindGroup(category: category, selection: selection, boundKinds: boundKinds,
                                               onSelect: onSelect)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: 560)
        }
    }
}

@MainActor
private struct GestureStudioKindGroup: View {
    let category: GestureKind.Category
    let selection: GestureKind
    let boundKinds: Set<GestureKind>
    let onSelect: (GestureKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(category.displayName, systemImage: category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(GestureKind.allCases.filter { $0.category == category }, id: \.self) { kind in
                GestureStudioKindRow(kind: kind, isSelected: kind == selection, isBound: boundKinds.contains(kind),
                                     onSelect: onSelect)
            }
        }
    }
}

@MainActor
private struct GestureStudioKindRow: View {
    let kind: GestureKind
    let isSelected: Bool
    let isBound: Bool
    let onSelect: (GestureKind) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let reason: String? = unavailableReason
        Button {
            onSelect(kind)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(kind.displayName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isBound {
                    Image(systemName: "link")
                        .font(.caption)
                        .help("Bound in this profile")
                        .accessibilityLabel(Text("Bound in this profile"))
                }
                if reason != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.orange)
                        .accessibilityLabel(Text("Unavailable"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : (reason == nil ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(reason ?? kind.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var unavailableReason: String? {
        if case .unavailable(let reason) = model.availability(of: kind) { return reason }
        return nil
    }
}
