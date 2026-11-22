import Foundation

// Service protocols implemented by the macOS modules (MFDevices, MFInput, MFActions, MFUI, App)
// and by mocks in tests. The engine depends only on these.

public enum MagicMouseModel: String, Codable, Sendable {
    case magicMouse1, magicMouse2, magicMouseUSBC, unknownMagicMouse
    public var displayName: String {
        switch self {
        case .magicMouse1: return "Magic Mouse (1st generation)"
        case .magicMouse2: return "Magic Mouse 2"
        case .magicMouseUSBC: return "Magic Mouse (USB-C)"
        case .unknownMagicMouse: return "Magic Mouse"
        }
    }
}

public struct DeviceInfo: Codable, Sendable, Equatable, Identifiable {
    /// Stable across reconnects (serial number / Bluetooth address when available).
    public var id: String
    public var name: String
    public var model: MagicMouseModel
    public var vendorID: Int
    public var productID: Int
    /// "Bluetooth", "USB", …
    public var transport: String
    public var batteryPercent: Int?
    public var isConnected: Bool
    public var surface: SurfaceGeometry

    public init(id: String, name: String, model: MagicMouseModel, vendorID: Int, productID: Int, transport: String,
                batteryPercent: Int? = nil, isConnected: Bool = true, surface: SurfaceGeometry = .magicMouse) {
        self.id = id; self.name = name; self.model = model; self.vendorID = vendorID; self.productID = productID
        self.transport = transport; self.batteryPercent = batteryPercent; self.isConnected = isConnected
        self.surface = surface
    }
}

/// Watches for Magic Mouse connect / disconnect. Callbacks arrive on the main queue.
public protocol DeviceMonitoring: AnyObject {
    var devices: [DeviceInfo] { get }
    func start(onChange: @escaping ([DeviceInfo]) -> Void)
    func stop()
}

public enum AdapterAvailability: Equatable, Sendable {
    case available
    /// e.g. private framework missing, symbol lookup failed, no multitouch device present.
    case unavailable(reason: String)
}

public enum AdapterError: Error, Equatable, Sendable {
    case unavailable(String)
    case noDevice
    case startFailed(String)
}

/// Source of touch frames. Exactly one adapter is active at a time.
public protocol TouchInputAdapter: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    /// True when the adapter relies on private / unsupported system interfaces.
    var usesPrivateAPI: Bool { get }
    var capabilities: InputCapabilities { get }
    /// Cheap runtime check; must not start any device streams or trigger permission prompts.
    func checkAvailability() -> AdapterAvailability
    /// Starts streaming. `onFrame` is called on an adapter-owned thread, in timestamp order.
    func start(onFrame: @escaping (TouchFrame) -> Void) throws
    /// Stops streaming and releases every device handle. Safe to call repeatedly.
    func stop()
    /// Devices changed (connect / disconnect); re-enumerate and keep streaming if possible.
    func devicesDidChange()
}

public extension TouchInputAdapter {
    func devicesDidChange() {}
}

/// Scroll event handed to the engine by the event tap for Smart Scroll.
public struct ScrollSample: Sendable, Equatable {
    public var deltaX: Double
    public var deltaY: Double
    /// Pixel-precise (continuous) deltas, as produced by Magic Mouse and trackpads.
    public var isContinuous: Bool
    /// The event tap's best determination that the event came from a Magic Mouse.
    public var isFromMagicMouse: Bool
    /// Momentum (inertial) phase event.
    public var isMomentum: Bool
    public var timestamp: TimeInterval
    public init(deltaX: Double, deltaY: Double, isContinuous: Bool, isFromMagicMouse: Bool, isMomentum: Bool = false,
                timestamp: TimeInterval) {
        self.deltaX = deltaX; self.deltaY = deltaY; self.isContinuous = isContinuous
        self.isFromMagicMouse = isFromMagicMouse; self.isMomentum = isMomentum; self.timestamp = timestamp
    }
}

public enum ScrollDecision: Sendable, Equatable {
    /// Leave the event exactly as it is (the default).
    case passThrough
    /// Rewrite the event's deltas in place (never post an additional event).
    case rewrite(deltaX: Double, deltaY: Double)
}

/// Callbacks from the global event tap. Every closure runs synchronously on the tap thread and
/// must return quickly.
public struct PointerEventHandlers {
    /// Physical button transition (`isDown`) for button number 0 = left, 1 = right, 2 = middle.
    public var onButton: (_ button: Int, _ isDown: Bool, _ timestamp: TimeInterval) -> Void
    /// Decide how to treat a scroll event.
    public var onScroll: (_ sample: ScrollSample) -> ScrollDecision
    /// A fallback chord trigger fired (`GestureKind` of category `.fallback`). Return true to
    /// swallow the originating event.
    public var onChord: (_ kind: GestureKind, _ timestamp: TimeInterval) -> Bool
    /// A global hot key registered with `registerHotKeys` fired.
    public var onHotKey: (_ identifier: UUID) -> Void

    public init(onButton: @escaping (Int, Bool, TimeInterval) -> Void,
                onScroll: @escaping (ScrollSample) -> ScrollDecision,
                onChord: @escaping (GestureKind, TimeInterval) -> Bool,
                onHotKey: @escaping (UUID) -> Void) {
        self.onButton = onButton; self.onScroll = onScroll; self.onChord = onChord; self.onHotKey = onHotKey
    }
}

