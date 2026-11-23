import SwiftUI
import AppKit

/// SF Symbol name field with a live preview and a hint when the name does not exist on this macOS.
@MainActor
struct ActionSymbolField: View {
    let title: String
    @Binding var symbolName: String

    private var isKnownSymbol: Bool {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                TextField(title, text: $symbolName, prompt: Text("SF Symbol name, e.g. star.fill"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                    .accessibilityLabel(Text("\(title) SF Symbol name"))
                Image(systemName: isKnownSymbol ? symbolName : "questionmark.square.dashed")
                    .font(.title3)
                    .frame(width: 26, height: 22)
                    .foregroundStyle(isKnownSymbol ? Color.primary : Color.secondary)
                    .accessibilityLabel(Text(isKnownSymbol ? "Symbol preview" : "Unknown symbol"))
            }
            if !isKnownSymbol {
                Text("No SF Symbol with this name exists on this Mac. Browse names in Apple's SF Symbols app.")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
