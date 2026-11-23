import CoreGraphics
import Foundation
import MFCore

/// Marker written into the `eventSourceUserData` field of every CGEvent MagicForge posts, so that
/// MagicForge's own event tap (MFInput) can recognise and ignore them. The input module
/// hard-codes the same constant ("MFORGE" in ASCII).
public enum SyntheticEventMarker {
    public static let userData: Int64 = 0x4D46_4F52_4745
}

/// Shared helpers for creating and posting synthetic Quartz events.
enum SyntheticEvents {
    /// A fresh event source that mirrors the hardware state.
    static func makeSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.failed("Could not create an event source for synthetic input.")
        }
        // Do not freeze real pointer / keyboard input after posting.
        source.localEventsSuppressionInterval = 0
        return source
    }

    /// Tags the event as MagicForge-generated and posts it at the HID level.
    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.userData)
        event.post(tap: .cghidEventTap)
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == SyntheticEventMarker.userData
    }

    /// Current pointer location in global display coordinates (top-left origin).
    static func pointerLocation() throws -> CGPoint {
        guard let probe = CGEvent(source: nil) else {
            throw ActionError.failed("Could not read the pointer location.")
        }
        return probe.location
    }

    /// Short gap between the halves of a synthetic press. Deliberately ignores cancellation so
    /// that a "down" event is always followed by its "up" event.
    static func gap(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// macOS virtual key codes (kVK_*) used by the built-in actions.
enum VirtualKey {
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let q: UInt16 = 12
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let space: UInt16 = 49
}
