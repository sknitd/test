import Foundation
import MFCore
import MFUtilities
import UserNotifications

/// Posts user notifications through UNUserNotificationCenter.
///
/// Authorization is requested lazily on the first `notify`. `UNUserNotificationCenter.current()`
/// raises an exception in a process without an application bundle (plain `swift run`), so in
/// that case notifications are only written to the log.
public final class UserNotificationNotifier: UserNotifying, @unchecked Sendable {
    private let log = Log("notifications")
    /// Shows banners even while MagicForge is the active application. Immutable after init.
    private let presenter = ForegroundPresenter()

    public init() {}

    /// True when the process runs from a real .app bundle with a bundle identifier.
    public static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    public func notify(title: String, body: String) {
        guard UserNotificationNotifier.isSupported else {
            log.notice("Notification not shown (not running from an app bundle): \(title)")
            return
        }
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let log = self.log
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("Notification authorization failed: \(error.localizedDescription)")
                return
            }
            guard granted else {
                log.info("Notifications are not allowed for MagicForge")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    log.error("Could not deliver notification: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// Delegate that lets notifications appear while the app is frontmost.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
