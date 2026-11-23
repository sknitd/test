import SwiftUI
import AppKit
import MFCore
import MFEngine
import MFUI

/// The application: a single main window plus a menu bar extra.
///
/// Activation policy stays `.regular` (Dock icon) for the whole run. That keeps the app
/// reachable when the menu bar icon is hidden and avoids policy switching glitches.
///
/// The struct is deliberately not annotated `@MainActor`: `App`'s requirements carry their own
/// main-actor isolation in every supported SDK, and the explicit hops below are valid either way.
public struct MagicForgeApp: App {
    @NSApplicationDelegateAdaptor(MagicForgeAppDelegate.self) private var appDelegate

    private let root: CompositionRoot

    public init() {
        // App.init runs on the main thread during launch.
        self.root = MainActor.assumeIsolated { CompositionRoot.shared }
    }

    public var body: some Scene {
        Window("MagicForge", id: MagicForgeWindowID.main) {
            MainWindowRootView(root: root)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)

        MenuBarExtra("MagicForge", systemImage: "magicmouse.fill", isInserted: menuBarIconBinding) {
            MenuBarRootView(root: root)
        }
        .menuBarExtraStyle(.menu)
    }

    /// Reads the setting during scene evaluation so the scene updates when it changes; the
    /// setter also covers the user dragging the icon out of the menu bar.
    @MainActor private var menuBarIconBinding: Binding<Bool> {
        let model: AppModel = root.model
        let isShown: Bool = model.configuration.settings.showMenuBarIcon
        return Binding<Bool>(
            get: { isShown },
            set: { newValue in
                model.update { configuration in
                    configuration.settings.showMenuBarIcon = newValue
                }
            }
        )
    }
}

/// Main window content with its environment.
@MainActor
struct MainWindowRootView: View {
    let root: CompositionRoot
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainWindowView()
            .environment(root.model)
            .environment(root.navigation)
            .environment(\.mfConfigurationLocation, root.configurationLocation)
            .background(MainWindowAccessor(onWindow: { window in
                root.mainWindowDidAttach(window)
            }))
            .onAppear {
                root.registerOpenWindow(openWindow)
            }
    }
}

/// Menu bar content with its environment.
@MainActor
struct MenuBarRootView: View {
    let root: CompositionRoot
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Menu-style extras do not reliably deliver onAppear, so the action is captured here.
        let _ = root.registerOpenWindow(openWindow)
        MenuBarContentView()
            .environment(root.model)
            .environment(root.navigation)
    }
}

/// Reports the NSWindow hosting the main window's content.
struct MainWindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> MainWindowReportingView {
        let view = MainWindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: MainWindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }
}

final class MainWindowReportingView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            onWindow?(window)
        }
    }
}
