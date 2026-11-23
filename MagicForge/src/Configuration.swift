import CoreFoundation
import Foundation

/// Maps a trigger to an action inside a profile.
public struct GestureBinding: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var trigger: GestureTrigger
    public var action: Action
    public var isEnabled: Bool
    /// 0…1, 0.5 = default. Applied to the trigger's gesture kinds while this profile is active.
    public var sensitivity: Double
    /// Optional hold / tap duration override in seconds.
    public var duration: TimeInterval?
    /// Higher wins when two enabled bindings in the effective profile share a trigger.
    public var priority: Int
    public var note: String

    public init(id: UUID = UUID(), trigger: GestureTrigger, action: Action, isEnabled: Bool = true,
                sensitivity: Double = 0.5, duration: TimeInterval? = nil, priority: Int = 0, note: String = "") {
        self.id = id; self.trigger = trigger; self.action = action; self.isEnabled = isEnabled
        self.sensitivity = sensitivity; self.duration = duration; self.priority = priority; self.note = note
    }
}

/// Smart Scroll settings. With `isEnabled == false` scroll events are never touched.
public struct ScrollSettings: Codable, Sendable, Equatable, Hashable {
    public var isEnabled: Bool = false
    public var verticalMultiplier: Double = 1.0
    public var horizontalMultiplier: Double = 1.0
    public var invertVertical: Bool = false
    public var invertHorizontal: Bool = false
    /// 0 = linear (speed multiplier only) … 1 = strong extra acceleration for fast flicks.
    public var acceleration: Double = 0
    /// 0 = none … 1 = heavy smoothing of line-based (non-continuous) scroll deltas.
    public var smoothing: Double = 0
    /// Only modify events that come from a Magic Mouse (never trackpads or other mice).
    public var magicMouseOnly: Bool = true
    /// Ignore horizontal deltas smaller than this fraction of the vertical delta (axis lock).
    public var horizontalDeadZone: Double = 0
    public init() {}
}

/// A set of gesture bindings. Profiles with no bundle identifiers are manual / global profiles.
public struct Profile: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    /// Apps this profile activates for (exact bundle identifiers).
    public var bundleIdentifiers: [String]
    public var bindings: [GestureBinding]
    /// When nil the global profile's scroll settings apply.
    public var scroll: ScrollSettings?
    public var isEnabled: Bool
    /// When true, triggers not bound here fall through to the global profile.
    public var inheritsGlobal: Bool

    public init(id: UUID = UUID(), name: String, symbolName: String = "cursorarrow.motionlines",
                bundleIdentifiers: [String] = [], bindings: [GestureBinding] = [], scroll: ScrollSettings? = nil,
                isEnabled: Bool = true, inheritsGlobal: Bool = true) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.bundleIdentifiers = bundleIdentifiers
        self.bindings = bindings; self.scroll = scroll; self.isEnabled = isEnabled; self.inheritsGlobal = inheritsGlobal
    }
}

// MARK: - Workflows

public indirect enum WorkflowCondition: Codable, Sendable, Hashable {
    case frontmostAppIs(bundleID: String)
    case appIsRunning(bundleID: String)
    case clipboardContains(String)
    case not(WorkflowCondition)
}

public indirect enum WorkflowStep: Codable, Sendable, Hashable {
    /// Any action except `.workflow` (nesting is rejected by validation to rule out loops).
    case action(Action)
    case delay(seconds: Double)
    /// Waits until the app is frontmost; fails the workflow with `timedOut` otherwise.
    case waitForApp(bundleID: String, timeout: Double)
    case conditional(WorkflowCondition, then: [WorkflowStep], otherwise: [WorkflowStep])
    case notify(title: String, body: String)
}

public struct Workflow: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var steps: [WorkflowStep]
    /// Whole-workflow timeout in seconds.
    public var timeout: Double
    /// Continue with the next step when a step fails instead of aborting.
    public var continueOnError: Bool

    public init(id: UUID = UUID(), name: String, symbolName: String = "flowchart", steps: [WorkflowStep] = [],
                timeout: Double = 30, continueOnError: Bool = false) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.steps = steps
        self.timeout = timeout; self.continueOnError = continueOnError
    }
}

// MARK: - Radial menu

