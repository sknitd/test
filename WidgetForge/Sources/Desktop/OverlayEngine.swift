import AppKit
import SwiftUI

/// Conversions between AppKit screen space (origin bottom-left of the primary display, y up) and the
/// layout engine's global space (origin top-left of the primary display, y down).
@MainActor
enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func displayID(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return screen.localizedName }
        // The UUID survives reboots and re-plugging; the CGDirectDisplayID does not.
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "display-\(number.uint32Value)"
    }

    static func displays() -> [DisplayInfo] {
        let primary = NSScreen.screens.first
        return NSScreen.screens.map { screen in
            DisplayInfo(id: displayID(for: screen), name: screen.localizedName, frame: rect(from: screen.visibleFrame),
                        scale: Double(screen.backingScaleFactor), isMain: screen == primary)
        }
    }

    static func rect(from frame: NSRect) -> Rect {
        Rect(x: Double(frame.minX), y: Double(primaryHeight - frame.maxY), width: Double(frame.width), height: Double(frame.height))
    }

    static func nsRect(from rect: Rect) -> NSRect {
        NSRect(x: rect.x, y: Double(primaryHeight) - rect.y - rect.height, width: rect.width, height: rect.height)
    }
}

/// What the overlay engine needs from the app.
@MainActor
protocol OverlayHost: AnyObject {
    var store: WidgetStore { get }
    var settings: AppSettings { get }
    var isEditMode: Bool { get }
    var isClickThroughEnabled: Bool { get }
    func runtime(for widgetID: String) -> WidgetRuntime?
    func widgetMenu(for widgetID: String) -> NSMenu
    func overlayDidLog(_ message: String)
}

/// One borderless, non-activating panel per widget.
final class WidgetPanel: NSPanel {
    let widgetID: String
    var allowsKey = true

