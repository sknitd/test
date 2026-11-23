import SwiftUI
import AppKit
import Combine
import MFCore
import MFEngine
import MFUtilities

/// Real-time touch diagnostics. The surface is redrawn from `TouchFeed.snapshot()` on every
/// display frame by a TimelineView + Canvas; no SwiftUI state changes per frame.
@MainActor
public struct TouchLabView: View {
    @Environment(AppModel.self) private var model

    @State private var showZones: Bool = true
    @State private var isPaused: Bool = false
    /// The view is on screen (appeared and the app's windows are not fully occluded).
    @State private var hasAppeared: Bool = false
    @State private var isAppVisible: Bool = true
    /// No frames for a while: the surface drops to a low refresh rate.
    @State private var isIdle: Bool = true
    @State private var syntheticNotice: String?
    @State private var isShowingExport: Bool = false
    @State private var isShowingCalibration: Bool = false

    public init() {}

    private var isVisible: Bool { hasAppeared && isAppVisible }

    private var liveInputAvailable: Bool {
        model.adapterStatus.state == .running && model.adapterStatus.capabilities.rawContacts
    }

    public var body: some View {
        MFPage("Touch Lab", subtitle: "Live view of what the mouse surface reports and what the recognizer makes of it.") {
            if !liveInputAvailable {
                TouchLabUnavailableBanner()
            }
            controls
            if let syntheticNotice {
                Label(syntheticNotice, systemImage: "waveform.path")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                surfaceCard
                statsPanel
                    .frame(width: 290)
            }
        }
        .onAppear {
            hasAppeared = true
            isPaused = model.touchFeed.isPaused
            isAppVisible = NSApplication.shared.occlusionState.contains(.visible)
        }
        .onDisappear { hasAppeared = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeOcclusionStateNotification)) { _ in
            isAppVisible = NSApplication.shared.occlusionState.contains(.visible)
        }
        .task { await monitorActivity() }
        .sheet(isPresented: $isShowingCalibration) {
            CalibrationSheet()
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: pausedBinding) {
                Text("Live").tag(false)
                Text("Pause").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Pause freezes the picture; frames arriving while paused are not recorded")
            Button("Clear") {
                model.touchFeed.clear()
            }
            .help("Forget the frames, trails and counters shown here")
            Toggle("Zones", isOn: $showZones)
                .toggleStyle(.checkbox)
                .help("Show the edge strips, corner zones and the centre zone used by the recognizer")
            Spacer(minLength: 8)
            TouchLabSyntheticMenu(notice: $syntheticNotice)
            if model.isSyntheticInputActive {
                Button("Stop") {
                    model.stopSynthetic()
                    syntheticNotice = nil
                }
                .help("Stop synthetic playback")
            }
            Button("Calibrate…") { isShowingCalibration = true }
            Button("Export Diagnostics…") { isShowingExport = true }
                .popover(isPresented: $isShowingExport, arrowEdge: .bottom) {
                    TouchLabExportPanel()
                }
        }
    }

    private var pausedBinding: Binding<Bool> {
        let feed: TouchFeed = model.touchFeed
        return Binding<Bool>(
            get: { isPaused },
            set: { newValue in
                isPaused = newValue
                feed.isPaused = newValue
            }
        )
    }

    // MARK: Surface

    private var surfaceOptions: TouchSurfaceRenderer.Options {
        TouchSurfaceRenderer.Options(
            showZones: showZones,
            edgeFraction: model.configuration.recognizer.edgeZoneFraction,
            cornerFraction: model.configuration.recognizer.cornerZoneFraction,
            trailLifetime: model.touchFeed.trailLifetime,
            liveInputAvailable: liveInputAvailable,
            isPaused: isPaused
        )
    }

    private var surfaceCard: some View {
        let feed: TouchFeed = model.touchFeed
        let options: TouchSurfaceRenderer.Options = surfaceOptions
        let interval: Double = isIdle ? 0.25 : 1.0 / 60.0
        return MFCard {
            TimelineView(.animation(minimumInterval: interval, paused: !isVisible)) { timeline in
                TouchSurfaceCanvas(feed: feed, date: timeline.date, options: options)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 540)
        }
    }

    private var statsPanel: some View {
        let feed: TouchFeed = model.touchFeed
        let paused: Bool = isPaused
        return TimelineView(.animation(minimumInterval: 0.2, paused: !isVisible)) { _ in
            TouchLabStatsPanel(snapshot: feed.snapshot(), now: MonotonicClock.now(), isPaused: paused)
        }
    }

    /// Checks ten times a second whether frames are arriving and flips `isIdle` only when that
    /// changes, so the 60 Hz redraw runs only while there is something to see.
    private func monitorActivity() async {
        let feed: TouchFeed = model.touchFeed
        var lastTotal: Int = -1
        var lastActivity: TimeInterval = MonotonicClock.now()
        while !Task.isCancelled {
            let snapshot: TouchFeed.Snapshot = feed.snapshot()
            let now: TimeInterval = MonotonicClock.now()
            let isTouching: Bool = !(snapshot.latest?.touching.isEmpty ?? true) && !feed.isPaused
            if snapshot.totalFrames != lastTotal || isTouching {
                lastTotal = snapshot.totalFrames
                lastActivity = now
            }
            // Trails need about a second to fade after the last frame.
            let idle: Bool = now - lastActivity > 1.5
            if idle != isIdle { isIdle = idle }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

/// Explains why no live finger data can be shown. Nothing is drawn in its place.
@MainActor
private struct TouchLabUnavailableBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("Live finger data is unavailable", systemImage: "exclamationmark.triangle.fill") {
            Text(explanation)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing is drawn on the surface unless real or clearly labelled synthetic frames arrive. "
                + "Synthetic Input still works for exploring the recognizer.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Restart Input") { model.restartInput() }
        }
    }

    private var explanation: String {
        let status: AdapterStatus = model.adapterStatus
        switch status.state {
        case .unavailable(let reason):
            return reason
        case .stopped:
            if !model.configuration.settings.allowPrivateMultitouch {
                return "The touch adapter is stopped because private multitouch access is turned off in Settings."
            }
            if model.connectedDevice == nil {
                return "The input adapter is stopped and no Magic Mouse is connected."
            }
            return "The input adapter (\(status.displayName)) is stopped."
        case .running:
            return "The active input adapter (\(status.displayName)) does not report per-finger positions, "
                + "so only fallback triggers are available."
        }
    }
}
