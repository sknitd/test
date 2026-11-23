import Foundation
import XCTest
import MFCore
import MFUtilities
import MFGestures
import MFProfiles
@testable import MFEngine

// MARK: - Mocks

final class MockAdapter: TouchInputAdapter, @unchecked Sendable {
    let identifier: String
    let displayName: String
    let usesPrivateAPI: Bool
    var capabilities = InputCapabilities(rawContacts: true, maxContacts: 5, contactSize: true, pointerEvents: false)
    var availability: AdapterAvailability = .available
    var startError: AdapterError?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var devicesDidChangeCount = 0
    private let handler = Locked<((TouchFrame) -> Void)?>(nil)

    init(identifier: String = "mock", displayName: String = "Mock Adapter", usesPrivateAPI: Bool = false) {
        self.identifier = identifier; self.displayName = displayName; self.usesPrivateAPI = usesPrivateAPI
    }

    var isStarted: Bool { handler.current != nil }

    func checkAvailability() -> AdapterAvailability { availability }

    func start(onFrame: @escaping (TouchFrame) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        handler.withLock { $0 = onFrame }
    }

    func stop() {
        stopCount += 1
        handler.withLock { $0 = nil }
    }

    func devicesDidChange() { devicesDidChangeCount += 1 }

    func push(_ frame: TouchFrame) { handler.current?(frame) }
    func push(_ frames: [TouchFrame]) { for frame in frames { push(frame) } }
}

final class MockDeviceMonitor: DeviceMonitoring {
    private(set) var devices: [DeviceInfo]
    private var onChange: (([DeviceInfo]) -> Void)?
    private(set) var isStarted = false

    init(devices: [DeviceInfo]) { self.devices = devices }

    func start(onChange: @escaping ([DeviceInfo]) -> Void) { self.onChange = onChange; isStarted = true }
    func stop() { onChange = nil; isStarted = false }

    func set(_ devices: [DeviceInfo]) {
        self.devices = devices
        onChange?(devices)
    }
}

final class MockPermissions: PermissionsProviding {
    var statuses: [PermissionKind: PermissionStatus] = [.accessibility: .granted, .inputMonitoring: .notRequired,
                                                        .automation: .notDetermined]
    private(set) var requested: [PermissionKind] = []
    private(set) var openedSettings: [PermissionKind] = []
    func status(of kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .notDetermined }
    func request(_ kind: PermissionKind) { requested.append(kind) }
    func openSystemSettings(for kind: PermissionKind) { openedSettings.append(kind) }
}

final class MockFrontmostApp: FrontmostAppProviding {
    private(set) var frontmostBundleID: String?
    var runningApps: [RunningApp] = []
    private var handler: ((String?) -> Void)?
    private(set) var isObserving = false

    func startObserving(_ handler: @escaping (String?) -> Void) { self.handler = handler; isObserving = true }
    func stopObserving() { handler = nil; isObserving = false }

    func activate(_ bundleID: String?) {
        frontmostBundleID = bundleID
        handler?(bundleID)
    }
}

final class RecordingPerformer: ActionPerforming, @unchecked Sendable {
    private let recorded = Locked<[Action]>([])
    private let failure = Locked<ActionError?>(nil)
    private let delay = Locked<TimeInterval>(0)

    var performed: [Action] { recorded.current }
    var error: ActionError? {
        get { failure.current }
        set { failure.withLock { $0 = newValue } }
    }
    /// Seconds each action takes.
    var duration: TimeInterval {
        get { delay.current }
        set { delay.withLock { $0 = newValue } }
    }

    func perform(_ action: Action, context: ActionContext) async throws {
        let wait = delay.current
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        if let error = failure.current { throw error }
        recorded.withLock { $0.append(action) }
    }

    func availability(of action: Action) -> ActionAvailability { .available }
}

final class MockPointerSource: PointerEventSource {
    var canStart = true
    private(set) var handlers: PointerEventHandlers?
    private(set) var enabledChords: Set<GestureKind> = []
    private(set) var scrollInterceptionEnabled = false
    private(set) var hotKeys: [UUID: KeyCombo] = [:]
    private(set) var startAttempts = 0

    var isRunning: Bool { handlers != nil }

