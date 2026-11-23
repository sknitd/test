import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MFCore
import MFEngine
import MFGestures
import MFUtilities

/// Menu that feeds generated touch frames through the real recognition pipeline.
@MainActor
struct TouchLabSyntheticMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var notice: String?

    var body: some View {
        Menu {
            Button("Demo Reel") { play(SyntheticTouch.demoReel(startTime: MonotonicClock.now()), name: "the demo reel") }
            Divider()
            ForEach(GestureKind.Category.allCases.filter { $0 != .fallback }, id: \.self) { category in
                Menu(category.displayName) {
                    ForEach(GestureKind.allCases.filter { $0.category == category }, id: \.self) { kind in
                        Button(kind.displayName) {
                            play(SyntheticTouch.frames(for: kind, startTime: MonotonicClock.now()), name: kind.displayName)
                        }
                    }
                }
            }
        } label: {
            Label("Synthetic Input", systemImage: "waveform.path")
        }
        .fixedSize()
        .help("Play generated touch frames (not real fingers) through the recognizer")
    }

    private func play(_ frames: [TouchFrame], name: String) {
        guard !frames.isEmpty else {
            notice = "There is no synthetic recording for \(name)."
            return
        }
        // Playback into a paused feed would show nothing.
        if model.touchFeed.isPaused {
            notice = "Synthetic input was not played because the Touch Lab is paused. Switch to Live first."
            return
        }
        notice = "Playing synthetic input for \(name). Recognized gestures run their bound actions."
        model.playSynthetic(frames, realtime: true)
    }
}

/// Popover content: explicit choice whether finger coordinates go into the exported report.
@MainActor
struct TouchLabExportPanel: View {
    @Environment(AppModel.self) private var model
    @State private var includeTouchFrames: Bool = false
    @State private var resultMessage: String?
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Diagnostics")
                .font(.headline)
            Text("A JSON report with versions, adapter and capabilities, metrics, permissions and recent gesture kinds.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Include touch frames (finger coordinates)", isOn: $includeTouchFrames)
            Text("Off by default. Finger coordinates are only written when this is checked.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
            }
            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let failureMessage {
                Label(failureMessage, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func export() {
        resultMessage = nil
        failureMessage = nil
        let data: Data = model.diagnosticsReport(includeTouchFrames: includeTouchFrames)
        guard !data.isEmpty else {
            failureMessage = "The engine returned an empty report; nothing was written."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "MagicForge-Diagnostics.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            resultMessage = "Saved \(url.lastPathComponent)."
        } catch {
            failureMessage = "Could not save the report: \(error.localizedDescription)"
        }
    }
}
