import Foundation
import Observation
import MFCore
import MFUtilities

/// The single source of truth the UI binds to, and the coordinator that wires
/// input → recognition → profile resolution → action execution.
///
/// CONTRACT: the public surface below is what the UI is written against. Bodies are filled in
/// by the engine implementation; signatures must not change without updating the UI.
@MainActor
@Observable
public final class AppModel {
    // MARK: Observable state (read-only for the UI)

    public private(set) var configuration: Configuration
    public private(set) var devices: [DeviceInfo] = []
    public private(set) var adapterStatus = AdapterStatus()
    public private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    public private(set) var frontmostBundleID: String?
    /// Profile currently in effect (app-specific match, manual override, or global).
    public private(set) var activeProfileID: UUID
    /// Manual override chosen by the user; nil = automatic switching.
    public private(set) var profileOverrideID: UUID?
    /// Newest first, capped at 50.
    public private(set) var recentGestures: [GestureRecord] = []
    /// Newest first, capped at 200.
    public private(set) var activityLog: [ActivityEntry] = []
    public private(set) var runningWorkflows: [RunningWorkflow] = []
    public private(set) var metrics = EngineMetrics()
    /// Set when the configuration could not be loaded or saved.
    public private(set) var persistenceError: String?
    /// True while synthetic frames (Touch Lab test input) are being played.
    public private(set) var isSyntheticInputActive = false
    /// True when the engine is started.
    public private(set) var isRunning = false

    /// Live touch data for the Touch Lab (poll `touchFeed.snapshot()` from a TimelineView).
    @ObservationIgnored public let touchFeed = TouchFeed()

    /// While true, gestures are recognized and reported but bound actions are NOT executed
    /// (Gesture Studio "test gesture" and calibration use this).
    public var suppressActions = false

    /// Called on the main actor for every recognized gesture (after profile resolution).
    @ObservationIgnored public var onGesture: ((GestureEvent) -> Void)?

    @ObservationIgnored let services: Services

    // MARK: Lifecycle

    public init(services: Services) {
        self.services = services
        let configuration = Configuration()
        self.configuration = configuration
        self.activeProfileID = configuration.globalProfileID
    }

    /// Loads configuration, starts device monitoring, the input adapter and the event tap.
    public func start() {}
    /// Stops every input source and cancels running workflows. Safe to call repeatedly.
    public func stop() {}
    /// Tears down and restarts the input adapter (after permissions change or reconnect).
    public func restartInput() {}

    // MARK: Convenience accessors

    public var isPaused: Bool { configuration.settings.gesturesPaused }
    public var activeProfile: Profile? { configuration.profiles.first { $0.id == activeProfileID } }
    public var globalProfile: Profile? { configuration.globalProfile }
    public var connectedDevice: DeviceInfo? { devices.first { $0.isConnected } }
    /// Enabled bindings in effect right now (active profile plus inherited global bindings).
    public var effectiveBindings: [GestureBinding] { [] }
    public var enabledGestureCount: Int { effectiveBindings.count }

    // MARK: Configuration

    public func setPaused(_ paused: Bool) {}
    /// The only way to change configuration: mutates, validates/repairs, re-applies to the running
    /// pipeline and schedules a debounced save.
    public func update(_ mutate: (inout Configuration) -> Void) {}
    /// Writes pending changes immediately.
    public func saveNow() {}
    public func resetToDefaults() {}
    public func setProfileOverride(_ id: UUID?) {}

    // MARK: Gestures

    public func availability(of kind: GestureKind) -> GestureAvailability { .unavailable(reason: "Engine not started") }
    public func conflicts(inProfile id: UUID) -> [BindingConflict] { [] }
    /// Conflicts that would exist if `candidate` were added to / replaced in the profile.
    public func conflicts(adding candidate: GestureBinding, toProfile id: UUID) -> [BindingConflict] { [] }
    public func calibration(forDevice id: String) -> DeviceCalibration { configuration.calibrations[id] ?? DeviceCalibration() }
    public func setCalibration(_ calibration: DeviceCalibration, forDevice id: String) {}

    // MARK: Profiles

    @discardableResult public func addProfile(name: String, bundleIdentifiers: [String]) -> Profile { Profile(name: name) }
    @discardableResult public func duplicateProfile(_ id: UUID) -> Profile? { nil }
    /// The global profile cannot be deleted.
    public func deleteProfile(_ id: UUID) {}
    public func exportProfiles(_ ids: [UUID]) throws -> Data { Data() }
    /// Full backup of the configuration (no secrets; the API key stays in the Keychain).
    public func exportBackup() throws -> Data { Data() }
    public func previewImport(_ data: Data) throws -> ImportPreview { ImportPreview() }
    /// Applies a previewed import. Scripts stay untrusted unless `approveScripts` is true.
    public func applyImport(_ preview: ImportPreview, approveScripts: Bool) {}

    // MARK: Script trust

    public func isTrusted(_ script: ScriptAction) -> Bool { false }
    public func approve(_ script: ScriptAction) {}
    public func revokeApproval(_ script: ScriptAction) {}
    /// Scripts referenced anywhere in the configuration that are not approved yet.
    public func untrustedScripts() -> [ScriptAction] { [] }

    // MARK: Actions and workflows

    public func availability(of action: Action) -> ActionAvailability { .available }
    /// Runs any action (leaf or routed). Never throws; failures are returned and logged.
    @discardableResult public func run(_ action: Action, source: ActionSource) async -> Result<Void, ActionError> {
        .failure(.unsupported("Engine not started"))
    }
    public func cancelAllWorkflows() {}
    /// Validation problems of a workflow (nesting, unknown references, empty), for the builder UI.
    public func validationIssues(for workflow: Workflow) -> [String] { [] }
    public func showRadialMenu(_ id: UUID) {}

    // MARK: Permissions

    public func refreshPermissions() {}
    public func requestPermission(_ kind: PermissionKind) {}
    public func openPermissionSettings(_ kind: PermissionKind) {}
    /// Why a permission is needed, tailored to what is currently configured; nil when unused.
    public func permissionRationale(_ kind: PermissionKind) -> String? { nil }

    // MARK: AI

    public var hasAPIKey: Bool { false }
    public func setAPIKey(_ key: String?) throws {}
    @discardableResult public func runAITemplate(_ id: UUID) async -> Result<String, AIError> { .failure(.disabled) }
    /// Sends a minimal test request to verify endpoint, model and key.
    public func testAIConnection() async -> Result<String, AIError> { .failure(.disabled) }

    // MARK: Synthetic input and diagnostics

    /// Plays frames through the real recognition pipeline (flagged synthetic in the Touch Lab).
    /// With `realtime` the original frame spacing is kept; otherwise frames are fed immediately.
    public func playSynthetic(_ frames: [TouchFrame], realtime: Bool) {}
    public func stopSynthetic() {}
    public func resetMetrics() {}
    public func clearRecentGestures() {}
    /// JSON diagnostics (versions, adapter, capabilities, metrics, permissions, recent gesture
    /// kinds). Touch coordinates are included only when `includeTouchFrames` is true.
    public func diagnosticsReport(includeTouchFrames: Bool) -> Data { Data() }
}
