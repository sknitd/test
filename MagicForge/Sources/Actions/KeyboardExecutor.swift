import CoreGraphics
import Foundation
import MFCore

/// Posts keyboard shortcuts as synthetic key-down / key-up pairs. Requires Accessibility.
struct KeyboardExecutor: Sendable {
    static func flags(for combo: KeyCombo) -> CGEventFlags {
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        if combo.shift { flags.insert(.maskShift) }
        if combo.function { flags.insert(.maskSecondaryFn) }
        return flags
    }

    /// Presses and releases the shortcut once.
    func press(_ combo: KeyCombo) async throws {
        let source: CGEventSource = try SyntheticEvents.makeSource()
        let keyCode = CGKeyCode(combo.keyCode)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ActionError.failed("Could not create the keyboard event.")
        }
        let flags = KeyboardExecutor.flags(for: combo)
        down.flags = flags
        up.flags = flags
        SyntheticEvents.post(down)
        await SyntheticEvents.gap(0.012)
        SyntheticEvents.post(up)
    }
}
