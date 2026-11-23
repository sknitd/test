import Foundation
import MFCore
import MFUtilities
import MFProfiles

/// A store that keeps an older readable copy of the configuration.
protocol ConfigurationBackupProviding {
    func loadBackup() throws -> Configuration?
}

extension JSONConfigurationStore: ConfigurationBackupProviding {}

// Loading, changing and saving the configuration; profile resolution.
extension AppModel {
    // MARK: Loading

    /// Reads the configuration once per model.
    ///
    /// - Nothing saved yet: the defaults are used and written.
    /// - Unreadable / corrupt: `persistenceError` is set and the store's backup is used when it
    ///   has one (`ConfigurationBackupProviding`), otherwise the defaults. Nothing is written
    ///   until the user changes something, so the damaged data is not replaced behind their back.
    /// - Written by a newer MagicForge: the defaults are used and saving is switched off for
    ///   this session, because any save would downgrade and destroy that file.
    func loadConfiguration() {
        hasLoadedConfiguration = true
        // Edits made before the first start were made to a placeholder and are dropped.
        hasUnsavedChanges = false
        saveTask?.cancel()
        var loaded: Configuration
        do {
            if let stored = try services.store.load() {
                loaded = stored
            } else {
                loaded = DefaultConfiguration.make()
                hasUnsavedChanges = true
            }
        } catch {
            var message = EngineText.describe(error)
            if case ConfigurationError.unsupportedSchema = error {
                savesBlockedReason = message + " Changes you make now are not saved, so that file stays intact."
                message = savesBlockedReason ?? message
                loaded = DefaultConfiguration.make()
            } else if let backup = (services.store as? ConfigurationBackupProviding).flatMap({ try? $0.loadBackup() }) {
                loaded = backup
                message += " The previous saved version was restored."
            } else {
                loaded = DefaultConfiguration.make()
                message += " MagicForge is using its default settings."
            }
            persistenceError = message
            logActivity(.error, "The configuration could not be loaded. \(message)")
            log.error("Configuration load failed")
        }
        let repairs = ConfigurationValidator.repair(&loaded)
        if !repairs.isEmpty { log.notice("Configuration repaired on load (\(repairs.count) note(s))") }
        configuration = loaded
        if hasUnsavedChanges { writeConfiguration() }
        applyActiveProfile()
    }

    // MARK: Changing

    public func setPaused(_ paused: Bool) {
        update { $0.settings.gesturesPaused = paused }
    }

    /// The only way to change configuration: mutates, validates/repairs, re-applies to the running
    /// pipeline and schedules a debounced save. Script approvals cannot be added here (only
    /// `approve(_:)` and an import with `approveScripts` can); removing them is allowed.
    public func update(_ mutate: (inout Configuration) -> Void) {
        applyChange(mayAddApprovals: false, mutate)
    }

    func applyChange(mayAddApprovals: Bool, _ mutate: (inout Configuration) -> Void) {
        var changed = configuration
        mutate(&changed)
        if !mayAddApprovals { changed.approvedScriptHashes.formIntersection(configuration.approvedScriptHashes) }
        ConfigurationValidator.repair(&changed)
        guard changed != configuration else { return }
        let previous = configuration
        configuration = changed
        if let override = profileOverrideID,
           !changed.profiles.contains(where: { $0.id == override && ($0.isEnabled || $0.id == changed.globalProfileID) }) {
            profileOverrideID = nil
        }
        if isRunning, previous.settings.allowPrivateMultitouch != changed.settings.allowPrivateMultitouch {
            restartInput()
        } else {
            applyActiveProfile()
        }
        if previous.settings.gesturesPaused != changed.settings.gesturesPaused {
            logActivity(.info, changed.settings.gesturesPaused ? "Gestures paused." : "Gestures resumed.")
        }
        scheduleSave()
    }

    public func resetToDefaults() {
        profileOverrideID = nil
        update { $0 = DefaultConfiguration.make() }
        logActivity(.info, "All settings were reset to the defaults.")
    }

