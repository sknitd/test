import AppKit

/// Application lifecycle. Created by SwiftUI through `@NSApplicationDelegateAdaptor`.
@MainActor
final class MagicForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CompositionRoot.shared.applicationDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CompositionRoot.shared.applicationWillTerminate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        CompositionRoot.shared.applicationDidBecomeActive()
    }

    /// MagicForge keeps recognizing gestures from the menu bar after its window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon (or reopening the app) with no visible window shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            CompositionRoot.shared.showMainWindow()
        }
        return true
    }
}