/// Global pointer event source (CGEventTap on macOS). Requires Accessibility permission.
public protocol PointerEventSource: AnyObject {
    var isRunning: Bool { get }
    /// Returns false (without prompting) when the tap cannot be created, e.g. permission missing.
    func start(handlers: PointerEventHandlers) -> Bool
    func stop()
    /// Which fallback chords should be detected (and swallowed).
    func setEnabledChords(_ kinds: Set<GestureKind>)
    /// Whether scroll events need to be delivered to `onScroll` at all (skip work when Smart Scroll is off).
    func setScrollInterceptionEnabled(_ enabled: Bool)
    /// Replace the registered global hot keys.
    func registerHotKeys(_ hotKeys: [UUID: KeyCombo])
}

public protocol PermissionsProviding: AnyObject {
    /// Never prompts.
    func status(of kind: PermissionKind) -> PermissionStatus
    /// Shows the system prompt at most once per kind per launch; later calls are no-ops.
    func request(_ kind: PermissionKind)
    func openSystemSettings(for kind: PermissionKind)
}

public struct RunningApp: Sendable, Equatable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

public protocol FrontmostAppProviding: AnyObject {
    var frontmostBundleID: String? { get }
    var runningApps: [RunningApp] { get }
    /// `handler` is called on the main queue whenever the frontmost app changes.
    func startObserving(_ handler: @escaping (String?) -> Void)
    func stopObserving()
}

/// Access to the user's text, only ever invoked by an explicit user-triggered action.
public protocol TextAccessProviding: AnyObject {
    func clipboardString() -> String?
    func setClipboardString(_ string: String)
    /// Copies the current selection of the frontmost app (synthetic ⌘C), returns it and restores
    /// the previous clipboard contents.
    func selectedText() async -> String?
}

public protocol SecretStoring: AnyObject {
    func secret(for account: String) throws -> String?
    func setSecret(_ value: String?, for account: String) throws
}

public protocol UserNotifying: AnyObject {
    func notify(title: String, body: String)
}

/// Presents the floating radial menu at the cursor and resolves with the chosen item, or nil
/// when dismissed.
public protocol RadialMenuPresenting: AnyObject {
    @MainActor func present(_ menu: RadialMenu, recent: [RadialMenuItem]) async -> RadialMenuItem?
    @MainActor func dismiss()
}

public struct AIRequest: Sendable, Equatable {
    public var baseURL: String
    public var model: String
    public var systemPrompt: String
    public var userPrompt: String
    public var timeout: Double
    public init(baseURL: String, model: String, systemPrompt: String, userPrompt: String, timeout: Double) {
        self.baseURL = baseURL; self.model = model; self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt; self.timeout = timeout
    }
}

public enum AIError: Error, Equatable, Sendable {
    case disabled, notConfigured(String), missingAPIKey, invalidURL, http(status: Int, message: String)
    case timedOut, badResponse(String), cancelled, noInput, declinedByUser
}

/// OpenAI-compatible chat completion client.
public protocol AICompleting: Sendable {
    func complete(_ request: AIRequest, apiKey: String) async throws -> String
}

/// UI hooks for the AI flow: consent before sending, preview before using the result.
public protocol AIInteractionPresenting: AnyObject {
    /// Shows exactly what will be sent and where; returns false when the user declines.
    @MainActor func confirmSend(text: String, template: PromptTemplate, endpoint: String) async -> Bool
    /// Shows the result; the user chooses what to do with it.
    @MainActor func presentResult(_ result: String, template: PromptTemplate) async -> AIResultChoice
}

public enum AIResultChoice: Sendable, Equatable { case copy, paste, dismiss }

public protocol ConfigurationStoring: AnyObject {
    /// Returns nil when nothing has been saved yet. Throws on unreadable / corrupt data.
    func load() throws -> Configuration?
    func save(_ configuration: Configuration) throws
    /// Where the configuration lives (for the "reveal in Finder" button), if file based.
    var location: URL? { get }
}

/// Everything the engine needs from the outside world.
public struct Services {
    /// In order of preference; the first available adapter is used.
    public var adapters: [TouchInputAdapter]
    public var deviceMonitor: DeviceMonitoring
    public var permissions: PermissionsProviding
    public var frontmostApp: FrontmostAppProviding
    public var performer: ActionPerforming
    public var pointerEvents: PointerEventSource?
    public var textAccess: TextAccessProviding
    public var secrets: SecretStoring
    public var notifier: UserNotifying?
    public var radialMenu: RadialMenuPresenting?
    public var ai: AICompleting
    public var aiPresenter: AIInteractionPresenting?
    public var store: ConfigurationStoring
    /// Opens / focuses the main window (set by the app).
    public var openDashboard: (@MainActor () -> Void)?

    public init(adapters: [TouchInputAdapter], deviceMonitor: DeviceMonitoring, permissions: PermissionsProviding,
                frontmostApp: FrontmostAppProviding, performer: ActionPerforming, pointerEvents: PointerEventSource?,
                textAccess: TextAccessProviding, secrets: SecretStoring, notifier: UserNotifying?,
                radialMenu: RadialMenuPresenting?, ai: AICompleting, aiPresenter: AIInteractionPresenting?,
                store: ConfigurationStoring, openDashboard: (@MainActor () -> Void)? = nil) {
        self.adapters = adapters; self.deviceMonitor = deviceMonitor; self.permissions = permissions
        self.frontmostApp = frontmostApp; self.performer = performer; self.pointerEvents = pointerEvents
        self.textAccess = textAccess; self.secrets = secrets; self.notifier = notifier; self.radialMenu = radialMenu
        self.ai = ai; self.aiPresenter = aiPresenter; self.store = store; self.openDashboard = openDashboard
    }
}