    func start(handlers: PointerEventHandlers) -> Bool {
        startAttempts += 1
        guard canStart else { return false }
        self.handlers = handlers
        return true
    }

    func stop() { handlers = nil }
    func setEnabledChords(_ kinds: Set<GestureKind>) { enabledChords = kinds }
    func setScrollInterceptionEnabled(_ enabled: Bool) { scrollInterceptionEnabled = enabled }
    func registerHotKeys(_ hotKeys: [UUID: KeyCombo]) { self.hotKeys = hotKeys }
}

final class MockTextAccess: TextAccessProviding {
    var clipboard: String?
    var selection: String?
    private(set) var selectionReads = 0
    private(set) var clipboardReads = 0
    func clipboardString() -> String? { clipboardReads += 1; return clipboard }
    func setClipboardString(_ string: String) { clipboard = string }
    func selectedText() async -> String? { selectionReads += 1; return selection }
}

final class MockSecrets: SecretStoring {
    var values: [String: String] = [:]
    var error: Error?
    func secret(for account: String) throws -> String? {
        if let error { throw error }
        return values[account]
    }
    func setSecret(_ value: String?, for account: String) throws {
        if let error { throw error }
        values[account] = value
    }
}

final class MockNotifier: UserNotifying {
    private(set) var notifications: [(title: String, body: String)] = []
    func notify(title: String, body: String) { notifications.append((title, body)) }
}

final class MockAIClient: AICompleting, @unchecked Sendable {
    private let requests = Locked<[(request: AIRequest, apiKey: String)]>([])
    private let outcome = Locked<Result<String, AIError>>(.success("AI reply"))

    var calls: [(request: AIRequest, apiKey: String)] { requests.current }
    var result: Result<String, AIError> {
        get { outcome.current }
        set { outcome.withLock { $0 = newValue } }
    }

    func complete(_ request: AIRequest, apiKey: String) async throws -> String {
        requests.withLock { $0.append((request, apiKey)) }
        return try outcome.current.get()
    }
}

@MainActor
final class MockAIPresenter: AIInteractionPresenting {
    var allowSending = true
    var choice: AIResultChoice = .dismiss
    private(set) var confirmations: [(text: String, endpoint: String)] = []
    private(set) var presentedResults: [String] = []

    func confirmSend(text: String, template: PromptTemplate, endpoint: String) async -> Bool {
        confirmations.append((text, endpoint))
        return allowSending
    }

    func presentResult(_ result: String, template: PromptTemplate) async -> AIResultChoice {
        presentedResults.append(result)
        return choice
    }
}

@MainActor
final class MockRadialPresenter: RadialMenuPresenting {
    /// Picks the item to "click"; nil dismisses the menu.
    var choose: (RadialMenu, [RadialMenuItem]) -> RadialMenuItem? = { menu, _ in menu.items.first }
    private(set) var presented: [RadialMenu] = []
    private(set) var recents: [[RadialMenuItem]] = []
    private(set) var dismissCount = 0

    func present(_ menu: RadialMenu, recent: [RadialMenuItem]) async -> RadialMenuItem? {
        presented.append(menu)
        recents.append(recent)
        return choose(menu, recent)
    }

    func dismiss() { dismissCount += 1 }
}

final class MemoryStore: ConfigurationStoring {
    var stored: Configuration?
    var loadError: Error?
    var saveError: Error?
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    var location: URL? { nil }

    init(_ stored: Configuration? = nil) { self.stored = stored }

    func load() throws -> Configuration? {
        loadCount += 1
        if let loadError { throw loadError }
        return stored
    }

    func save(_ configuration: Configuration) throws {
        if let saveError { throw saveError }
        saveCount += 1
        stored = configuration
    }
}

// MARK: - Harness

@MainActor
final class Harness {
    let adapter: MockAdapter
    let extraAdapters: [MockAdapter]
    let monitor: MockDeviceMonitor
    let permissions = MockPermissions()
    let frontmost = MockFrontmostApp()
    let performer = RecordingPerformer()
    let pointer = MockPointerSource()
    let text = MockTextAccess()
    let secrets = MockSecrets()
    let notifier = MockNotifier()
    let radial = MockRadialPresenter()
    let ai = MockAIClient()
    let aiPresenter = MockAIPresenter()
    let store: ConfigurationStoring
    private(set) var dashboardOpenCount = 0
    private(set) var model: AppModel!

