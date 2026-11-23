import CoreFoundation
import Foundation

// Value types shared between the engine (MFEngine), MFProfiles and the UI.

public struct AdapterStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case stopped
        case running
        /// No adapter could start; gestures that need raw contacts are disabled.
        case unavailable(reason: String)
    }
    public var identifier: String
    public var displayName: String
    public var usesPrivateAPI: Bool
    public var capabilities: InputCapabilities
    public var state: State

    public init(identifier: String = "none", displayName: String = "No input adapter", usesPrivateAPI: Bool = false,
                capabilities: InputCapabilities = .none, state: State = .stopped) {
        self.identifier = identifier; self.displayName = displayName; self.usesPrivateAPI = usesPrivateAPI
        self.capabilities = capabilities; self.state = state
    }
}

public enum GestureAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

/// Entry in the dashboard's recent-gesture list (memory only).
public struct GestureRecord: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var event: GestureEvent
    public var date: Date
    public var profileName: String
    /// Display name of the action that ran, or nil when the gesture was not bound.
    public var actionName: String?
    /// Error text when the action failed.
    public var failure: String?
    public init(id: UUID = UUID(), event: GestureEvent, date: Date = Date(), profileName: String,
                actionName: String?, failure: String? = nil) {
        self.id = id; self.event = event; self.date = date; self.profileName = profileName
        self.actionName = actionName; self.failure = failure
    }
}

public struct ActivityEntry: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable { case info, warning, error }
    public var id: UUID
    public var date: Date
    public var level: Level
    public var message: String
    public init(id: UUID = UUID(), date: Date = Date(), level: Level, message: String) {
        self.id = id; self.date = date; self.level = level; self.message = message
    }
}

public struct RunningWorkflow: Sendable, Equatable, Identifiable {
    public var id: UUID            // run id
    public var workflowID: UUID
    public var name: String
    public var startedAt: Date
    /// Index path description of the step in progress, e.g. "3 / 5".
    public var progress: String
    public init(id: UUID = UUID(), workflowID: UUID, name: String, startedAt: Date = Date(), progress: String = "") {
        self.id = id; self.workflowID = workflowID; self.name = name; self.startedAt = startedAt; self.progress = progress
    }
}

/// Measured (never estimated) pipeline numbers since launch or the last reset.
public struct EngineMetrics: Sendable, Equatable {
    public var framesProcessed: Int = 0
    public var gesturesRecognized: Int = 0
    public var actionsExecuted: Int = 0
    public var actionFailures: Int = 0
    /// Recognizer time per frame, seconds.
    public var averageProcessingTime: TimeInterval = 0
    public var maxProcessingTime: TimeInterval = 0
    /// Frame timestamp → pipeline arrival, seconds (real input only).
    public var averageDeliveryLatency: TimeInterval = 0
    /// Last contributing frame → action dispatch, seconds.
    public var averageDispatchLatency: TimeInterval = 0
    public init() {}
}

public struct BindingConflict: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// Two enabled bindings with the same trigger in the same effective profile.
        case duplicateTrigger
        /// e.g. tap vs double tap: the single tap must wait for the double-tap window.
        case delaysOther
        /// The trigger overlaps native scrolling or a system gesture.
        case overlapsSystemGesture
        /// The gesture cannot be delivered by the current device / adapter.
        case unavailableGesture
        /// A sequence trigger is a prefix of (or equal to) another trigger.
        case sequencePrefix
    }
    public enum Severity: String, Sendable { case info, warning, error }
    public var id: UUID
    public var kind: Kind
    public var severity: Severity
    public var bindingIDs: [UUID]
    public var message: String
    public init(id: UUID = UUID(), kind: Kind, severity: Severity, bindingIDs: [UUID], message: String) {
        self.id = id; self.kind = kind; self.severity = severity; self.bindingIDs = bindingIDs; self.message = message
    }
}

/// Result of parsing an import file, shown to the user before anything is applied.
public struct ImportPreview: Sendable, Equatable {
    public var profiles: [Profile]
    public var workflows: [Workflow]
    public var radialMenus: [RadialMenu]
    /// Script actions contained anywhere in the import that are not yet approved on this Mac.
    public var untrustedScripts: [ScriptAction]
    public var warnings: [String]
    /// True when the file is a full backup (settings included) rather than a profile export.
    public var isFullBackup: Bool
    /// Present only for full backups.
    public var fullConfiguration: Configuration?
    public init(profiles: [Profile] = [], workflows: [Workflow] = [], radialMenus: [RadialMenu] = [],
                untrustedScripts: [ScriptAction] = [], warnings: [String] = [], isFullBackup: Bool = false,
                fullConfiguration: Configuration? = nil) {
        self.profiles = profiles; self.workflows = workflows; self.radialMenus = radialMenus
        self.untrustedScripts = untrustedScripts; self.warnings = warnings; self.isFullBackup = isFullBackup
        self.fullConfiguration = fullConfiguration
    }
}

public enum ConfigurationError: Error, Equatable, Sendable {
    case unreadable(String)
    case unsupportedSchema(Int)
    case invalid(String)
}
