import SwiftUI
import AppKit
import MFCore
import MFUtilities

/// Borderless panel that can become key (for keyboard input) without activating the app.
final class RadialMenuPanel: NSPanel {
    /// Returns true when the key event was consumed.
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == NSEvent.EventType.keyDown, let handler = onKeyDown, handler(event) {
            return
        }
        super.sendEvent(event)
    }
}

/// Content view of the panel. Receives every pointer event itself (the SwiftUI ring underneath
/// is display only) and reports positions in a top-left based coordinate space. It only tracks
/// the pointer; it never captures or warps it.
final class RadialMenuInputView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = pointerTrackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
}

/// Presents the floating radial menu at the cursor.
@MainActor
public final class RadialMenuController: RadialMenuPresenting {
    private var panel: RadialMenuPanel?
    private var overlayModel: RadialOverlayModel?
    private var continuation: CheckedContinuation<RadialMenuItem?, Never>?
    private var presentedMenuID: UUID?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let log = Log("radial-menu")

    nonisolated public init() {}

    /// Shows `menu` centred on the pointer and resolves with the chosen item, or nil when it was
    /// dismissed. Presenting while a menu is open closes the open one (resolving it with nil);
    /// presenting the *same* menu again just closes it, so a trigger works as a toggle.
    public func present(_ menu: RadialMenu, recent: [RadialMenuItem]) async -> RadialMenuItem? {
        if panel != nil {
            let isToggle: Bool = presentedMenuID == menu.id
            finish(with: nil)
            if isToggle { return nil }
        }
        guard !menu.items.isEmpty else {
            log.notice("Radial menu has no items; nothing to show")
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<RadialMenuItem?, Never>) in
            self.continuation = continuation
            self.show(menu, recent: recent)
        }
    }

    public func dismiss() {
        finish(with: nil)
    }

    // MARK: Showing

    private func show(_ menu: RadialMenu, recent: [RadialMenuItem]) {
        let mouse: NSPoint = NSEvent.mouseLocation
        let screens: [NSScreen] = NSScreen.screens
        let screenUnderPointer: NSScreen? = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        guard let screen = screenUnderPointer ?? NSScreen.main ?? screens.first else {
            log.error("No screen available for the radial menu")
            finish(with: nil)
            return
        }

        let model = RadialOverlayModel(menu: menu, recent: recent)
        model.onChoose = { [weak self] (item: RadialMenuItem) in
            self?.finish(with: item)
        }
        model.onDismiss = { [weak self] in
            self?.finish(with: nil)
        }

        let size: CGSize = model.layout.panelSize
        let origin: CGPoint = model.layout.panelOrigin(mouse: mouse, visibleFrame: screen.visibleFrame)
        let newPanel = RadialMenuPanel(contentRect: NSRect(origin: origin, size: size),
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        newPanel.level = .popUpMenu
        newPanel.isOpaque = false
        newPanel.backgroundColor = NSColor.clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.isMovable = false
        newPanel.ignoresMouseEvents = false
        newPanel.acceptsMouseMovedEvents = true
        newPanel.animationBehavior = .none

        let container = RadialMenuInputView(frame: NSRect(origin: .zero, size: size))
        let hosting = NSHostingView(rootView: RadialOverlayView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.onMove = { [weak model] (point: CGPoint) in
            model?.pointerMoved(to: point)
        }
        container.onExit = { [weak model] in
            model?.pointerExited()
        }
        container.onClick = { [weak model] (point: CGPoint) in
            model?.clicked(at: point)
        }
        newPanel.contentView = container
        newPanel.onKeyDown = { [weak self] (event: NSEvent) -> Bool in
            guard let controller = self else { return false }
            return controller.handleKey(event)
        }

        panel = newPanel
        overlayModel = model
        presentedMenuID = menu.id
        installMonitors()

        newPanel.setFrameOrigin(origin)
        newPanel.orderFrontRegardless()
        newPanel.makeKey()
        // Highlight whatever is already under the pointer.
        let local: NSPoint = newPanel.convertPoint(fromScreen: mouse)
        model.pointerMoved(to: CGPoint(x: local.x, y: size.height - local.y))
    }

    // MARK: Dismissal

    /// Closes the panel (if any) and resumes the pending continuation exactly once.
    private func finish(with item: RadialMenuItem?) {
        removeMonitors()
        let closingPanel: RadialMenuPanel? = panel
        let closingModel: RadialOverlayModel? = overlayModel
        panel = nil
        overlayModel = nil
        presentedMenuID = nil
        let pending: CheckedContinuation<RadialMenuItem?, Never>? = continuation
        continuation = nil

        if let closingPanel = closingPanel {
            closingPanel.onKeyDown = nil
            closingPanel.ignoresMouseEvents = true
            closingModel?.onChoose = nil
            closingModel?.onDismiss = nil
            closingModel?.isVisible = false
            Task { @MainActor in
                // Let the short fade-out play, then remove the window.
                try? await Task.sleep(nanoseconds: 130_000_000)
                closingPanel.orderOut(nil)
                closingPanel.contentView = nil
            }
        }
        pending?.resume(returning: item)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks delivered to other apps.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] (_: NSEvent) in
            MainActor.assumeIsolated {
                if let controller = self {
                    controller.finish(with: nil)
                }
            }
        }
        // Clicks in MagicForge's own windows other than the menu panel.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] (event: NSEvent) -> NSEvent? in
            let windowNumber: Int = event.windowNumber
            MainActor.assumeIsolated {
                if let controller = self, let openPanel = controller.panel, openPanel.windowNumber != windowNumber {
                    controller.finish(with: nil)
                }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: Keyboard

    /// Every key is consumed while the menu is key so nothing leaks into the app underneath.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model = overlayModel else { return false }
        let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:
            model.handle(.escape)
            return true
        case 36, 76:
            model.handle(.activate)
            return true
        case 51, 117:
            model.handle(.deleteBackward)
            return true
        case 124, 125:
            model.handle(.next)
            return true
        case 123, 126:
            model.handle(.previous)
            return true
        default:
            break
        }
        if flags.contains(.command) || flags.contains(.control) {
            return true
        }
        guard let characters = event.characters, !characters.isEmpty else { return true }
        if characters.count == 1, let digit = Int(characters), digit >= 0, digit <= 9 {
            model.handle(.digit(digit))
            return true
        }
        let allowed: CharacterSet = CharacterSet.alphanumerics.union(.punctuationCharacters).union(CharacterSet(charactersIn: " "))
        let isText: Bool = characters.unicodeScalars.allSatisfy { allowed.contains($0) }
        if isText {
            model.handle(.text(characters))
        }
        return true
    }
}
