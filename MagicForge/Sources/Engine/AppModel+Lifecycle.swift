import Foundation
import MFCore
import MFUtilities
import MFProfiles

// Starting and stopping the engine, input sources, devices and permissions.
extension AppModel {
    /// Loads configuration, starts device monitoring, the input adapter and the event tap.
    /// Synchronous: configuration, permissions, devices and `isRunning` are final on return.
    public func start() {
        guard !isRunning else { return }
        if !hasLoadedConfiguration { loadConfiguration() }
        isRunning = true
        permissions = currentPermissions()

        services.deviceMonitor.start { [weak self] devices in
            MainHop.run { [weak self] in self?.devicesChanged(devices) }
        }
        devices = services.deviceMonitor.devices
        frontmostBundleID = services.frontmostApp.frontmostBundleID
        services.frontmostApp.startObserving { [weak self] bundleID in
            MainHop.run { [weak self] in self?.frontmostAppChanged(bundleID) }
        }

        startAdapter()
        startPointerSource(reportFailure: true)
        refreshInputState()
        logActivity(.info, "MagicForge started.")
    }

    /// Stops every input source and cancels running workflows. Safe to call repeatedly.
    public func stop() {
        guard isRunning else {
            saveNow()
            return
        }
        isRunning = false
        stopInput()
        services.deviceMonitor.stop()
        services.frontmostApp.stopObserving()
        cancelAllWorkflows()
        services.radialMenu?.dismiss()
        executingBindings.removeAll()
        adapterUnavailableReason = "MagicForge is not running."
        refreshInputState()
        saveNow()
        logActivity(.info, "MagicForge stopped.")
    }

    /// Tears down and restarts the input adapter (after permissions change or reconnect).
    public func restartInput() {
        guard isRunning else { return }
        stopInput()
        permissions = currentPermissions()
        startAdapter()
        startPointerSource(reportFailure: true)
        refreshInputState()
    }

    // MARK: Input sources

    func connectPipeline() {
        pipeline.setCallbacks(GesturePipeline.Callbacks(
            onOutput: { [weak self] output in
                MainHop.enqueue { [weak self] in self?.handleGesture(output) }
            },
            onStatsChanged: { [weak self] in
                MainHop.enqueue { [weak self] in self?.syncPipelineMetrics() }
            },
            onSyntheticFinished: { [weak self] token in
                MainHop.enqueue { [weak self] in self?.syntheticPlaybackFinished(token) }
            },
            onHotKey: { [weak self] identifier in
                MainHop.enqueue { [weak self] in self?.showRadialMenu(identifier) }
            }))
    }

    private func stopInput() {
        isSyntheticInputActive = false
        syntheticToken = -1
        // Every adapter, not only the active one: `stop()` is documented as safe to repeat.
        for adapter in services.adapters { adapter.stop() }
        activeAdapter = nil
        services.pointerEvents?.stop()
        isPointerSourceRunning = false
        pipeline.reset()
    }

    /// Starts the first usable adapter. On failure the reason is kept for `adapterStatus`;
    /// the attempt is repeated when a device appears and on `restartInput()`.
    func startAdapter() {
        guard isRunning, activeAdapter == nil else { return }
        guard !services.adapters.isEmpty else {
            adapterUnavailableReason = "This build has no touch input source."
            return
        }
        var reasons: [String] = []
        for adapter in services.adapters {
            if adapter.usesPrivateAPI && !configuration.settings.allowPrivateMultitouch {
                reasons.append("\(adapter.displayName) is turned off in Settings (“Allow private multitouch”).")
                continue
            }
            if case .unavailable(let reason) = adapter.checkAvailability() {
                reasons.append(reason)
                continue
            }
            do {
                let pipeline = self.pipeline
                try adapter.start(onFrame: { [weak pipeline] frame in pipeline?.ingest(frame) })
                activeAdapter = adapter
                logActivity(.info, "Touch input started: \(adapter.displayName).")
                return
            } catch AdapterError.noDevice {
                reasons.append("No Magic Mouse is connected.")
            } catch AdapterError.unavailable(let reason) {
                reasons.append(reason)
            } catch AdapterError.startFailed(let reason) {
                reasons.append("\(adapter.displayName) could not start: \(reason)")
            } catch {
                reasons.append("\(adapter.displayName) could not start: \(error.localizedDescription)")
            }
        }
        let reason = reasons.joined(separator: " ")
        if reason != adapterUnavailableReason {
            adapterUnavailableReason = reason
            logActivity(.warning, "Touch gestures are unavailable: \(reason)")
        }
    }