public struct RadialMenuItem: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var symbolName: String
    /// Ignored when `children` is not empty (the item opens a submenu instead).
    public var action: Action
    public var children: [RadialMenuItem]
    public init(id: UUID = UUID(), title: String, symbolName: String = "circle", action: Action = .none,
                children: [RadialMenuItem] = []) {
        self.id = id; self.title = title; self.symbolName = symbolName; self.action = action; self.children = children
    }
}

public struct RadialMenuTheme: Codable, Sendable, Hashable {
    public var diameter: Double = 280
    /// Hex RGB such as "#0A84FF"; empty = system accent colour.
    public var accentHex: String = ""
    public var showLabels: Bool = true
    public var showRecentActions: Bool = true
    public init() {}
}

public struct RadialMenu: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var items: [RadialMenuItem]
    public var theme: RadialMenuTheme
    /// Optional global keyboard shortcut that opens this menu.
    public var hotKey: KeyCombo?
    public init(id: UUID = UUID(), name: String, items: [RadialMenuItem] = [], theme: RadialMenuTheme = RadialMenuTheme(),
                hotKey: KeyCombo? = nil) {
        self.id = id; self.name = name; self.items = items; self.theme = theme; self.hotKey = hotKey
    }
}

// MARK: - AI

public enum AIInputSource: String, Codable, Sendable, CaseIterable { case selectedText, clipboard }

public struct PromptTemplate: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var systemPrompt: String
    /// `{{input}}` is replaced with the captured text.
    public var userPrompt: String
    public var input: AIInputSource
    public init(id: UUID = UUID(), name: String, systemPrompt: String = "", userPrompt: String = "{{input}}",
                input: AIInputSource = .selectedText) {
        self.id = id; self.name = name; self.systemPrompt = systemPrompt; self.userPrompt = userPrompt; self.input = input
    }
}

/// Optional AI integration. Disabled by default; the API key lives in the Keychain, never here.
public struct AISettings: Codable, Sendable, Hashable {
    public var isEnabled: Bool = false
    /// OpenAI-compatible base URL, e.g. "https://api.openai.com/v1".
    public var baseURL: String = ""
    public var model: String = ""
    public var timeout: Double = 30
    /// Ask for confirmation showing the exact text before every request.
    public var confirmBeforeSending: Bool = true
    public var templates: [PromptTemplate] = []
    public init() {}
    public static let keychainAccount = "ai-api-key"
}

// MARK: - App settings and root configuration

public struct AppSettings: Codable, Sendable, Hashable {
    public var launchAtLogin: Bool = false
    public var startMinimized: Bool = false
    public var notificationsEnabled: Bool = true
    public var animationsEnabled: Bool = true
    public var gesturesPaused: Bool = false
    /// Use the private MultitouchSupport adapter when present (required for touch gestures).
    public var allowPrivateMultitouch: Bool = true
    /// Keep the last recognized gestures in memory for the dashboard (never written to disk).
    public var keepRecentGestures: Bool = true
    public var showMenuBarIcon: Bool = true
    public var hasCompletedOnboarding: Bool = false
    public init() {}
}

public struct Configuration: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Configuration.currentSchemaVersion
    /// Always contains exactly one global profile whose id is `globalProfileID`.
    public var profiles: [Profile] = []
    public var globalProfileID: UUID = UUID()
    public var workflows: [Workflow] = []
    public var radialMenus: [RadialMenu] = []
    public var ai: AISettings = AISettings()
    public var settings: AppSettings = AppSettings()
    public var recognizer: RecognizerConfig = RecognizerConfig()
    /// Keyed by `DeviceInfo.id`.
    public var calibrations: [String: DeviceCalibration] = [:]
    /// SHA-256 hex digests of `ScriptAction.trustPayload` values the user approved on this Mac.
    public var approvedScriptHashes: Set<String> = []

    public init() {}

    public var globalProfile: Profile? { profiles.first { $0.id == globalProfileID } }

    public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion && lhs.profiles == rhs.profiles && lhs.globalProfileID == rhs.globalProfileID
            && lhs.workflows == rhs.workflows && lhs.radialMenus == rhs.radialMenus && lhs.ai == rhs.ai
            && lhs.settings == rhs.settings && lhs.recognizer == rhs.recognizer && lhs.calibrations == rhs.calibrations
            && lhs.approvedScriptHashes == rhs.approvedScriptHashes
    }
}