    init(widgetID: String, frame: NSRect) {
        self.widgetID = widgetID
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // the SwiftUI content draws its own shadow inside rounded corners
        isMovable = false                 // moving is handled by the edit overlay so it can snap and persist
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true     // only text fields take keyboard focus; clicks never activate the app
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        setAccessibilityRole(.group)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Window levels and Space behaviour for the two layers. See docs/FEASIBILITY.md for what each choice means
/// and which parts have been verified.
enum OverlayLayering {
    /// One above the desktop icons: under every application window, above the wallpaper and icons.
    static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    static func level(for layer: WidgetLayer, editing: Bool) -> NSWindow.Level {
        // While editing, widgets float so they cannot get lost behind other windows.
        if editing { return .floating }
        return layer == .floating ? .floating : desktopLevel
    }

    static func collectionBehavior(for layer: WidgetLayer) -> NSWindow.CollectionBehavior {
        switch layer {
        case .desktop: return [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        case .floating: return [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        }
    }
}

/// Creates, positions and retires widget panels so that the screen always mirrors the store.
@MainActor
final class OverlayManager {
    private weak var host: OverlayHost?
    private(set) var panels: [String: WidgetPanel] = [:]
    private var observers: [NSObjectProtocol] = []
    private(set) var isVisible = true

    init(host: OverlayHost) {
        self.host = host
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.host?.overlayDidLog("Display configuration changed: \(NSScreen.screens.count) display(s)")
                self?.sync()
            }
        })
        // Spaces changes can reorder desktop-level windows; re-assert ours.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reassertOrdering() }
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        sync()
    }

    /// Reconcile panels with the store. Cheap enough to call after any change.
    func sync() {
        guard let host else { return }
        let displays = ScreenGeometry.displays()
        let wanted = isVisible ? host.store.widgets.filter { !$0.hidden } : []
        let wantedIDs = Set(wanted.map(\.id))

        for (id, panel) in panels where !wantedIDs.contains(id) {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
            panels[id] = nil
        }
        for widget in wanted {
            guard let rect = LayoutEngine.globalRect(for: widget.placement, in: displays), let runtime = host.runtime(for: widget.id) else { continue }
            let frame = ScreenGeometry.nsRect(from: rect)
            let panel: WidgetPanel
            if let existing = panels[widget.id] {
                panel = existing
            } else {
                panel = WidgetPanel(widgetID: widget.id, frame: frame)
                let container = WidgetContainerView(widgetID: widget.id, host: host, runtime: runtime)
                panel.contentView = container
                panels[widget.id] = panel
            }
            configure(panel, for: widget, frame: frame)
        }
    }

    private func configure(_ panel: WidgetPanel, for widget: WidgetInstance, frame: NSRect) {
        guard let host else { return }
        let editing = host.isEditMode
        if panel.frame != frame, !(panel.contentView as? WidgetContainerView)!.isDragging { panel.setFrame(frame, display: true) }
        let level = OverlayLayering.level(for: widget.layer, editing: editing)
        if panel.level != level { panel.level = level }
        panel.collectionBehavior = OverlayLayering.collectionBehavior(for: widget.layer)
        panel.alphaValue = CGFloat(min(1, max(0.1, widget.opacity)))
        // Click-through never applies while editing, otherwise a widget could become unreachable.
        panel.ignoresMouseEvents = !editing && (widget.clickThrough || host.isClickThroughEnabled)
        switch widget.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.setAccessibilityLabel("\(widget.name) widget")
        (panel.contentView as? WidgetContainerView)?.update(editing: editing, locked: widget.locked)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func reassertOrdering() {
        for panel in panels.values where panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Facts about the live panels, for diagnostics and the self-test.
    func report() -> [[String: String]] {
        panels.values.map { panel in
            ["widget": panel.widgetID, "level": "\(panel.level.rawValue)", "visible": "\(panel.isVisible)",
             "frame": NSStringFromRect(panel.frame), "ignoresMouse": "\(panel.ignoresMouseEvents)",
             "screen": panel.screen?.localizedName ?? "none", "onActiveSpace": "\(panel.isOnActiveSpace)"]
        }
    }
}

/// The content view of a widget panel: the SwiftUI widget plus, in edit mode, the drag/resize overlay.
@MainActor
final class WidgetContainerView: NSView {
    let widgetID: String
    private weak var host: OverlayHost?
    private let hosting: NSHostingView<WidgetHostView>
    private let editOverlay: EditOverlayView
    var isDragging: Bool { editOverlay.isDragging }

    init(widgetID: String, host: OverlayHost, runtime: WidgetRuntime) {
        self.widgetID = widgetID
        self.host = host
        hosting = NSHostingView(rootView: WidgetHostView(runtime: runtime))
        editOverlay = EditOverlayView(widgetID: widgetID, host: host)
        super.init(frame: .zero)
        hosting.autoresizingMask = [.width, .height]
        editOverlay.autoresizingMask = [.width, .height]
        editOverlay.isHidden = true
        addSubview(hosting)
        addSubview(editOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        editOverlay.frame = bounds
    }

    func update(editing: Bool, locked: Bool) {
        editOverlay.isHidden = !editing
        editOverlay.isLocked = locked
        editOverlay.needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? { host?.widgetMenu(for: widgetID) }
}

/// The SwiftUI root of a widget panel.
struct WidgetHostView: View {
    @ObservedObject var runtime: WidgetRuntime

    var body: some View {
        WidgetContentView(definition: runtime.instance.definition, env: runtime.environment())
            .shadow(color: .black.opacity(runtime.instance.definition.style.shadowRadius > 0 ? 0.22 : 0),
                    radius: CGFloat(runtime.instance.definition.style.shadowRadius) / 2, y: 1)
            .padding(WidgetHostView.shadowInset)
            .overlay(alignment: .bottom) {
                if let notice = runtime.lastNotice {
                    Text(notice)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .onTapGesture { runtime.clearNotice() }
                        .task(id: notice) {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            runtime.clearNotice()
                        }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(runtime.instance.name)
    }

    /// Room inside the panel for the drop shadow.
    static let shadowInset: CGFloat = 6
}

/// Handles moving and resizing in edit mode with AppKit mouse tracking (smooth, no gesture lag), drawing a
/// selection border, corner handles and alignment guides against the other widgets.
@MainActor
final class EditOverlayView: NSView {
    private let widgetID: String
    private weak var host: OverlayHost?
    var isLocked = false
    private(set) var isDragging = false

    private var dragStartMouse = NSPoint.zero
    private var dragStartRect = Rect(x: 0, y: 0, width: 0, height: 0)
    private var activeHandle: ResizeHandle?
    private var guides: [AlignmentGuide] = []
    private static let handleSize: CGFloat = 12

    init(widgetID: String, host: OverlayHost) {
        self.widgetID = widgetID
        self.host = host
        super.init(frame: .zero)
        setAccessibilityLabel("Move or resize widget")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : super.hitTest(point) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 14, yRadius: 14)
        (isLocked ? NSColor.systemOrange : NSColor.controlAccentColor).withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        path.fill()
        guard !isLocked else {
            let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
            lock?.draw(in: NSRect(x: bounds.maxX - 24, y: 8, width: 12, height: 14))
            return
        }
        NSColor.controlAccentColor.setFill()
        for handle in ResizeHandle.allCases {
            NSBezierPath(ovalIn: handleRect(handle).insetBy(dx: 2, dy: 2)).fill()
        }
    }

    private func handleRect(_ handle: ResizeHandle) -> NSRect {
        let s = EditOverlayView.handleSize
        let x: CGFloat = handle.movesLeft ? 0 : (handle.movesRight ? bounds.maxX - s : bounds.midX - s / 2)
        let y: CGFloat = handle.movesTop ? 0 : (handle.movesBottom ? bounds.maxY - s : bounds.midY - s / 2)
        return NSRect(x: x, y: y, width: s, height: s)
    }

    private func handle(at point: NSPoint) -> ResizeHandle? {
        ResizeHandle.allCases.first { handleRect($0).insetBy(dx: -3, dy: -3).contains(point) }
    }

    override func resetCursorRects() {
        guard !isLocked else { return }
        addCursorRect(bounds, cursor: .openHand)
        for handle in ResizeHandle.allCases {
            let horizontal = handle == .left || handle == .right
            let vertical = handle == .top || handle == .bottom
            addCursorRect(handleRect(handle), cursor: horizontal ? .resizeLeftRight : (vertical ? .resizeUpDown : .crosshair))
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard !isLocked, let host, let widget = host.store.widget(widgetID),
              let rect = LayoutEngine.globalRect(for: widget.placement, in: ScreenGeometry.displays()) else { return }
        if event.clickCount == 2 {
            NotificationCenter.default.post(name: .widgetForgeOpenInBuilder, object: widgetID)
            return
        }
        isDragging = true
        dragStartMouse = NSEvent.mouseLocation
        dragStartRect = rect
        activeHandle = handle(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let host, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = Double(mouse.x - dragStartMouse.x)
        let dy = Double(dragStartMouse.y - mouse.y)            // screen y grows upward; layout y grows downward
        var rect: Rect
        if let activeHandle {
            rect = LayoutEngine.resize(dragStartRect, handle: activeHandle, dx: dx, dy: dy, minWidth: 80, minHeight: 48)
            if host.settings.snapToGrid { rect = LayoutEngine.snap(rect, grid: host.settings.gridSize, snapSize: true) }
        } else {
            rect = dragStartRect.offset(dx: dx, dy: dy)
            if host.settings.showAlignmentGuides, !event.modifierFlags.contains(.command) {
                let displays = ScreenGeometry.displays()
                let others = host.store.widgets.filter { $0.id != widgetID && !$0.hidden }
                    .compactMap { LayoutEngine.globalRect(for: $0.placement, in: displays) }
                let snapped = LayoutEngine.guides(moving: rect, others: others, threshold: 6)
                rect = snapped.rect
                guides = snapped.guides
            }
            if guides.isEmpty, host.settings.snapToGrid { rect = LayoutEngine.snap(rect, grid: host.settings.gridSize) }
        }
        window.setFrame(ScreenGeometry.nsRect(from: rect), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let host, let window else { return }
        isDragging = false
        guides = []
        let placement = LayoutEngine.placement(forGlobal: ScreenGeometry.rect(from: window.frame), in: ScreenGeometry.displays())
        let wasSnapping = host.store.snapToGrid
        host.store.snapToGrid = false                 // the drag already applied grid and guide snapping
        if activeHandle != nil { host.store.resize(widgetID, to: placement) } else { host.store.move(widgetID, to: placement) }
        host.store.snapToGrid = wasSnapping
        activeHandle = nil
    }

    /// Arrow keys nudge the widget (Shift = 10 pt) so edit mode is usable without a pointer.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !isLocked, let host, let widget = host.store.widget(widgetID) else { return super.keyDown(with: event) }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        var placement = widget.placement
        switch Int(event.keyCode) {
        case 123: placement.x -= step
        case 124: placement.x += step
        case 125: placement.y += step
        case 126: placement.y -= step
        default: return super.keyDown(with: event)
        }
        let wasSnapping = host.store.snapToGrid
        host.store.snapToGrid = false
        host.store.move(widgetID, to: placement)
        host.store.snapToGrid = wasSnapping
    }
}

extension Notification.Name {
    static let widgetForgeOpenInBuilder = Notification.Name("WidgetForgeOpenInBuilder")
    static let widgetForgeShowMainWindow = Notification.Name("WidgetForgeShowMainWindow")
}
