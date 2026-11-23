import Foundation
import MFCore
import MFUtilities

// Main-actor side of the gesture pipeline: records, metrics, dispatch, synthetic input.
extension AppModel {
    /// Called for every gesture the pipeline resolved (already matched against sequences).
    func handleGesture(_ output: PipelineOutput) {
        guard isRunning else { return }
        metrics.gesturesRecognized += 1
        syncPipelineMetrics()
        onGesture?(output.event)

        var record = GestureRecord(event: output.event, profileName: output.profileName, actionName: nil)
        guard let binding = output.binding, !isPaused, !suppressActions else {
            appendRecord(record)
            return
        }
        record.actionName = binding.action.displayName(in: configuration)
        // A gesture repeated faster than its action finishes must not pile up executions.
        guard !executingBindings.contains(binding.id) else {
            record.failure = "Skipped: the previous run of this action has not finished."
            appendRecord(record)
            return
        }
        appendRecord(record)
        executingBindings.insert(binding.id)
        dispatchLatencyTotal += max(0, MonotonicClock.now() - output.recognizedAt)
        dispatchLatencyCount += 1
        metrics.averageDispatchLatency = dispatchLatencyTotal / Double(dispatchLatencyCount)

        let context = ActionContext(source: .gesture, frontmostBundleID: frontmostBundleID, gesture: output.event)
        let action = binding.action
        let bindingID = binding.id
        let recordID = record.id
        Task { [weak self] in
            guard let self else { return }
            let result = await self.runTopLevel(action, context: context)
            self.executingBindings.remove(bindingID)
            if case .failure(let error) = result, error != .cancelled {
                self.markRecord(recordID, failure: EngineText.describe(error))
            }
        }
    }

    private func appendRecord(_ record: GestureRecord) {
        guard configuration.settings.keepRecentGestures else { return }
        recentGestures.insert(record, at: 0)
        if recentGestures.count > AppModel.recentGestureLimit {
            recentGestures.removeLast(recentGestures.count - AppModel.recentGestureLimit)
        }
    }

    private func markRecord(_ id: UUID, failure: String) {
        guard let index = recentGestures.firstIndex(where: { $0.id == id }) else { return }
        recentGestures[index].failure = failure
    }

    public func clearRecentGestures() {
        recentGestures.removeAll()
    }

    // MARK: Metrics

    /// Copies the pipeline's frame counters into the observable metrics.
    func syncPipelineMetrics() {
        let stats = pipeline.currentStats
        var updated = metrics
        updated.framesProcessed = stats.frames
        updated.averageProcessingTime = stats.frames > 0 ? stats.processingTotal / Double(stats.frames) : 0
        updated.maxProcessingTime = stats.processingMax
        updated.averageDeliveryLatency = stats.realFrames > 0 ? stats.deliveryTotal / Double(stats.realFrames) : 0
        if updated != metrics { metrics = updated }
    }

    public func resetMetrics() {
        pipeline.resetStats()
        dispatchLatencyTotal = 0
        dispatchLatencyCount = 0
        metrics = EngineMetrics()
    }

    // MARK: Synthetic input

    /// Plays frames through the real recognition pipeline (flagged synthetic in the Touch Lab).
    /// With `realtime` the original frame spacing is kept; otherwise frames are fed immediately.
    /// Frames are re-timestamped onto the current monotonic clock; real touch frames are ignored
    /// until playback ends. Ignored while the engine is stopped.
    public func playSynthetic(_ frames: [TouchFrame], realtime: Bool) {
        guard isRunning, !frames.isEmpty else { return }
        isSyntheticInputActive = true
        syntheticToken = pipeline.playSynthetic(frames, realtime: realtime)
    }

    public func stopSynthetic() {
        pipeline.stopSynthetic()
        syntheticToken = -1
        if isSyntheticInputActive { isSyntheticInputActive = false }
    }

    func syntheticPlaybackFinished(_ token: Int) {
        guard token == syntheticToken else { return }
        syntheticToken = -1
        isSyntheticInputActive = false
    }
}
