import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MFCore
import MFUtilities

/// Moves and resizes the focused window of the frontmost app through the Accessibility API.
/// Requires Accessibility. Thread-safe: the only mutable state is the lock-guarded frame memory.
final class WindowExecutor: @unchecked Sendable {
    private let memory = Locked<FrameMemory>(FrameMemory(capacity: 64))
    private let log = Log("actions.window")

    func perform(_ action: WindowAction) async throws {
        let displays: [DisplayArea] = await MainActor.run { WindowExecutor.currentDisplays() }
        let target = try focusedWindow()
        switch action {
        case .minimize:
            try check(AX.set(target.window, kAXMinimizedAttribute as String, bool: true), "minimize the window")
        case .close:
            guard let button = AX.element(target.window, kAXCloseButtonAttribute as String) else {
                throw ActionError.failed("The focused window has no close button.")
            }
            try check(AX.press(button), "close the window")
        case .restorePreviousFrame:
            guard let previous = memory.withLock({ $0.takePrevious(for: target.key) }) else {
                throw ActionError.failed("No earlier frame is remembered for this window.")
            }
            try apply(previous, to: target)
        case .snapLeft: try place(.leftHalf, target: target, displays: displays)
        case .snapRight: try place(.rightHalf, target: target, displays: displays)
        case .snapTop: try place(.topHalf, target: target, displays: displays)
        case .snapBottom: try place(.bottomHalf, target: target, displays: displays)
        case .maximize: try place(.maximize, target: target, displays: displays)
        case .center: try place(.center, target: target, displays: displays)
        case .moveToNextDisplay: try place(.nextDisplay, target: target, displays: displays)
        case .resize(let fraction): try place(.resize(byFraction: fraction), target: target, displays: displays)
        }
    }

    // MARK: Target lookup

    private struct Target {
        let application: AXUIElement
        let window: AXUIElement
        let key: FrameMemory.Key
    }

    private func focusedWindow() throws -> Target {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw ActionError.failed("There is no frontmost application.")
        }
        let pid: pid_t = frontmost.processIdentifier
        let application = AX.application(pid: pid)
        let found: AXUIElement? = AX.element(application, kAXFocusedWindowAttribute as String)
            ?? AX.element(application, kAXMainWindowAttribute as String)
        guard let window = found else {
            throw ActionError.failed("\(frontmost.localizedName ?? "The frontmost app") has no focused window.")
        }
        // Equal AXUIElements (same window) hash equally, so pid + hash identifies the window.
        let key = FrameMemory.Key(pid: pid, windowHash: UInt(CFHash(window)))
        return Target(application: application, window: window, key: key)
    }

    // MARK: Placement

    private func place(_ placement: WindowPlacement, target: Target, displays: [DisplayArea]) throws {
        guard !displays.isEmpty else { throw ActionError.failed("No display information is available.") }
        let current = try frame(of: target.window)
        guard let destination = WindowGeometry.frame(for: placement, window: current, displays: displays) else {
            if placement == .nextDisplay { throw ActionError.failed("There is only one display.") }
            throw ActionError.failed("Could not work out a frame for the window.")
        }
        try apply(destination, to: target, rememberingCurrent: current)
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        guard let origin = AX.point(window, kAXPositionAttribute as String),
              let size = AX.size(window, kAXSizeAttribute as String) else {
            throw ActionError.failed("Could not read the window's frame.")
        }
        return CGRect(origin: origin, size: size)
    }

    private func apply(_ destination: CGRect, to target: Target, rememberingCurrent current: CGRect? = nil) throws {
        let window = target.window
        if AX.bool(window, "AXFullScreen") == true {
            throw ActionError.failed("The window is in full screen.")
        }
        guard AX.isSettable(window, kAXPositionAttribute as String) else {
            throw ActionError.failed("This window cannot be moved.")
        }
        let canResize: Bool = AX.isSettable(window, kAXSizeAttribute as String)

        // Some apps (notably Chromium / Electron based ones) animate or mis-handle frame changes
        // while "enhanced user interface" is on; switch it off for the duration of the change.
        let enhancedAttribute = "AXEnhancedUserInterface"
        let hadEnhancedUI: Bool = AX.bool(target.application, enhancedAttribute) == true
        if hadEnhancedUI { _ = AX.set(target.application, enhancedAttribute, bool: false) }
        defer {
            if hadEnhancedUI { _ = AX.set(target.application, enhancedAttribute, bool: true) }
        }

        // Size → position → size: the first resize lets the window fit on the destination
        // display, the move puts it there, and the second resize corrects apps that clamped the
        // first one against the old display's bounds.
        if canResize { _ = AX.set(window, kAXSizeAttribute as String, size: destination.size) }
        let moveError: AXError = AX.set(window, kAXPositionAttribute as String, point: destination.origin)
        if moveError != .success {
            throw ActionError.failed("Could not move the window: \(AX.describe(moveError)).")
        }
        if canResize {
            let resizeError: AXError = AX.set(window, kAXSizeAttribute as String, size: destination.size)
            if resizeError != .success {
                throw ActionError.failed("Could not resize the window: \(AX.describe(resizeError)).")
            }
        }

        // Remember where the window came from, and where it actually ended up (apps may enforce
        // their own minimum / maximum sizes).
        let applied: CGRect = (try? frame(of: window)) ?? destination
        if let current {
            memory.withLock { $0.record(previous: current, applied: applied, for: target.key) }
        }
        if !canResize && !WindowGeometry.isApproximatelyEqual(applied, destination) {
            log.info("Window is not resizable; moved only")
        }
    }

    private func check(_ error: AXError, _ what: String) throws {
        guard error == .success else {
            throw ActionError.failed("Could not \(what): \(AX.describe(error)).")
        }
    }

    // MARK: Displays

    /// All displays in global top-left coordinates. `NSScreen.screens.first` is the primary
    /// display (the one whose AppKit frame origin is 0,0), which anchors both coordinate spaces.
    @MainActor
    static func currentDisplays() -> [DisplayArea] {
        let screens: [NSScreen] = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight: CGFloat = primary.frame.height
        return screens.map { screen in
            DisplayArea(frame: WindowGeometry.topLeftRect(fromAppKit: screen.frame, primaryDisplayHeight: primaryHeight),
                        visibleFrame: WindowGeometry.topLeftRect(fromAppKit: screen.visibleFrame,
                                                                 primaryDisplayHeight: primaryHeight))
        }
    }
}

/// Bounded memory of "where was this window before MagicForge moved it".
struct FrameMemory {
    struct Key: Hashable {
        let pid: pid_t
        let windowHash: UInt
    }

    private struct Entry {
        var previous: CGRect
        var applied: CGRect
    }

    private let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    /// Records a move. When the window is still where MagicForge last put it (e.g. snap left,
    /// then snap right) the original frame is kept, so "restore" returns to the user's own layout.
    mutating func record(previous: CGRect, applied: CGRect, for key: Key) {
        if var entry = entries[key], WindowGeometry.isApproximatelyEqual(entry.applied, previous) {
            entry.applied = applied
            entries[key] = entry
        } else {
            entries[key] = Entry(previous: previous, applied: applied)
        }
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries[evicted] = nil
        }
    }

    mutating func takePrevious(for key: Key) -> CGRect? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        order.removeAll { $0 == key }
        return entry.previous
    }
}
