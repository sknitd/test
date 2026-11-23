import AppKit
import ApplicationServices
import Foundation
import MFCore
import MFUtilities

/// Clipboard access and "read the current selection" for explicit, user-triggered actions.
/// Text is never logged.
public final class PasteboardTextAccess: TextAccessProviding {
    /// How long to wait for the frontmost app to answer the synthetic ⌘C.
    private static let copyWait: TimeInterval = 0.3
    private static let pollInterval: TimeInterval = 0.02

    private let keyboard = KeyboardExecutor()
    private let log = Log("actions.text")

    public init() {}

    public func clipboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    public func setClipboardString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// The frontmost app's selected text, or nil when there is none or it cannot be read.
    ///
    /// 1. Asks the focused UI element for `kAXSelectedTextAttribute` (no clipboard involved).
    /// 2. Otherwise posts ⌘C, waits up to 300 ms for the clipboard to change, reads it and puts
    ///    the previous clipboard contents back.
    ///
    /// Both paths need Accessibility; without it this returns nil and never prompts.
    public func selectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            log.info("Selection unavailable: Accessibility permission missing")
            return nil
        }
        if let text = PasteboardTextAccess.selectedTextViaAccessibility(), !text.isEmpty {
            return text
        }
        return await selectedTextViaCopy()
    }

    private static func selectedTextViaAccessibility() -> String? {
        guard let focused = AX.element(AX.systemWide(), kAXFocusedUIElementAttribute as String) else { return nil }
        _ = AXUIElementSetMessagingTimeout(focused, AX.messagingTimeout)
        return AX.string(focused, kAXSelectedTextAttribute as String)
    }

    private func selectedTextViaCopy() async -> String? {
        let before: (snapshot: PasteboardSnapshot, changeCount: Int) = await MainActor.run {
            (snapshot: PasteboardSnapshot.capture(), changeCount: NSPasteboard.general.changeCount)
        }
        do {
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.c, command: true))
        } catch {
            log.error("Could not post the copy shortcut")
            return nil
        }

        var copied: String?
        var didChange = false
        let attempts = Int((PasteboardTextAccess.copyWait / PasteboardTextAccess.pollInterval).rounded(.up))
        for _ in 0..<attempts {
            await SyntheticEvents.gap(PasteboardTextAccess.pollInterval)
            let changeCount: Int = await MainActor.run { NSPasteboard.general.changeCount }
            if changeCount != before.changeCount {
                didChange = true
                break
            }
        }
        if didChange {
            let snapshot = before.snapshot
            copied = await MainActor.run {
                let text: String? = NSPasteboard.general.string(forType: .string)
                snapshot.restore()
                return text
            }
        }
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }
}