    /// Starts the event tap when there is one. Without Accessibility it reports false (and never
    /// prompts); the attempt is repeated from `refreshPermissions()`.
    func startPointerSource(reportFailure: Bool) {
        guard isRunning, let source = services.pointerEvents else { return }
        if source.isRunning {
            isPointerSourceRunning = true
            return
        }
        pipeline.resetScroll()
        let started = source.start(handlers: pipeline.makePointerHandlers())
        isPointerSourceRunning = started
        if started {
            logActivity(.info, "Mouse event observation started (fallback triggers, Smart Scroll, hot keys).")
        } else if reportFailure {
            logActivity(.warning, "Mouse events cannot be observed, so fallback triggers, Smart Scroll and hot keys "
                        + "are off. This usually means the Accessibility permission is missing.")
        }
    }

    /// Recomputes `adapterStatus`, then re-resolves the profile against the new capabilities.
    func refreshInputState() {
        var status: AdapterStatus
        if let adapter = activeAdapter {
            var capabilities = adapter.capabilities
            capabilities.pointerEvents = isPointerSourceRunning
            status = AdapterStatus(identifier: adapter.identifier, displayName: adapter.displayName,
                                   usesPrivateAPI: adapter.usesPrivateAPI, capabilities: capabilities, state: .running)
        } else {
            status = AdapterStatus()
            if let preferred = services.adapters.first {
                status.identifier = preferred.identifier
                status.displayName = preferred.displayName
                status.usesPrivateAPI = preferred.usesPrivateAPI
            }
            status.capabilities = InputCapabilities(rawContacts: false, maxContacts: 0, contactSize: false,
                                                    pointerEvents: isPointerSourceRunning)
            status.state = isRunning ? .unavailable(reason: adapterUnavailableReason) : .stopped
        }
        if status != adapterStatus { adapterStatus = status }
        applyActiveProfile()
    }

    // MARK: Devices and frontmost app

    private func devicesChanged(_ newDevices: [DeviceInfo]) {
        guard isRunning else { return }
        let wasConnected = connectedDevice != nil
        devices = newDevices
        let isConnected = connectedDevice != nil
        if wasConnected != isConnected {
            let model = connectedDevice?.model.displayName ?? "Magic Mouse"
            logActivity(.info, isConnected ? "\(model) connected." : "Magic Mouse disconnected.")
        }
        if let adapter = activeAdapter {
            adapter.devicesDidChange()
        } else if isConnected {
            startAdapter()
        }
        refreshInputState()
    }

    private func frontmostAppChanged(_ bundleID: String?) {
        guard isRunning, bundleID != frontmostBundleID else { return }
        frontmostBundleID = bundleID
        applyActiveProfile()
    }

    // MARK: Permissions

    func currentPermissions() -> [PermissionKind: PermissionStatus] {
        var result: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases { result[kind] = services.permissions.status(of: kind) }
        return result
    }

    public func refreshPermissions() {
        let latest = currentPermissions()
        let before = permissions[.accessibility]
        if latest != permissions { permissions = latest }
        guard isRunning, let source = services.pointerEvents else { return }
        let wasRunning = isPointerSourceRunning
        isPointerSourceRunning = source.isRunning
        let accessibility = latest[.accessibility]
        if !isPointerSourceRunning, accessibility == .granted || accessibility == .notRequired {
            // Only report a failure when the permission just changed, not on every refresh.
            startPointerSource(reportFailure: before != accessibility)
        }
        if wasRunning && !isPointerSourceRunning {
            logActivity(.warning, "Mouse event observation stopped; fallback triggers, Smart Scroll and hot keys are off.")
        }
        if wasRunning != isPointerSourceRunning { refreshInputState() }
    }

    public func requestPermission(_ kind: PermissionKind) {
        services.permissions.request(kind)
        refreshPermissions()
    }

