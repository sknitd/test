import SwiftUI
import MFCore
import MFEngine
import MFUtilities

/// Guided calibration: tap five times, swipe in each direction, rest the hand. Opened from the
/// Touch Lab. Needs a connected mouse whose adapter delivers raw contacts.
@MainActor
public struct CalibrationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session = CalibrationSession()

    public init() {}

    private var device: DeviceInfo? { model.connectedDevice }

    /// nil when calibration can run, else why it cannot.
    private var unavailableReason: String? {
        guard device != nil else { return "No Magic Mouse is connected." }
        let status: AdapterStatus = model.adapterStatus
        switch status.state {
        case .unavailable(let reason):
            return "Live finger data is unavailable: \(reason)"
        case .stopped:
            return "The input adapter is stopped, so no finger data arrives."
        case .running:
            return status.capabilities.rawContacts ? nil
                : "The active input adapter does not report per-finger positions."
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if let reason = unavailableReason {
                MFEmptyState(systemImage: "hand.raised.slash", title: "Calibration is unavailable", message: reason)
            } else if let device {
                CalibrationStepView(session: session, device: device, onStart: { start(device) })
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 420)
        .task { await pollFeed() }
        .onDisappear { session.end(model: model) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calibrate Touch Surface")
                .font(.title3.weight(.semibold))
            if let device {
                Text("\(device.name) — \(device.model.displayName)")
                    .foregroundStyle(.secondary)
                Text(calibrationStatus(for: device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calibrationStatus(for device: DeviceInfo) -> String {
        if let date = model.configuration.calibrations[device.id]?.calibratedAt {
            return "Last calibrated \(date.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Not calibrated yet; built-in defaults are in use."
    }

    private var footer: some View {
        HStack {
            if let device {
                Button("Reset Calibration") { reset(device) }
                    .disabled(model.configuration.calibrations[device.id] == nil)
                    .help("Go back to the built-in defaults for this mouse")
            }
            Spacer()
            Button(session.step == .review ? "Discard" : "Close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if let device, session.step == .review, unavailableReason == nil {
                Button("Save Calibration") { save(device) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.taps.isEmpty && session.swipes.isEmpty)
            }
        }
    }

    private func start(_ device: DeviceInfo) {
        session.begin(model: model, surface: device.surface, now: MonotonicClock.now())
    }

    private func save(_ device: DeviceInfo) {
        let calibration: DeviceCalibration = session.result(base: model.calibration(forDevice: device.id))
        model.setCalibration(calibration, forDevice: device.id)
        dismiss()
    }

    private func reset(_ device: DeviceInfo) {
        var defaults = DeviceCalibration()
        defaults.surface = device.surface
        model.setCalibration(defaults, forDevice: device.id)
    }

    private func pollFeed() async {
        let feed: TouchFeed = model.touchFeed
        while !Task.isCancelled {
            session.poll(feed.snapshot(), now: MonotonicClock.now())
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
    }
}

/// The body of the sheet for the current step.
@MainActor
private struct CalibrationStepView: View {
    let session: CalibrationSession
    let device: DeviceInfo
    let onStart: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.step {
            case .intro: intro
            case .taps: taps
            case .swipes: swipes
            case .rest: rest
            case .review: review
            }
            if session.step != .intro && session.step != .review { liveNotes }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calibration measures how you tap and swipe on this mouse so the recognizer's thresholds fit you.")
                .fixedSize(horizontal: false, vertical: true)
            Label("Tap the surface \(CalibrationMath.requiredTaps) times with one finger", systemImage: "1.circle")
            Label("Swipe up, down, left and right once each", systemImage: "2.circle")
            Label("Rest your hand on the mouse for a few seconds", systemImage: "3.circle")
            Text("While calibrating, gestures do not run their actions. Each saved value is the median of your samples.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start", action: onStart)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var taps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 1 of 3 — Tap")
                .font(.headline)
            Text("Tap the surface lightly with one finger, the way you normally would. Do not press the button.")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(session.taps.count), total: Double(CalibrationMath.requiredTaps)) {
                Text("\(session.taps.count) of \(CalibrationMath.requiredTaps) taps")
            }
        }
    }

    private var swipes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 2 of 3 — Swipe")
                .font(.headline)
            if let expected = session.expectedSwipe {
                Label("Swipe \(expected.rawValue) with one finger", systemImage: Self.arrowSymbol(for: expected))
                    .font(.title3)
            }
            Text("“Up” is toward the front of the mouse, away from your palm.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(session.swipes.count), total: Double(CalibrationMath.swipeOrder.count)) {
                Text("\(session.swipes.count) of \(CalibrationMath.swipeOrder.count) swipes")
            }
        }
    }

    private var rest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 3 of 3 — Rest")
                .font(.headline)
            Text("Rest your hand on the mouse as you do between gestures and keep it still.")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: min(session.restElapsed, CalibrationSession.restSeconds),
                         total: CalibrationSession.restSeconds) {
                Text(String(format: "%.1f of %.0f s", min(session.restElapsed, CalibrationSession.restSeconds),
                            CalibrationSession.restSeconds))
            }
            Text("This step only reports what the sensor sees while resting; it does not change the saved calibration.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Skip This Step") { session.skipRest(now: MonotonicClock.now()) }
        }
    }

    private var review: some View {
        let current: DeviceCalibration = model.calibration(forDevice: device.id)
        let measured: DeviceCalibration = session.result(base: current)
        let hasSizes: Bool = !session.taps.compactMap(\.size).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text("Measured Values")
                .font(.headline)
            Text("Medians of \(session.taps.count) taps and \(session.swipes.count) swipes. Current values in parentheses.")
                .font(.callout)
                .foregroundStyle(.secondary)
            MFKeyValueRow("Typical tap duration", value: String(format: "%.0f ms (%.0f ms)",
                                                                measured.typicalTapDuration * 1000,
                                                                current.typicalTapDuration * 1000))
            MFKeyValueRow("Typical tap movement", value: String(format: "%.2f mm (%.2f mm)",
                                                                measured.typicalTapMovementMM,
                                                                current.typicalTapMovementMM))
            MFKeyValueRow("Typical tap contact size", value: hasSizes
                ? String(format: "%.2f (%.2f)", measured.typicalTapSize, current.typicalTapSize)
                : String(format: "not reported by the sensor — keeping %.2f", current.typicalTapSize))
            MFKeyValueRow("Typical swipe distance", value: String(format: "%.1f mm (%.1f mm)",
                                                                  measured.typicalSwipeDistanceMM,
                                                                  current.typicalSwipeDistanceMM))
            Divider()
            MFKeyValueRow("Resting contacts seen (not saved)", value: "\(session.restMaxContacts)")
            MFKeyValueRow("Largest resting contact size (not saved)", value: restSizeText)
        }
    }

    private var restSizeText: String {
        guard let size = session.restMaxSize else { return "—" }
        return String(format: "%.2f (palm threshold %.2f)", size, model.configuration.recognizer.palmSizeThreshold)
    }

    @ViewBuilder private var liveNotes: some View {
        if let feedback = session.feedback {
            Text(feedback)
                .font(.callout)
        }
        if let recognized = session.lastRecognized {
            Text("Recognizer reported: \(recognized.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if session.sawSyntheticInput {
            Label("Synthetic input is playing and is ignored: calibration only measures real fingers.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private static func arrowSymbol(for direction: GestureKind.Direction) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}
