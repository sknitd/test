import ApplicationServices
import CoreGraphics
import Foundation

/// Thin, typed wrappers around the C Accessibility (AXUIElement) API.
enum AX {
    /// Upper bound for a single Accessibility call to an unresponsive application, in seconds.
    static let messagingTimeout: Float = 1.0

    static func application(pid: pid_t) -> AXUIElement {
        let element: AXUIElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func systemWide() -> AXUIElement {
        let element: AXUIElement = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error: AXError = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        // Safe: the Core Foundation type identifier was checked on the line above.
        return (raw as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // Safe: the Core Foundation type identifier was checked on the line above.
        let boxed = raw as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(boxed, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // Safe: the Core Foundation type identifier was checked on the line above.
        let boxed = raw as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(boxed, .cgSize, &size) else { return nil }
        return size
    }

    static func set(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> AXError {
        var mutablePoint = point
        guard let boxed: AXValue = AXValueCreate(.cgPoint, &mutablePoint) else { return .failure }
        return AXUIElementSetAttributeValue(element, attribute as CFString, boxed)
    }

    static func set(_ element: AXUIElement, _ attribute: String, size: CGSize) -> AXError {
        var mutableSize = size
        guard let boxed: AXValue = AXValueCreate(.cgSize, &mutableSize) else { return .failure }
        return AXUIElementSetAttributeValue(element, attribute as CFString, boxed)
    }

    static func set(_ element: AXUIElement, _ attribute: String, bool: Bool) -> AXError {
        // A Boolean NSNumber is toll-free bridged to CFBoolean.
        let boxed: CFTypeRef = NSNumber(value: bool)
        return AXUIElementSetAttributeValue(element, attribute as CFString, boxed)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let error: AXError = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// Short human-readable explanation for the errors users actually run into.
    static func describe(_ error: AXError) -> String {
        switch error {
        case .success: return "no error"
        case .apiDisabled: return "Accessibility access is not enabled for MagicForge"
        case .cannotComplete: return "the application did not respond"
        case .attributeUnsupported: return "the window does not support this"
        case .actionUnsupported: return "the window does not support this action"
        case .notImplemented: return "the application does not support Accessibility control"
        case .invalidUIElement: return "the window no longer exists"
        case .illegalArgument: return "the application rejected the value"
        default: return "Accessibility error \(error.rawValue)"
        }
    }
}
