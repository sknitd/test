import SwiftUI
import MFCore
import MFEngine

/// Full editor for one action: category → action → parameters, with availability and a test button.
///
/// The binding is the single source of truth. The only private state is the category the user
/// picked while the action is still `.none` (for example "Keyboard" before a shortcut is recorded).
@MainActor
public struct ActionEditor: View {
    @Binding private var action: Action
    private let allowsWorkflows: Bool
    private let showsRunButton: Bool
    @Environment(AppModel.self) private var model
    @State private var pendingCategory: ActionCategory?

    /// - Parameters:
    ///   - allowsWorkflows: pass false inside the workflow builder (workflows cannot be nested).
    ///   - showsRunButton: pass false to hide the "Run Now" test row.
    public init(action: Binding<Action>, allowsWorkflows: Bool = true, showsRunButton: Bool = true) {
        self._action = action
        self.allowsWorkflows = allowsWorkflows
        self.showsRunButton = showsRunButton
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categoryPicker
            ActionParameterSection(action: $action, category: displayedCategory, keyCombo: keyComboBinding)
            ActionAvailabilityRow(action: action)
            if showsRunButton {
                ActionRunRow(action: action)
            }
        }
    }

    private var categories: [ActionCategory] {
        ActionCategory.allCases.filter { category in allowsWorkflows || category != .workflow }
    }

    private var displayedCategory: ActionCategory? {
        action == .none ? pendingCategory : action.category
    }

    private var categoryPicker: some View {
        Picker("Category", selection: categoryBinding) {
            Text("No Action").tag(ActionCategory?.none)
            Divider()
            ForEach(categories) { category in
                Label(category.displayName, systemImage: category.symbolName)
                    .tag(ActionCategory?.some(category))
            }
        }
        .pickerStyle(.menu)
    }

    private var categoryBinding: Binding<ActionCategory?> {
        Binding<ActionCategory?>(
            get: { displayedCategory },
            set: { newValue in select(newValue) }
        )
    }

    private func select(_ category: ActionCategory?) {
        guard let category = category else {
            pendingCategory = nil
            action = .none
            return
        }
        if action != .none && action.category == category { return }
        if let fresh = ActionDefaults.action(for: category, in: model.configuration) {
            pendingCategory = nil
            action = fresh
        } else {
            pendingCategory = category
            action = .none
        }
    }

    private var keyComboBinding: Binding<KeyCombo?> {
        Binding<KeyCombo?>(
            get: {
                if case .keyboard(let combo) = action { return combo }
                return nil
            },
            set: { newValue in
                if let combo = newValue {
                    pendingCategory = nil
                    action = .keyboard(combo)
                } else {
                    pendingCategory = .keyboard
                    action = .none
                }
            }
        )
    }
}

/// Chooses the parameter editor for the displayed category.
@MainActor
struct ActionParameterSection: View {
    @Binding var action: Action
    let category: ActionCategory?
    let keyCombo: Binding<KeyCombo?>

    var body: some View {
        if let category = category {
            editor(for: category)
        } else {
            Text("Nothing happens when this is triggered.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func editor(for category: ActionCategory) -> some View {
        switch category {
        case .system: ActionSystemEditor(action: $action)
        case .window: ActionWindowEditor(action: $action)
        case .app: ActionAppEditor(action: $action)
        case .keyboard: ActionKeyboardEditor(combo: keyCombo)
        case .mouse: ActionMouseEditor(action: $action)
        case .text: ActionTextEditor(action: $action)
        case .script: ActionScriptEditor(action: $action)
        case .workflow: ActionWorkflowPicker(action: $action)
        case .radialMenu: ActionRadialMenuPicker(action: $action)
        case .ai: ActionAITemplatePicker(action: $action)
        case .control: ActionControlEditor(action: $action)
        default: EmptyView()
        }
    }
}

/// Shows why an action cannot run right now (missing permission / unsupported), if anything.
@MainActor
struct ActionAvailabilityRow: View {
    let action: Action
    @Environment(AppModel.self) private var model

    var body: some View {
        if action != .none {
            content(for: model.availability(of: action))
        }
    }

    @ViewBuilder
    private func content(for availability: ActionAvailability) -> some View {
        switch availability {
        case .available:
            EmptyView()
        case .needsPermission(let kind):
            HStack(spacing: 8) {
                MFStatusBadge("Needs \(kind.displayName)", style: .warning)
                Button("Request…") { model.requestPermission(kind) }
                    .controlSize(.small)
                Button("Open System Settings") { model.openPermissionSettings(kind) }
                    .controlSize(.small)
            }
        case .unavailable(let reason):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MFStatusBadge("Unavailable", style: .bad)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum ActionRunStatus: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
}

/// "Run Now" test button with the result of the last run.
@MainActor
struct ActionRunRow: View {
    let action: Action
    @Environment(AppModel.self) private var model
    @State private var status: ActionRunStatus = .idle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: { run() }) {
                Label("Run Now", systemImage: "play.fill")
            }
            .disabled(action == .none || status == .running)
            .help("Runs this action once, exactly as a gesture would")
            statusView
            Spacer(minLength: 0)
        }
        .onChange(of: action) {
            status = .idle
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Label("Ran successfully", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func run() {
        let target: Action = action
        status = .running
        Task {
            let result: Result<Void, ActionError> = await model.run(target, source: .manualTest)
            switch result {
            case .success: status = .succeeded
            case .failure(let error): status = .failed(ActionText.describe(error))
            }
        }
    }
}
