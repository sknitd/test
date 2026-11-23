import Foundation

/// macOS virtual key codes (the `kVK_*` constants from Carbon's HIToolbox `Events.h`).
/// The `kVK_ANSI_*` codes describe key positions on an ANSI US layout.
public enum KeyCodes {
    // Letters
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let x: UInt16 = 0x07
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let b: UInt16 = 0x0B
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let y: UInt16 = 0x10
    public static let t: UInt16 = 0x11
    public static let o: UInt16 = 0x1F
    public static let u: UInt16 = 0x20
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E

    // Digits (top row)
    public static let one: UInt16 = 0x12
    public static let two: UInt16 = 0x13
    public static let three: UInt16 = 0x14
    public static let four: UInt16 = 0x15
    public static let six: UInt16 = 0x16
    public static let five: UInt16 = 0x17
    public static let nine: UInt16 = 0x19
    public static let seven: UInt16 = 0x1A
    public static let eight: UInt16 = 0x1C
    public static let zero: UInt16 = 0x1D

    // Punctuation
    public static let equal: UInt16 = 0x18
    public static let minus: UInt16 = 0x1B
    public static let rightBracket: UInt16 = 0x1E
    public static let leftBracket: UInt16 = 0x21
    public static let quote: UInt16 = 0x27
    public static let semicolon: UInt16 = 0x29
    public static let backslash: UInt16 = 0x2A
    public static let comma: UInt16 = 0x2B
    public static let slash: UInt16 = 0x2C
    public static let period: UInt16 = 0x2F
    public static let grave: UInt16 = 0x32

    // Editing and whitespace
    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    /// Backspace (⌫).
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let forwardDelete: UInt16 = 0x75

    // Function keys
    public static let f1: UInt16 = 0x7A
    public static let f2: UInt16 = 0x78
    public static let f3: UInt16 = 0x63
    public static let f4: UInt16 = 0x76
    public static let f5: UInt16 = 0x60
    public static let f6: UInt16 = 0x61
    public static let f7: UInt16 = 0x62
    public static let f8: UInt16 = 0x64
    public static let f9: UInt16 = 0x65
    public static let f10: UInt16 = 0x6D
    public static let f11: UInt16 = 0x67
    public static let f12: UInt16 = 0x6F

    // Navigation
    public static let home: UInt16 = 0x73
    public static let pageUp: UInt16 = 0x74
    public static let end: UInt16 = 0x77
    public static let pageDown: UInt16 = 0x79
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E

    public static let letters: [UInt16] = [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z]
    public static let digits: [UInt16] = [zero, one, two, three, four, five, six, seven, eight, nine]
    public static let functionKeys: [UInt16] = [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12]
    public static let arrows: [UInt16] = [leftArrow, rightArrow, upArrow, downArrow]
}

/// Human readable names for virtual key codes, as printed on an ANSI US keyboard.
public enum KeyCodeNames {
    private static let names: [UInt16: String] = {
        var table: [UInt16: String] = [
            KeyCodes.equal: "=", KeyCodes.minus: "-", KeyCodes.rightBracket: "]", KeyCodes.leftBracket: "[",
            KeyCodes.quote: "'", KeyCodes.semicolon: ";", KeyCodes.backslash: "\\", KeyCodes.comma: ",",
            KeyCodes.slash: "/", KeyCodes.period: ".", KeyCodes.grave: "`",
            KeyCodes.returnKey: "↩", KeyCodes.tab: "⇥", KeyCodes.space: "Space", KeyCodes.delete: "⌫",
            KeyCodes.escape: "⎋", KeyCodes.forwardDelete: "⌦",
            KeyCodes.home: "Home", KeyCodes.end: "End", KeyCodes.pageUp: "Page Up", KeyCodes.pageDown: "Page Down",
            KeyCodes.leftArrow: "←", KeyCodes.rightArrow: "→", KeyCodes.upArrow: "↑", KeyCodes.downArrow: "↓",
        ]
        let alphabet: [String] = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q",
                                  "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        for (code, letter) in zip(KeyCodes.letters, alphabet) { table[code] = letter }
        for (index, code) in KeyCodes.digits.enumerated() { table[code] = String(index) }
        for (index, code) in KeyCodes.functionKeys.enumerated() { table[code] = "F\(index + 1)" }
        return table
    }()

    /// Name of the key, or "Key 0x…" for codes MagicForge has no name for.
    public static func name(for keyCode: UInt16) -> String {
        if let name = names[keyCode] { return name }
        let hex = String(keyCode, radix: 16, uppercase: true)
        return "Key 0x" + (hex.count < 2 ? "0" + hex : hex)
    }

    /// True when MagicForge has a proper name for the code.
    public static func isKnown(_ keyCode: UInt16) -> Bool { names[keyCode] != nil }

    /// Keys that always carry the Fn flag in real key events (function, arrow and navigation keys).
    public static func impliesFunctionFlag(_ keyCode: UInt16) -> Bool {
        KeyCodes.functionKeys.contains(keyCode) || KeyCodes.arrows.contains(keyCode)
            || [KeyCodes.home, KeyCodes.end, KeyCodes.pageUp, KeyCodes.pageDown, KeyCodes.forwardDelete].contains(keyCode)
    }
}

public extension KeyCombo {
    /// Modifier glyphs in the standard macOS order (⌃⌥⇧⌘).
    var modifierString: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text
    }

    /// e.g. "⌃⌥⇧⌘K", derived from `keyCode` and the modifier flags (never from `label`).
    /// "fn" is only shown for keys that do not carry the Fn flag implicitly.
    var displayString: String {
        let fn = function && !KeyCodeNames.impliesFunctionFlag(keyCode) ? "fn" : ""
        return fn + modifierString + KeyCodeNames.name(for: keyCode)
    }

    var hasModifiers: Bool { command || option || control || shift }
}
