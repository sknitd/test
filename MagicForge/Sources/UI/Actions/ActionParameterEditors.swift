import SwiftUI
import MFCore
import MFEngine

// Parameter editors for the leaf action categories. Each one reads its payload from the shared
// `Binding<Action>` and writes a complete new action back.

@MainActor
struct ActionSystemEditor: View {
    @Binding var action: Action

    private var selection: Binding<SystemAction> {
        Binding<SystemAction>(
            get: {
                if case .system(let value) = action { return value }
                return SystemAction.missionControl
            },
            set: { newValue in action = .system(newValue) }
        )
    }

    var body: some View {
        Picker("Action", selection: selection) {
            ForEach(SystemAction.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
    }
}

@MainActor
struct ActionWindowEditor: View {
    @Binding var action: Action

    private var current: WindowAction {
        if case .window(let value) = action { return value }
        return WindowAction.snapLeft
    }

    private var resizeFraction: Double {
        if case .resize(let fraction) = current { return fraction }
        return 0.1
    }

    private var choice: Binding<WindowActionChoice> {
        Binding<WindowActionChoice>(
            get: { WindowActionChoice(current) },
            set: { newValue in action = .window(newValue.action(resizeFraction: resizeFraction)) }
        )
    }

    private var percent: Binding<Double> {
        Binding<Double>(
            get: { (resizeFraction * 100).rounded() },
            set: { newValue in action = .window(.resize(byFraction: newValue / 100)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: choice) {
                ForEach(WindowActionChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if WindowActionChoice(current) == .resize {
                Stepper(value: percent, in: -50...50, step: 5) {
                    Text("Change size by \(ActionText.percentString(resizeFraction)) of the screen")
                }
                Text(resizeFraction == 0 ? "0% leaves the window unchanged." : "Positive values grow the window, negative values shrink it. It stays centred.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct ActionAppEditor: View {
    @Binding var action: Action

    private var current: AppAction {
        if case .app(let value) = action { return value }
        return AppAction.launch(bundleID: "")
    }

    private var choice: Binding<AppActionChoice> {
        Binding<AppActionChoice>(
            get: { AppActionChoice(current) },
            set: { newValue in
                if newValue != AppActionChoice(current) {
                    action = .app(newValue.action(replacing: current))
                }
            }
        )
    }

    private var bundleID: Binding<String> {
        Binding<String>(
            get: {
                switch current {
                case .launch(let id), .switchTo(let id): return id
                default: return ""
                }
            },
            set: { newValue in
                if case .switchTo = current {
                    action = .app(.switchTo(bundleID: newValue))
                } else {
                    action = .app(.launch(bundleID: newValue))
                }
            }
        )
    }

    private var urlText: Binding<String> {
        Binding<String>(
            get: {
                if case .openURL(let value) = current { return value }
                return ""
            },
            set: { newValue in action = .app(.openURL(newValue)) }
        )
    }

    private var pathText: Binding<String> {
        Binding<String>(
            get: {
                if case .openPath(let value) = current { return value }
                return ""
            },
            set: { newValue in action = .app(.openPath(newValue)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: choice) {
                ForEach(AppActionChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            parameters
        }
    }

    @ViewBuilder
    private var parameters: some View {
        switch AppActionChoice(current) {
        case .launch, .switchTo:
            ActionAppPicker(title: "App", bundleID: bundleID)
        case .openURL:
            urlField
        case .openPath:
            pathField
        case .hideFrontmost, .quitFrontmost:
            EmptyView()
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("URL", text: urlText, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
            if !ActionText.isValidURL(urlText.wrappedValue) {
                Text("Enter a complete URL including the scheme, for example https://example.com")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var pathField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Path", text: pathText, prompt: Text("~/Documents"))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let path = ActionAppNames.choosePath() {
                        action = .app(.openPath(path))
                    }
                }
            }
            if !pathExists(pathText.wrappedValue) {
                Text("Nothing exists at this path right now.")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private func pathExists(_ path: String) -> Bool {
        let expanded: String = (path as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }
}

@MainActor
struct ActionKeyboardEditor: View {
    let combo: Binding<KeyCombo?>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Shortcut")
                KeyComboRecorder(combo: combo)
            }
            Text("The shortcut is sent to the frontmost app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct ActionMouseEditor: View {
    @Binding var action: Action

    private var current: MouseAction {
        if case .mouse(let value) = action { return value }
        return MouseAction.middleClick
    }

    private var scrollDelta: (dx: Double, dy: Double) {
        if case .scroll(let dx, let dy) = current { return (dx, dy) }
        return (0, 0)
    }

    private var choice: Binding<MouseActionChoice> {
        Binding<MouseActionChoice>(
            get: { MouseActionChoice(current) },
            set: { newValue in
                if newValue != MouseActionChoice(current) {
                    action = .mouse(newValue.action)
                }
            }
        )
    }

    private var horizontal: Binding<Double> {
        Binding<Double>(
            get: { scrollDelta.dx },
            set: { newValue in action = .mouse(.scroll(dx: newValue, dy: scrollDelta.dy)) }
        )
    }

    private var vertical: Binding<Double> {
        Binding<Double>(
            get: { scrollDelta.dy },
            set: { newValue in action = .mouse(.scroll(dx: scrollDelta.dx, dy: newValue)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: choice) {
                ForEach(MouseActionChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if MouseActionChoice(current) == .scroll {
                Stepper(value: vertical, in: -50...50, step: 1) {
                    Text("Vertical: \(ActionText.numberString(scrollDelta.dy)) lines (positive = up)")
                }
                Stepper(value: horizontal, in: -50...50, step: 1) {
                    Text("Horizontal: \(ActionText.numberString(scrollDelta.dx)) lines (positive = right)")
                }
            }
        }
    }
}

@MainActor
struct ActionTextEditor: View {
    @Binding var action: Action

    private var current: TextAction {
        if case .text(let value) = action { return value }
        return TextAction.paste
    }

    private var choice: Binding<TextActionChoice> {
        Binding<TextActionChoice>(
            get: { TextActionChoice(current) },
            set: { newValue in
                if newValue != TextActionChoice(current) {
                    action = .text(newValue.action(replacing: current))
                }
            }
        )
    }

    private var fixedText: Binding<String> {
        Binding<String>(
            get: {
                switch current {
                case .copyText(let value), .pasteText(let value): return value
                default: return ""
                }
            },
            set: { newValue in
                if case .copyText = current {
                    action = .text(.copyText(newValue))
                } else {
                    action = .text(.pasteText(newValue))
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: choice) {
                ForEach(TextActionChoice.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if showsTextField {
                TextField("Text", text: fixedText, prompt: Text("Text to put on the clipboard"), axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                Text("This replaces the current clipboard contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsTextField: Bool {
        let selected: TextActionChoice = TextActionChoice(current)
        return selected == .copyText || selected == .pasteText
    }
}

@MainActor
struct ActionControlEditor: View {
    @Binding var action: Action

    private var selection: Binding<ControlAction> {
        Binding<ControlAction>(
            get: {
                if case .control(let value) = action { return value }
                return ControlAction.toggleGesturesPaused
            },
            set: { newValue in action = .control(newValue) }
        )
    }

    var body: some View {
        Picker("Action", selection: selection) {
            ForEach(ControlAction.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
    }
}
