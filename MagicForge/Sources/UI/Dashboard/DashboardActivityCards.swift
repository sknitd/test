import SwiftUI
import MFCore
import MFEngine

@MainActor
struct DashboardWorkflowsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Running workflows", systemImage: "arrow.triangle.branch") {
            ForEach(model.runningWorkflows) { run in
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(run.name)
                    if !run.progress.isEmpty {
                        Text("Step \(run.progress)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(run.startedAt, style: .time)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Button("Cancel All Workflows", role: .destructive) {
                model.cancelAllWorkflows()
            }
            .controlSize(.small)
        }
    }
}

@MainActor
struct DashboardRecentGesturesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Recent gestures", systemImage: "clock.arrow.circlepath") {
            if !model.configuration.settings.keepRecentGestures {
                Text("Recent gestures are not kept. You can turn this on in Settings › Privacy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.recentGestures.isEmpty {
                Text("No gestures recognized yet. Recognized gestures are listed here and kept in memory only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.recentGestures.prefix(15))) { record in
                    DashboardGestureRow(record: record)
                    Divider()
                }
                HStack {
                    Text("Kept in memory only, never written to disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        model.clearRecentGestures()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

@MainActor
struct DashboardGestureRow: View {
    let record: GestureRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: record.event.kind.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.event.kind.displayName)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failure = record.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text("\(ShellFormat.percent(record.event.confidence)) confidence")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(record.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let action: String = record.actionName ?? "No action bound"
        return "\(action) · \(record.profileName)"
    }
}

/// Numbers measured by the engine since launch or the last reset. Nothing here is estimated.
@MainActor
struct DashboardMetricsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let metrics: EngineMetrics = model.metrics
        let hasFrames: Bool = metrics.framesProcessed > 0
        let hasActions: Bool = metrics.actionsExecuted > 0
        MFCard("Measured performance", systemImage: "speedometer") {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    MFKeyValueRow("Frames processed", value: ShellFormat.count(metrics.framesProcessed))
                    MFKeyValueRow("Gestures recognized", value: ShellFormat.count(metrics.gesturesRecognized))
                    MFKeyValueRow("Actions executed", value: ShellFormat.count(metrics.actionsExecuted))
                    MFKeyValueRow("Action failures", value: ShellFormat.count(metrics.actionFailures))
                }
                VStack(spacing: 6) {
                    MFKeyValueRow("Recognizer time per frame (average)",
                                  value: ShellFormat.milliseconds(metrics.averageProcessingTime, hasData: hasFrames))
                    MFKeyValueRow("Recognizer time per frame (maximum)",
                                  value: ShellFormat.milliseconds(metrics.maxProcessingTime, hasData: hasFrames))
                    MFKeyValueRow("Frame delivery latency (average)",
                                  value: ShellFormat.milliseconds(metrics.averageDeliveryLatency, hasData: hasFrames))
                    MFKeyValueRow("Gesture to action dispatch (average)",
                                  value: ShellFormat.milliseconds(metrics.averageDispatchLatency, hasData: hasActions))
                }
            }
            HStack {
                Text("Measured on this Mac since launch or the last reset. “—” means nothing has been measured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset") {
                    model.resetMetrics()
                }
                .controlSize(.small)
                .accessibilityLabel("Reset measurements")
            }
        }
    }
}
