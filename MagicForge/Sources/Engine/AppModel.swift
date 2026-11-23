import Foundation
import Observation
import MFCore
import MFUtilities
import MFProfiles
import MFAutomation

/// The single source of truth the UI binds to, and the coordinator that wires
/// input → recognition → profile resolution → action execution.
///
/// CONTRACT: the public surface is what the UI is written against; signatures must not change
/// without updating the UI. The implementation is split by topic into `AppModel+*.swift`
/// (see docs/ENGINE.md). All state here is main-actor confined; the input threads work on
/// value snapshots owned by `GesturePipeline`.
@MainActor
@Observable
public final class AppModel {
    // MARK: Observable state (read-only for the UI)

    public internal(set) var configuration: Configuration
    public internal(set) var devices: [DeviceInfo] = []
    public internal(set) var adapterStatus = AdapterStatus()
    public internal(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    public internal(set) var frontmostBundleID: String?
    /// Profile currently in effect (app-specific match, manual override, or global).
    public internal(set) var activeProfileID: UUID
    /// Manual override chosen by the user; nil = automatic switching.
    public internal(set) var profileOverrideID: UUID?
    /// Newest first, capped at 50.
    public internal(set) var recentGestures: [GestureRecord] = []
    /// Newest first, capped at 200.
    public internal(set) var activityLog: [ActivityEntry] = []
    public internal(set) var runningWorkflows: [RunningWorkflow] = []
    public internal(set) var metrics = EngineMetrics()
    /// Set when the configuration could not be loaded or saved.
    public internal(set) var persistenceError: String?
    /// True while synthetic frames (Touch Lab test input) are being played.
    public internal(set) var isSyntheticInputActive = false
    /// True when the engine is started.
    public internal(set) var isRunning = false

    /// Live touch data for the Touch Lab (poll `touchFeed.snapshot()` from a TimelineView).
    @ObservationIgnored public let touchFeed = TouchFeed()

    /// While true, gestures are recognized and reported but bound actions are NOT executed
    /// (Gesture Studio "test gesture" and calibration use this). The recognizer then listens for
    /// every gesture the input can deliver, bound or not, so any gesture can be tried out.
    public var suppressActions = false {
        didSet {
            if oldValue != suppressActions { applyActiveProfile() }
        }
    }

    /// Called on the main actor for every recognized gesture (after profile resolution).
    @ObservationIgnored public var onGesture: ((GestureEvent) -> Void)?

    @ObservationIgnored let services: Services

    // MARK: Internal state (main actor only)

    static let recentGestureLimit = 50
    static let activityLogLimit = 200
    static let recentRadialItemLimit = 6
    /// Routed actions (menu → workflow → menu …) deeper than this are refused.
    static let maxRoutingDepth = 6

    @ObservationIgnored let log = Log("engine")
    @ObservationIgnored let pipeline: GesturePipeline
    @ObservationIgnored let workflowRunner: WorkflowRunner
    @ObservationIgnored let workflowEnvironment: EngineWorkflowEnvironment
    /// Copy of `configuration.approvedScriptHashes` readable from the workflow runner's executor.
    @ObservationIgnored let approvedHashes: Locked<Set<String>>

    @ObservationIgnored var resolvedProfile: ResolvedProfile
    @ObservationIgnored var activeAdapter: TouchInputAdapter?
    @ObservationIgnored var adapterUnavailableReason = "MagicForge is not running."
    @ObservationIgnored var isPointerSourceRunning = false

    @ObservationIgnored var hasLoadedConfiguration = false
    @ObservationIgnored var hasUnsavedChanges = false
    /// Non-nil when saving would destroy data MagicForge could not read (see `loadConfiguration`).
    @ObservationIgnored var savesBlockedReason: String?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    /// Delay between the last change and the write to disk, seconds.
    @ObservationIgnored var saveDebounce: TimeInterval = 0.5

    /// Bindings whose gesture-triggered action is still running.
    @ObservationIgnored var executingBindings: Set<UUID> = []
    @ObservationIgnored var recentRadialItems: [RadialMenuItem] = []
    @ObservationIgnored var syntheticToken = -1
    @ObservationIgnored var dispatchLatencyTotal: TimeInterval = 0
    @ObservationIgnored var dispatchLatencyCount = 0
    @ObservationIgnored var cachedHasAPIKey: Bool?
    /// Bumped when the stored API key changes, so `hasAPIKey` is observable.
    var apiKeyRevision = 0

    // MARK: Lifecycle

    public init(services: Services) {
        self.services = services
        let configuration = Configuration()
        self.configuration = configuration
        self.activeProfileID = configuration.globalProfileID
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil)
        self.resolvedProfile = resolved
        self.pipeline = GesturePipeline(feed: touchFeed, profile: resolved)
        let hashes = Locked<Set<String>>([])
        self.approvedHashes = hashes
        let environment = EngineWorkflowEnvironment()
        self.workflowEnvironment = environment
        self.workflowRunner = WorkflowRunner(performer: services.performer, environment: environment,
                                             isScriptTrusted: { script in
            hashes.withLock { $0.contains(ScriptTrust.hash(of: script)) }
        })
        environment.model = self
        connectPipeline()
    }

    // MARK: Convenience accessors

    public var isPaused: Bool { configuration.settings.gesturesPaused }
    public var activeProfile: Profile? { configuration.profiles.first { $0.id == activeProfileID } }
    public var globalProfile: Profile? { configuration.globalProfile }
    public var connectedDevice: DeviceInfo? { devices.first { $0.isConnected } }
    /// Enabled bindings in effect right now (active profile plus inherited global bindings).
    /// Bindings set to "No Action" are left out; bindings the current input cannot deliver are
    /// included (ask `availability(of:)` for those).
    public var effectiveBindings: [GestureBinding] {
        let profile = activeProfile ?? ProfileResolver.globalProfile(in: configuration)
        return ProfileResolver.effectiveBindings(for: profile, in: configuration).filter { $0.action != .none }
    }
    public var enabledGestureCount: Int { effectiveBindings.count }

    // MARK: Activity log

    func logActivity(_ level: ActivityEntry.Level, _ message: String) {
        activityLog.insert(ActivityEntry(level: level, message: message), at: 0)
        if activityLog.count > AppModel.activityLogLimit {
            activityLog.removeLast(activityLog.count - AppModel.activityLogLimit)
        }
    }
}
