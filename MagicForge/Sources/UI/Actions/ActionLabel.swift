import SwiftUI
import MFCore
import MFEngine

/// Icon + name of an action, followed by a short parameter summary (shortcut, app, script line…).
@MainActor
public struct ActionLabel: View {
    private let action: Action
    private let showsSummary: Bool
    @Environment(AppModel.self) private var model

    public init(action: Action, showsSummary: Bool = true) {
        self.action = action
        self.showsSummary = showsSummary
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            if let summary = summary {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        ActionText.title(for: action) { bundleID in ActionAppNames.displayName(for: bundleID) }
    }

    private var symbolName: String {
        action.symbolName
    }

    private var summary: String? {
        guard showsSummary else { return nil }
        return ActionText.parameterSummary(for: action, in: model.configuration)
    }
}