    public func setProfileOverride(_ id: UUID?) {
        if let id {
            guard let profile = configuration.profiles.first(where: { $0.id == id }),
                  profile.isEnabled || id == configuration.globalProfileID else { return }
        }
        guard profileOverrideID != id else { return }
        profileOverrideID = id
        applyActiveProfile()
    }

    // MARK: Saving

    private func scheduleSave() {
        hasUnsavedChanges = true
        // Before `start()` the stored configuration has not been read; writing now would replace it.
        guard hasLoadedConfiguration else { return }
        saveTask?.cancel()
        let delay = UInt64(max(0, saveDebounce) * 1_000_000_000)
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.writeConfiguration()
        }
    }

    /// Writes pending changes immediately.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard hasLoadedConfiguration, hasUnsavedChanges else { return }
        writeConfiguration()
    }

    private func writeConfiguration() {
        if let reason = savesBlockedReason {
            if persistenceError != reason { persistenceError = reason }
            return
        }
        do {
            try services.store.save(configuration)
            hasUnsavedChanges = false
            if persistenceError != nil { persistenceError = nil }
        } catch {
            let message = "The configuration could not be saved. " + EngineText.describe(error)
            if persistenceError != message {
                persistenceError = message
                logActivity(.error, message)
            }
            log.error("Configuration save failed")
        }
    }

    // MARK: Profile resolution

    /// Resolves the profile for the current app / override / capabilities and pushes the result
    /// to the pipeline and the event tap as value snapshots.
    func applyActiveProfile() {
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: frontmostBundleID,
                                               overrideID: profileOverrideID,
                                               capabilities: isRunning ? adapterStatus.capabilities : nil)
        resolvedProfile = resolved
        if activeProfileID != resolved.profileID { activeProfileID = resolved.profileID }
        approvedHashes.withLock { $0 = configuration.approvedScriptHashes }

        // While actions are suppressed (Gesture Studio, calibration) every gesture is listened for.
        var recognizerKinds = resolved.enabledKinds.filter { $0.requirement == .rawContacts }
        var chordKinds = resolved.chordKinds
        if suppressActions {
            recognizerKinds = Set(GestureKind.allCases.filter { $0.requirement == .rawContacts })
            chordKinds = Set(GestureKind.allCases.filter { $0.category == .fallback })
        }
        let calibration = connectedDevice.flatMap { configuration.calibrations[$0.id] } ?? DeviceCalibration()
        pipeline.apply(PipelineSettings(profile: resolved,
                                        recognizer: resolved.recognizerConfig(base: configuration.recognizer),
                                        calibration: calibration, recognizerKinds: recognizerKinds,
                                        actionsAreLive: !isPaused && !suppressActions))
        if let source = services.pointerEvents {
            source.setEnabledChords(chordKinds)
            source.setScrollInterceptionEnabled(resolved.scroll.isEnabled)
            var hotKeys: [UUID: KeyCombo] = [:]
            for menu in configuration.radialMenus {
                if let combo = menu.hotKey { hotKeys[menu.id] = combo }
            }
            source.registerHotKeys(hotKeys)
        }
    }

    // MARK: Gestures

    public func availability(of kind: GestureKind) -> GestureAvailability {
        guard isRunning else { return .unavailable(reason: "MagicForge is not running.") }
        let capabilities = adapterStatus.capabilities
        switch kind.requirement {
        case .pointerEvents:
            if capabilities.pointerEvents { return .available }
            guard services.pointerEvents != nil else {
                return .unavailable(reason: "This build cannot observe mouse events, so fallback triggers are not offered.")
            }
            if let status = permissions[.accessibility], status != .granted, status != .notRequired {
                return .unavailable(reason: "Needs the Accessibility permission to observe mouse clicks and scrolling.")
            }
            return .unavailable(reason: "Mouse events are not being observed right now. Try “Restart Input”.")
        case .rawContacts:
            guard capabilities.rawContacts else {
                if case .unavailable(let reason) = adapterStatus.state, !reason.isEmpty {
                    return .unavailable(reason: reason)
                }
                return .unavailable(reason: "No touch input source is running.")
            }
            if capabilities.maxContacts < kind.fingerCount {
                return .unavailable(reason: "Needs \(kind.fingerCount) fingers, but \(adapterStatus.displayName) "
                                    + "reports at most \(capabilities.maxContacts).")
            }
            return .available
        }
    }

    public func conflicts(inProfile id: UUID) -> [BindingConflict] {
        guard let profile = configuration.profiles.first(where: { $0.id == id }) else { return [] }
        return ConflictDetector.conflicts(in: profile, configuration: configuration, capabilities: conflictCapabilities)
    }

    /// Conflicts that would exist if `candidate` were added to / replaced in the profile.
    public func conflicts(adding candidate: GestureBinding, toProfile id: UUID) -> [BindingConflict] {
        guard let profile = configuration.profiles.first(where: { $0.id == id }) else { return [] }
        return ConflictDetector.conflicts(adding: candidate, to: profile, configuration: configuration,
                                          capabilities: conflictCapabilities)
    }

    /// Unavailable-gesture conflicts are only meaningful while the engine knows what it can deliver.
    private var conflictCapabilities: InputCapabilities? { isRunning ? adapterStatus.capabilities : nil }

    public func calibration(forDevice id: String) -> DeviceCalibration {
        configuration.calibrations[id] ?? DeviceCalibration()
    }

    public func setCalibration(_ calibration: DeviceCalibration, forDevice id: String) {
        update { $0.calibrations[id] = calibration }
    }

    // MARK: Profiles

    @discardableResult public func addProfile(name: String, bundleIdentifiers: [String]) -> Profile {
        let profile = Profile(name: name, bundleIdentifiers: bundleIdentifiers)
        update { $0.profiles.append(profile) }
        return configuration.profiles.first { $0.id == profile.id } ?? profile
    }

    @discardableResult public func duplicateProfile(_ id: UUID) -> Profile? {
        guard let original = configuration.profiles.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " Copy"
        copy.bindings = original.bindings.map { binding in
            var duplicate = binding
            duplicate.id = UUID()
            return duplicate
        }
        update { $0.profiles.append(copy) }
        return configuration.profiles.first { $0.id == copy.id }
    }

    /// The global profile cannot be deleted.
    public func deleteProfile(_ id: UUID) {
        guard id != configuration.globalProfileID else { return }
        if profileOverrideID == id { profileOverrideID = nil }
        update { $0.profiles.removeAll { $0.id == id } }
    }

    public func exportProfiles(_ ids: [UUID]) throws -> Data {
        try ProfileTransfer.exportProfiles(ids, from: configuration)
    }

    /// Full backup of the configuration (no secrets; the API key stays in the Keychain).
    public func exportBackup() throws -> Data {
        try ProfileTransfer.exportBackup(configuration)
    }

    public func previewImport(_ data: Data) throws -> ImportPreview {
        try ProfileTransfer.preview(data: data, current: configuration)
    }

    /// Applies a previewed import. Scripts stay untrusted unless `approveScripts` is true.
    /// A profile import adds to what exists (including the AI prompts it carries); a full backup
    /// replaces the configuration (`ProfileTransfer.apply` branches on `isFullBackup`).
    public func applyImport(_ preview: ImportPreview, approveScripts: Bool) {
        var notes: [String] = []
        applyChange(mayAddApprovals: true) { configuration in
            notes = ProfileTransfer.apply(preview: preview, to: &configuration, approveScripts: approveScripts)
        }
        let summary = preview.isFullBackup
            ? "Backup restored."
            : "Imported \(preview.profiles.count) profile(s)."
        logActivity(notes.isEmpty ? .info : .warning,
                    notes.isEmpty ? summary : summary + " " + notes.joined(separator: " "))
    }

    // MARK: Script trust

    public func isTrusted(_ script: ScriptAction) -> Bool {
        ScriptTrust.isTrusted(script, in: configuration)
    }

    public func approve(_ script: ScriptAction) {
        applyChange(mayAddApprovals: true) { ScriptTrust.approve(script, in: &$0) }
    }

    public func revokeApproval(_ script: ScriptAction) {
        update { ScriptTrust.revoke(script, in: &$0) }
    }

    /// Scripts referenced anywhere in the configuration that are not approved yet.
    public func untrustedScripts() -> [ScriptAction] {
        ScriptTrust.untrustedScripts(in: configuration)
    }
}
