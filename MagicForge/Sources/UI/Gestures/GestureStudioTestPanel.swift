import SwiftUI
import MFCore
import MFEngine
import MFGestures
import MFUtilities

/// "Test gesture": shows what the recognizer reports while bound actions are suppressed.
@MainActor
struct GestureStudioTestPanel: View {
    let kind: GestureKind

    @Environment(AppModel.self) private var model
    @State private var session = GestureTestSession()

    var body: some View {
        MFCard("Test Gesture", systemImage: "play.circle") {
            Text("While testing, gestures are recognized and listed here but their actions do not run.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            recognitionNote
            controls
            if let notice = session.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            latestResult
            attemptList
        }
        .onAppear { session.expected = kind }
        .onChange(of: kind) { _, newValue in
            session.expected = newValue
            session.clear()
        }
        .onDisappear { session.stop(model: model) }
    }

    /// The recognizer only emits gestures that are bound and enabled in the active profile.
    @ViewBuilder private var recognitionNote: some View {
        let isBoundNow: Bool = model.effectiveBindings.contains { $0.trigger.kinds.contains(kind) }
        if !isBoundNow {
            Label("This gesture is not enabled in the active profile, so the recognizer will not report it. "
                + "Save an enabled binding first.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(session.isListening ? "Stop Testing" : "Start Testing") {
                if session.isListening {
                    session.stop(model: model)
                } else {
                    session.start(model: model)
                }
            }
            Button {
                playSynthetic()
            } label: {
                Label("Play Synthetic", systemImage: "waveform.path")
            }
            .disabled(kind.category == .fallback)
            .help(kind.category == .fallback
                ? "Fallback triggers come from the keyboard and mouse buttons; there is no synthetic touch input for them."
                : "Feed generated (not real) touch frames for this gesture through the recognizer")
            if model.isSyntheticInputActive {
                Button("Stop Synthetic") { model.stopSynthetic() }
            }
            Spacer()
            Button("Clear") { session.clear() }
                .disabled(session.attempts.isEmpty)
            if session.isListening {
                MFStatusBadge("Listening — actions suppressed", style: .info)
            }
        }
    }

    @ViewBuilder private var latestResult: some View {
        if let latest = session.attempts.first {
            HStack(spacing: 8) {
                Image(systemName: latest.matchesExpected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(latest.matchesExpected ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                Text(latest.matchesExpected ? "Recognized \(latest.event.kind.displayName)"
                    : "Recognized \(latest.event.kind.displayName), not \(kind.displayName)")
                    .font(.headline)
                if latest.isSynthetic { MFStatusBadge("SYNTHETIC", style: .warning) }
            }
            ProgressView(value: min(max(latest.event.confidence, 0), 1)) {
                Text("Confidence \(Self.percent(latest.event.confidence))")
                    .font(.caption)
            }
        } else if session.isListening {
            Text("Waiting for a gesture…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var attemptList: some View {
        if session.attempts.count > 1 {
            Divider()
            Text("Recent attempts")
                .font(.subheadline.weight(.semibold))
            ForEach(session.attempts) { attempt in
                HStack(spacing: 8) {
                    Image(systemName: attempt.matchesExpected ? "checkmark" : "xmark")
                        .foregroundStyle(attempt.matchesExpected ? Color.green : Color.orange)
                        .frame(width: 14)
                        .accessibilityLabel(Text(attempt.matchesExpected ? "Match" : "No match"))
                    Text(attempt.event.kind.displayName)
                    if attempt.isSynthetic {
                        Text("synthetic")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(Self.percent(attempt.event.confidence))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(attempt.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
    }

    private func playSynthetic() {
        let frames: [TouchFrame] = SyntheticTouch.frames(for: kind, startTime: MonotonicClock.now())
        guard let first = frames.first, let last = frames.last else {
            session.notice = "There is no synthetic recording for this gesture."
            return
        }
        session.notice = "Synthetic input: generated frames, not your fingers."
        session.start(model: model)
        session.expectSynthetic(for: (last.timestamp - first.timestamp) + 1.5)
        model.playSynthetic(frames, realtime: true)
    }
}