    public func openPermissionSettings(_ kind: PermissionKind) {
        services.permissions.openSystemSettings(for: kind)
    }

    /// Why a permission is needed, tailored to what is currently configured; nil when unused.
    public func permissionRationale(_ kind: PermissionKind) -> String? {
        switch kind {
        case .accessibility:
            let uses = accessibilityUses()
            guard !uses.isEmpty else { return nil }
            return "Accessibility lets MagicForge " + EngineText.list(uses) + "."
        case .automation:
            let hasAppleScript = ScriptTrust.scripts(in: configuration).contains { script in
                if case .appleScript = script { return true }
                return false
            }
            return hasAppleScript
                ? "Your AppleScript actions control other apps. macOS asks for consent per app the first time a script addresses it."
                : nil
        case .inputMonitoring:
            // MagicForge's input path does not use listen-only observation: touch frames come from
            // the multitouch adapter and pointer events from an active tap (Accessibility).
            return nil
        }
    }

    private func accessibilityUses() -> [String] {
        var uses: [String] = []
        var actions: [Action] = []
        var usesChords = false
        var usesScroll = false
        for profile in configuration.profiles where profile.isEnabled {
            if profile.scroll?.isEnabled == true { usesScroll = true }
            for binding in profile.bindings where binding.isEnabled {
                actions.append(binding.action)
                if binding.trigger.kinds.contains(where: { $0.category == .fallback }) { usesChords = true }
            }
        }
        if services.pointerEvents != nil {
            if usesChords { uses.append("detect the Control-Option fallback triggers") }
            if usesScroll { uses.append("adjust scrolling (Smart Scroll)") }
            if configuration.radialMenus.contains(where: { $0.hotKey != nil }) { uses.append("listen for radial menu hot keys") }
        }
        actions += configuration.workflows.flatMap { ActionWalker.actions(in: $0.steps) }
        actions += configuration.radialMenus.flatMap { ActionWalker.actions(in: $0.items) }
        let postsEvents = actions.contains { action in
            switch action {
            case .keyboard, .mouse, .window, .system: return true
            case .text(let text):
                switch text {
                case .copy, .paste, .pasteText: return true
                case .copyText: return false
                }
            default: return false
            }
        }
        if postsEvents { uses.append("press shortcuts, click, paste and move windows for your actions") }
        if configuration.ai.isEnabled, configuration.ai.templates.contains(where: { $0.input == .selectedText }) {
            uses.append("copy the selected text for AI prompts you trigger")
        }
        return uses
    }
}

/// Flattens the actions nested in workflows and radial menus (bounded depth).
enum ActionWalker {
    static func actions(in steps: [WorkflowStep], depth: Int = 0) -> [Action] {
        guard depth < 16 else { return [] }
        var result: [Action] = []
        for step in steps {
            switch step {
            case .action(let action): result.append(action)
            case .conditional(_, let then, let otherwise):
                result += actions(in: then, depth: depth + 1) + actions(in: otherwise, depth: depth + 1)
            case .delay, .waitForApp, .notify: break
            }
        }
        return result
    }

    static func actions(in items: [RadialMenuItem], depth: Int = 0) -> [Action] {
        guard depth < 16 else { return [] }
        var result: [Action] = []
        for item in items {
            result.append(item.action)
            result += actions(in: item.children, depth: depth + 1)
        }
        return result
    }
}

enum EngineText {
    /// "a", "a and b", "a, b and c".
    static func list(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    static func describe(_ error: ActionError) -> String {
        switch error {
        case .permissionDenied(let kind): return "The \(kind.displayName) permission is missing."
        case .unsupported(let reason): return reason
        case .failed(let reason): return reason
        case .timedOut: return "It took too long and was stopped."
        case .cancelled: return "It was cancelled."
        case .untrusted: return "The script has not been approved on this Mac."
        case .notFound(let what): return "\(what) no longer exists."
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ConfigurationError.unreadable(let text), ConfigurationError.invalid(let text): return text
        case ConfigurationError.unsupportedSchema(let version):
            return "The configuration was written by a newer version of MagicForge (format \(version))."
        default: return error.localizedDescription
        }
    }
}
