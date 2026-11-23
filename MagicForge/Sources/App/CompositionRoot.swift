import SwiftUI
import AppKit
import Observation
import MFCore
import MFUtilities
import MFEngine
import MFProfiles
import MFIntegrations
import MFDevices
import MFInput
import MFActions
import MFUI

/// Late-bound "open the main window" hook. `Services.openDashboard` has to exist before the
/// composition root has finished initialising, so it calls through this box.
@MainActor
final class DashboardOpener {
    var handler: (() -> Void)?
    func open() { handler?() }
}

/// The one place where concrete implementations are chosen and wired together.
///
/// Integration notes are marked `// WIRING:` at every spot that depends on details of modules
/// this file was written without seeing (it was first compiled on the macOS CI runner).
@MainActor
final class CompositionRoot {
    /// Shared by `MagicForgeApp` (scenes) and `MagicForgeAppDelegate` (lifecycle), which SwiftUI
    /// creates independently of each other.
    static let shared = CompositionRoot()

    let model: AppModel
    let navigation: NavigationState
    /// Where the configuration file lives; handed to the UI for "Reveal in Finder".
    let configurationLocation: URL?

    // Retained here as well as by `Services` so their lifetime is obvious.
    private let radialMenuController: RadialMenuController
    private let aiInteractionController: AIInteractionController
    private let dashboardOpener: DashboardOpener
    /// Kept to release a held drag lock when gestures are paused or the app quits
    /// (`ActionPerforming` has no hook for that, so the engine cannot do it).
    private let performer: SystemActionPerformer
    private var wasPaused: Bool = false

    private let log = Log("app")

    // MARK: Window bookkeeping

    private var openWindowAction: OpenWindowAction?
    private weak var mainWindow: NSWindow?
    private var hasStarted: Bool = false
    /// True once the "start minimized" decision has been made (or can no longer apply).
    private var hasAppliedLaunchVisibility: Bool = false

    // MARK: Construction

    private init() {
        // --- Persistence ---------------------------------------------------------------
        // WIRING: JSONConfigurationStore(directory:) and its static defaultDirectory are pinned
        // in the brief. `location` comes from ConfigurationStoring.
        let store = JSONConfigurationStore(directory: JSONConfigurationStore.defaultDirectory)

        // --- Input ---------------------------------------------------------------------
        // WIRING: adapters are tried in order; the private MultitouchSupport adapter is the only
        // touch adapter. If MFInput gains a public-API fallback adapter, append it here.
        let multitouchAdapter = MultitouchSupportAdapter()
        let pointerSource = EventTapPointerSource()
        // WIRING: scroll-origin heuristic. The adapter records when a finger was last on the Magic
        // Mouse (`MultitouchSupportAdapter.activity`); the event tap asks through
        // `EventTapPointerSource.magicMouseActivityProbe` (called on the tap thread). Without the
        // probe, `assumeContinuousScrollIsMagicMouse` (default false) decides instead.
        pointerSource.magicMouseActivityProbe = CompositionRoot.makeActivityProbe(multitouchAdapter.activity)
        let deviceMonitor = HIDDeviceMonitor()

        // --- System services -----------------------------------------------------------
        let permissions = SystemPermissions()
        // WIRING: SystemActionPerformer also offers init(permissions:scriptTimeout:) if the
        // default script timeout needs changing.
        let performer = SystemActionPerformer(permissions: permissions)
        let frontmostApp = WorkspaceAppProvider()
        let textAccess = PasteboardTextAccess()
        let notifier = UserNotificationNotifier()
        // WIRING: the Keychain service name must stay stable or saved API keys become invisible.
        let secrets = KeychainSecretStore(service: "com.magicforge.app")
        let aiClient = OpenAICompatibleClient()

        // --- UI-backed presenters --------------------------------------------------------
        // WIRING: both controllers are pinned as `public init()` in the brief; their sources were
        // not on disk when this file was written. If either needs the model or the animation
        // setting, inject it after `AppModel` is created below.
        let radialMenuController = RadialMenuController()
        let aiInteractionController = AIInteractionController()

        let dashboardOpener = DashboardOpener()

        let services = Services(
            adapters: [multitouchAdapter],
            deviceMonitor: deviceMonitor,
            permissions: permissions,
            frontmostApp: frontmostApp,
            performer: performer,
            pointerEvents: pointerSource,
            textAccess: textAccess,
            secrets: secrets,
            notifier: notifier,
            radialMenu: radialMenuController,
            ai: aiClient,
            aiPresenter: aiInteractionController,
            store: store,
            openDashboard: { dashboardOpener.open() }
        )

        self.model = AppModel(services: services)
        self.navigation = NavigationState()
        self.configurationLocation = store.location
        self.radialMenuController = radialMenuController
        self.aiInteractionController = aiInteractionController
        self.dashboardOpener = dashboardOpener
        self.performer = performer

        dashboardOpener.handler = { [weak self] in
            self?.showMainWindow()
        }
    }

