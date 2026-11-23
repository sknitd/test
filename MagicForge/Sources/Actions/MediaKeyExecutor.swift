import AppKit
import CoreGraphics
import Foundation
import MFCore

/// Posts the "special" (NX system-defined) keys found on Apple keyboards: volume, brightness and
/// media transport. These are the same events the keyboard's own media keys generate, so the
/// system shows its usual volume / brightness HUD. Requires Accessibility.
enum MediaKey: Int {
    // NX_KEYTYPE_* values from <IOKit/hidsystem/ev_keymap.h>, defined locally on purpose.
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
}

struct MediaKeyExecutor: Sendable {
    /// NSEvent subtype for auxiliary control buttons (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    private static let auxControlButtonsSubtype: Int16 = 8

    func press(_ key: MediaKey) async throws {
        try await MainActor.run { try MediaKeyExecutor.post(key, isDown: true) }
        await SyntheticEvents.gap(0.012)
        try await MainActor.run { try MediaKeyExecutor.post(key, isDown: false) }
    }

    @MainActor
    private static func post(_ key: MediaKey, isDown: Bool) throws {
        // data1 layout: key code in bits 16…31, key state (0xA = down, 0xB = up) in bits 8…15.
        let state: Int = isDown ? 0xA : 0xB
        let data1: Int = (key.rawValue << 16) | (state << 8)
        let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
        let created: NSEvent? = NSEvent.otherEvent(with: .systemDefined, location: NSPoint.zero, modifierFlags: flags,
                                                   timestamp: 0, windowNumber: 0, context: nil,
                                                   subtype: auxControlButtonsSubtype, data1: data1, data2: -1)
        guard let event = created, let cgEvent = event.cgEvent else {
            throw ActionError.failed("Could not create the media key event.")
        }
        SyntheticEvents.post(cgEvent)
    }
}
