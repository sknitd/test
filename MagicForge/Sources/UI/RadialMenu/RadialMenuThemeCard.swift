import SwiftUI
import MFCore
import MFEngine

/// Diameter, accent colour and visibility options of a radial menu.
@MainActor
struct RadialMenuThemeCard: View {
    let menu: RadialMenu
    @Environment(AppModel.self) private var model

    private func themeBinding<Value>(_ keyPath: WritableKeyPath<RadialMenuTheme, Value>, fallback: Value) -> Binding<Value> {
        let id: UUID = menu.id
        return Binding<Value>(
            get: { RadialMenuEditing.menu(id, in: model)?.theme[keyPath: keyPath] ?? fallback },
            set: { newValue in
                RadialMenuEditing.update(id, in: model) { edited in
                    edited.theme[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var accentColor: Binding<Color> {
        let id: UUID = menu.id
        return Binding<Color>(
            get: {
                let theme: RadialMenuTheme = RadialMenuEditing.menu(id, in: model)?.theme ?? RadialMenuTheme()
                return RadialThemeColor.accent(for: theme)
            },
            set: { newValue in
                guard let hex = RadialThemeColor.hex(from: newValue) else { return }
                RadialMenuEditing.update(id, in: model) { edited in
                    edited.theme.accentHex = hex
                }
            }
        )
    }

    private var hexProblem: String? {
        let text: String = menu.theme.accentHex.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        return Color(hex: text) == nil ? "Not a valid hex colour (use #RRGGBB). The system accent colour is used instead." : nil
    }

    var body: some View {
        MFCard("Appearance", systemImage: "paintpalette") {
            VStack(alignment: .leading, spacing: 10) {
                diameterRow
                accentRow
                Toggle("Show labels under the icons", isOn: themeBinding(\.showLabels, fallback: true))
                Toggle("Show recently used items under the ring", isOn: themeBinding(\.showRecentActions, fallback: true))
            }
        }
    }

    private var diameterRow: some View {
        HStack(spacing: 8) {
            Slider(value: themeBinding(\.diameter, fallback: 280),
                   in: Double(RadialOverlayLayout.minimumDiameter)...Double(RadialOverlayLayout.maximumDiameter),
                   step: 10,
                   label: { Text("Diameter") })
            Text("\(Int(menu.theme.diameter)) pt")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ColorPicker("Accent colour", selection: accentColor, supportsOpacity: false)
                    .fixedSize()
                TextField("Hex", text: themeBinding(\.accentHex, fallback: ""), prompt: Text("#0A84FF"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 110)
                    .labelsHidden()
                    .accessibilityLabel(Text("Accent colour as hex"))
                Button("Use System Accent") {
                    RadialMenuEditing.update(menu.id, in: model) { edited in
                        edited.theme.accentHex = ""
                    }
                }
                .disabled(menu.theme.accentHex.isEmpty)
            }
            if let problem = hexProblem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }
}