    /// Built outside the main actor's isolation on purpose: the probe runs on the event tap thread.
    nonisolated private static func makeActivityProbe(_ activity: MagicMouseActivity) -> () -> Bool {
        return { activity.isActive() }
    }

    // MARK: Lifecycle (called by the app delegate)

    /// Starts the engine exactly once.
    func applicationDidFinishLaunching() {
        guard !hasStarted else { return }
        // WIRING: `model.start()` is expected to load the saved configuration synchronously, so
        // `startMinimized` is known right after it returns. If loading becomes asynchronous,
        // call `applyLaunchVisibilityIfReady()` when loading completes instead.
        model.start()
        hasStarted = true
        wasPaused = model.isPaused
        observePauseState()
        applyLaunchVisibilityIfReady()
        // The launch window normally attaches before or right after this callback. Stop waiting
        // after a moment so a window the user opens later is never closed by mistake.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.hasAppliedLaunchVisibility = true
        }
    }

    func applicationWillTerminate() {
        model.saveNow()
        model.stop()
        performer.releaseHeldInput()
    }

    /// Releases a held drag lock the moment gestures become paused, so a paused MagicForge never
    /// leaves the left mouse button logically down. Observation fires once per registration, so
    /// the tracking re-arms itself after every change.
    private func observePauseState() {
        withObservationTracking {
            _ = model.isPaused
        } onChange: { [weak self] in
            // `onChange` runs before the new value is stored; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                let paused: Bool = self.model.isPaused
                if paused && !self.wasPaused {
                    self.performer.releaseHeldInput()
                }
                self.wasPaused = paused
                self.observePauseState()
            }
        }
    }

    func applicationDidBecomeActive() {
        guard hasStarted else { return }
        model.refreshPermissions()
    }

    // MARK: Main window

    /// Remembers SwiftUI's window-opening action; it is the supported way to reopen a closed
    /// `Window` scene and is only available from inside a view.
    func registerOpenWindow(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    /// Called when the main window's content is attached to its NSWindow.
    func mainWindowDidAttach(_ window: NSWindow) {
        mainWindow = window
        applyLaunchVisibilityIfReady()
    }

    /// "Start minimized": SwiftUI always creates the `Window` scene's window at launch and has
    /// no scene-level switch to suppress it on macOS 14, so the launch window is closed as soon
    /// as both facts are known: the configuration is loaded and the window exists. The app keeps
    /// running (Dock icon and menu bar item); the window reopens from either.
    private func applyLaunchVisibilityIfReady() {
        guard hasStarted, !hasAppliedLaunchVisibility, let window = mainWindow else { return }
        hasAppliedLaunchVisibility = true
        guard model.configuration.settings.startMinimized else { return }
        log.info("Start minimized: closing the launch window")
        Task { @MainActor in
            window.close()
        }
    }

    /// Opens or focuses the main window. Used by `Services.openDashboard` and Dock reopen.
    func showMainWindow() {
        hasAppliedLaunchVisibility = true
        NSApp.activate(ignoringOtherApps: true)
        if let openWindowAction {
            openWindowAction(id: MagicForgeWindowID.main)
            return
        }
        // Fallback for the short time before any view has registered the open action.
        let existing: NSWindow? = mainWindow ?? NSApp.windows.first { window in
            window.identifier?.rawValue == MagicForgeWindowID.main
        }
        if let existing {
            existing.makeKeyAndOrderFront(nil)
        } else {
            log.error("Main window could not be opened: no open-window action registered yet")
        }
    }
}
