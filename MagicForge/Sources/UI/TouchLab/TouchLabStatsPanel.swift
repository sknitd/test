import SwiftUI
import MFCore
import MFEngine

/// Side panel of the Touch Lab. Rebuilt a few times per second from a feed snapshot; every
/// number is a measured value from the snapshot, "—" when there is nothing to report.
@MainActor
struct TouchLabStatsPanel: View {
    let snapshot: TouchFeed.Snapshot
    /// Monotonic "now" used to tell whether the newest frame is recent.
    let now: TimeInterval
    let isPaused: Bool

    @Environment(AppModel.self) private var model

    private var hasFrames: Bool { snapshot.totalFrames > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            contactsCard
            recognizerCard
            timingCard
            adapterCard
        }
    }

    private var contactsCard: some View {
        MFCard("Contacts", systemImage: "hand.point.up.left") {
            if snapshot.isSynthetic && hasFrames {
                MFStatusBadge("SYNTHETIC INPUT", style: .warning)
            }
            if isPaused {
                MFStatusBadge("Paused", style: .neutral)
            }
            MFKeyValueRow("Touching", value: hasFrames ? "\(snapshot.latest?.touching.count ?? 0)" : "—")
            MFKeyValueRow("Counted for gestures", value: hasFrames ? "\(snapshot.live.activeFingerCount)" : "—")
            MFKeyValueRow("Resting", value: hasFrames ? "\(snapshot.live.restingFingerCount)" : "—")
        }
    }

    private var recognizerCard: some View {
        MFCard("Recognizer", systemImage: "waveform.path.ecg") {
            MFKeyValueRow("Phase", value: hasFrames ? snapshot.live.phase : "—")
            MFKeyValueRow("Candidate", value: snapshot.live.candidate?.displayName ?? "—")
            ProgressView(value: min(max(snapshot.live.candidate == nil ? 0 : snapshot.live.candidateConfidence, 0), 1)) {
                Text("Candidate confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MFKeyValueRow("Last gesture", value: lastGestureText)
        }
    }

    private var lastGestureText: String {
        guard let gesture = snapshot.lastGesture else { return "—" }
        let percent: Int = Int((min(max(gesture.confidence, 0), 1) * 100).rounded())
        return "\(gesture.kind.displayName) (\(percent) %)"
    }

    private var timingCard: some View {
        MFCard("Timing", systemImage: "speedometer") {
            MFKeyValueRow("Frame rate", value: frameRateText)
            MFKeyValueRow("Delivery latency", value: latencyText)
            MFKeyValueRow("Processing time", value: hasFrames ? Self.milliseconds(snapshot.lastProcessingTime) : "—")
            MFKeyValueRow("Frames received", value: hasFrames ? "\(snapshot.totalFrames)" : "—")
        }
    }

    /// The feed's rate is "frames in the second before the newest frame"; once frames stop
    /// arriving that number is history, so it is reported as idle.
    private var frameRateText: String {
        guard hasFrames, let latest = snapshot.latest else { return "—" }
        if !isPaused && now - latest.timestamp > 1.0 { return "0 Hz (idle)" }
        return String(format: "%.0f Hz", snapshot.framesPerSecond)
    }

    private var latencyText: String {
        guard hasFrames else { return "—" }
        // The feed does not measure delivery latency for synthetic frames.
        if snapshot.isSynthetic { return "— (synthetic)" }
        return Self.milliseconds(snapshot.lastDeliveryLatency)
    }

    private static func milliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2f ms", seconds * 1000)
    }

    private var adapterCard: some View {
        let status: AdapterStatus = model.adapterStatus
        return MFCard("Input Adapter", systemImage: "cable.connector") {
            MFKeyValueRow("Adapter", value: status.displayName)
            HStack {
                Text("State")
                Spacer()
                TouchLabAdapterStateBadge(state: status.state)
            }
            MFKeyValueRow("Raw contacts", value: status.capabilities.rawContacts
                ? "Yes (up to \(status.capabilities.maxContacts))" : "No")
            MFKeyValueRow("Contact size", value: status.capabilities.contactSize ? "Yes" : "No")
            MFKeyValueRow("Private API", value: status.usesPrivateAPI ? "Yes" : "No")
        }
    }
}

struct TouchLabAdapterStateBadge: View {
    let state: AdapterStatus.State

    var body: some View {
        switch state {
        case .running: MFStatusBadge("Running", style: .good)
        case .stopped: MFStatusBadge("Stopped", style: .neutral)
        case .unavailable: MFStatusBadge("Unavailable", style: .bad)
        }
    }
}