    var memoryStore: MemoryStore { store as! MemoryStore } // swiftlint:disable:this force_cast

    init(configuration: Configuration? = TestConfig.base(), store: ConfigurationStoring? = nil,
         adapter: MockAdapter = MockAdapter(), extraAdapters: [MockAdapter] = [],
         devices: [DeviceInfo] = [TestConfig.mouse], withPointerSource: Bool = true, withRadialPresenter: Bool = true,
         withAIPresenter: Bool = true) {
        self.adapter = adapter
        self.extraAdapters = extraAdapters
        self.monitor = MockDeviceMonitor(devices: devices)
        self.store = store ?? MemoryStore(configuration)
        model = makeModel(withPointerSource: withPointerSource, withRadialPresenter: withRadialPresenter,
                          withAIPresenter: withAIPresenter)
    }

    /// A second model on the same services, as after quitting and launching again.
    func makeModel(withPointerSource: Bool = true, withRadialPresenter: Bool = true,
                   withAIPresenter: Bool = true) -> AppModel {
        let services = Services(
            adapters: [adapter] + extraAdapters, deviceMonitor: monitor, permissions: permissions, frontmostApp: frontmost,
            performer: performer, pointerEvents: withPointerSource ? pointer : nil, textAccess: text, secrets: secrets,
            notifier: notifier, radialMenu: withRadialPresenter ? radial : nil, ai: ai,
            aiPresenter: withAIPresenter ? aiPresenter : nil, store: store,
            openDashboard: { [weak self] in self?.dashboardOpenCount += 1 })
        let model = AppModel(services: services)
        model.saveDebounce = 0.05
        return model
    }

    /// Pushes a complete synthetic gesture through the mock adapter, ending "now".
    func perform(_ kind: GestureKind) {
        adapter.push(TestFrames.gesture(kind))
    }

    /// Waits (without blocking the main actor) until `condition` holds.
    @discardableResult
    func wait(_ what: String = "condition", timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line,
              until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)", file: file, line: line)
                return false
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    /// Lets queued main-actor work and short timers run.
    func settle(_ seconds: TimeInterval = 0.15) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

enum TestFrames {
    /// Frames of one synthetic gesture, re-timed so the last frame is stamped "now".
    static func gesture(_ kind: GestureKind) -> [TouchFrame] {
        let frames = SyntheticTouch.frames(for: kind, startTime: 0)
        guard let last = frames.last else { return [] }
        let shift = MonotonicClock.now() - last.timestamp
        return frames.map { TouchFrame(timestamp: $0.timestamp + shift, deviceID: 7, contacts: $0.contacts) }
    }
}

enum TestConfig {
    static let mouse = DeviceInfo(id: "serial-123", name: "Test Mouse", model: .magicMouse2, vendorID: 0x05AC,
                                  productID: 0x0269, transport: "Bluetooth", batteryPercent: 80)
    static let appBundleID = "com.example.editor"
    static let keyA = Action.keyboard(KeyCombo(keyCode: 0, command: true, label: "⌘A"))
    static let keyB = Action.keyboard(KeyCombo(keyCode: 11, command: true, label: "⌘B"))
    static let keyC = Action.keyboard(KeyCombo(keyCode: 8, command: true, label: "⌘C"))

    /// Global profile: two-finger tap → ⌘A. App profile for `appBundleID`: two-finger tap → ⌘B.
    static func base() -> Configuration {
        var configuration = Configuration()
        let global = Profile(name: "Global", bindings: [
            GestureBinding(trigger: .single(.twoFingerTap), action: keyA),
        ])
        let app = Profile(name: "Editor", bundleIdentifiers: [appBundleID], bindings: [
            GestureBinding(trigger: .single(.twoFingerTap), action: keyB),
        ])
        configuration.profiles = [global, app]
        configuration.globalProfileID = global.id
        return configuration
    }

    static func with(_ bindings: [GestureBinding], mutate: (inout Configuration) -> Void = { _ in }) -> Configuration {
        var configuration = Configuration()
        let global = Profile(name: "Global", bindings: bindings)
        configuration.profiles = [global]
        configuration.globalProfileID = global.id
        mutate(&configuration)
        return configuration
    }
}
