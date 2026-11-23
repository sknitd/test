import AppKit
import Foundation
import MFCore

/// Frontmost / running application information from NSWorkspace.
/// Use from the main thread (the observer callback is delivered on the main queue).
public final class WorkspaceAppProvider: FrontmostAppProviding {
    private var observer: NSObjectProtocol?

    public init() {}

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    public var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Apps with a Dock icon (regular activation policy) that have a bundle identifier, sorted by name.
    public var runningApps: [RunningApp] {
        var seen = Set<String>()
        var apps: [RunningApp] = []
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            guard let bundleID = application.bundleIdentifier, seen.insert(bundleID).inserted else { continue }
            apps.append(RunningApp(bundleID: bundleID, name: application.localizedName ?? bundleID))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func startObserving(_ handler: @escaping (String?) -> Void) {
        stopObserving()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: OperationQueue.main
        ) { notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            handler(activated?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
    }

    public func stopObserving() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
