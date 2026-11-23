import AppKit
import Foundation

/// A copy of everything on the general pasteboard, so it can be put back after MagicForge has
/// borrowed the clipboard for a moment (paste-text, reading the selection).
struct PasteboardSnapshot: Sendable {
    struct Representation: Sendable {
        /// Raw value of the `NSPasteboard.PasteboardType`.
        let type: String
        let data: Data
    }

    /// Marker understood by clipboard managers (nspasteboard.org): "do not record this entry".
    static let transientTypeName = "org.nspasteboard.TransientType"

    /// One entry per pasteboard item, each with all of its representations.
    private let items: [[Representation]]

    private init(items: [[Representation]]) {
        self.items = items
    }

    /// Captures the current contents of the general pasteboard.
    @MainActor
    static func capture() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        var captured: [[Representation]] = []
        let currentItems: [NSPasteboardItem] = pasteboard.pasteboardItems ?? []
        for item in currentItems {
            var representations: [Representation] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations.append(Representation(type: type.rawValue, data: data))
                }
            }
            if !representations.isEmpty { captured.append(representations) }
        }
        return PasteboardSnapshot(items: captured)
    }

    /// Puts the captured contents back, replacing whatever is there now.
    @MainActor
    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        var restored: [NSPasteboardItem] = []
        for representations in items {
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            restored.append(item)
        }
        pasteboard.writeObjects(restored)
    }

    /// Replaces the clipboard with `string`, flagged as transient. Returns the new change count.
    @MainActor
    static func setTransientString(_ string: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(transientTypeName))
        return pasteboard.changeCount
    }
}
