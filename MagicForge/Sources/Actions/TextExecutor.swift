import AppKit
import Foundation
import MFCore

/// Clipboard and copy / paste actions. Copy, paste and paste-text post ⌘C / ⌘V and therefore
/// need Accessibility; copy-text only writes to the clipboard.
struct TextExecutor: Sendable {
    /// How long the pasted text stays on the clipboard before the previous contents come back.
    /// Long enough for the frontmost app to read the pasteboard in response to ⌘V.
    static let clipboardRestoreDelay: TimeInterval = 0.6

    private let keyboard = KeyboardExecutor()

    static func requiresEventPosting(_ action: TextAction) -> Bool {
        switch action {
        case .copy, .paste, .pasteText: return true
        case .copyText: return false
        }
    }

    func perform(_ action: TextAction) async throws {
        switch action {
        case .copy:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.c, command: true))
        case .paste:
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.v, command: true))
        case .copyText(let text):
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        case .pasteText(let text):
            try await paste(text)
        }
    }

    /// Puts `text` on the clipboard, presses ⌘V, then restores the previous clipboard contents
    /// (unless something else changed the clipboard in the meantime).
    private func paste(_ text: String) async throws {
        let borrowed: (snapshot: PasteboardSnapshot, changeCount: Int) = await MainActor.run {
            let snapshot = PasteboardSnapshot.capture()
            let changeCount = PasteboardSnapshot.setTransientString(text)
            return (snapshot: snapshot, changeCount: changeCount)
        }
        do {
            try await keyboard.press(KeyCombo(keyCode: VirtualKey.v, command: true))
        } catch {
            await TextExecutor.restore(borrowed.snapshot, ifChangeCountIs: borrowed.changeCount)
            throw error
        }
        // Restore even if the action's task is cancelled meanwhile.
        let snapshot = borrowed.snapshot
        let changeCount = borrowed.changeCount
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(TextExecutor.clipboardRestoreDelay * 1_000_000_000))
            await TextExecutor.restore(snapshot, ifChangeCountIs: changeCount)
        }
    }

    @MainActor
    static func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) {
        // If the user (or another app) copied something since, leave their clipboard alone.
        guard NSPasteboard.general.changeCount == changeCount else { return }
        snapshot.restore()
    }
}
