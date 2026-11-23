import CoreFoundation
import Foundation

/// Configuration shared between `EventTapPointerSource` (any thread) and the tap thread.
struct EventTapConfiguration {
    var handlers: PointerEventHandlers?
    var enabledChords: Set<GestureKind> = []
    var scrollInterceptionEnabled = false
    var hotKeys: [UUID: KeyCombo] = [:]
    var magicMouseActivityProbe: (() -> Bool)?
    var assumeContinuousScrollIsMagicMouse = false
}

/// Pure helpers used by the tap callback.
enum EventTapLogic {
    /// `eventSourceUserData` value ("MFORGE") that marks events posted by MagicForge itself.
    /// MFActions hard-codes the same number when it synthesizes events.
    static let syntheticEventUserData: Int64 = 0x4D46_4F52_4745

    static let chordScrollKinds: Set<GestureKind> = [.chordScrollUp, .chordScrollDown, .chordScrollLeft,
                                                     .chordScrollRight]

    /// Control+Option held, Command and Shift not held.
    static func isChordModifierState(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskControl) && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand) && !flags.contains(.maskShift)
    }

    /// Positive vertical deltas are "scroll up"; positive horizontal deltas are "scroll left"
    /// (the sign convention of scroll-wheel events, after the system's natural-scrolling setting).
    static func chordScrollKind(deltaX: Double, deltaY: Double) -> GestureKind? {
        if deltaX == 0 && deltaY == 0 { return nil }
        if abs(deltaY) >= abs(deltaX) { return deltaY > 0 ? .chordScrollUp : .chordScrollDown }
        return deltaX > 0 ? .chordScrollLeft : .chordScrollRight
    }

    /// Command, Option, Control and Shift must match exactly. The Fn flag is only required when
    /// the combo asks for it; it is otherwise ignored because arrow and function keys always set it.
    static func matches(_ combo: KeyCombo, keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard combo.keyCode == keyCode else { return false }
        if combo.command != flags.contains(.maskCommand) { return false }
        if combo.option != flags.contains(.maskAlternate) { return false }
        if combo.control != flags.contains(.maskControl) { return false }
        if combo.shift != flags.contains(.maskShift) { return false }
        if combo.function && !flags.contains(.maskSecondaryFn) { return false }
        return true
    }

    static func hotKey(for keyCode: UInt16, flags: CGEventFlags, in hotKeys: [UUID: KeyCombo]) -> UUID? {
        var best: UUID?
        for (identifier, combo) in hotKeys where matches(combo, keyCode: keyCode, flags: flags) {
            if let current = best {
                if identifier.uuidString < current.uuidString { best = identifier }
            } else {
                best = identifier
            }
        }
        return best
    }

    static var eventMask: CGEventMask {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel, .keyDown, .keyUp]
        var mask: CGEventMask = 0
        for type in types { mask |= CGEventMask(1) << CGEventMask(type.rawValue) }
        return mask
    }
}
