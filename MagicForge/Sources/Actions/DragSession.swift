import CoreGraphics
import Foundation
import MFCore
import MFUtilities

/// "Drag lock": holds the left mouse button down synthetically until toggled off.
///
/// macOS only produces drag events while a *hardware* button is down, so pressing the button
/// synthetically is not enough: while the lock is held, a short-lived event tap on its own
/// thread rewrites pointer movement (`mouseMoved`) into `leftMouseDragged`. The tap exists only
/// while a drag is held and is removed when the drag ends, which happens when
/// - the action is triggered again (a synthetic mouse-up is posted),
/// - the user physically clicks (that click's mouse-up drops the item), or
/// - the safety timeout elapses.
///
/// All state is guarded by `lock`.
final class DragSession: @unchecked Sendable {
    /// A forgotten drag lock is released automatically after this many seconds.
    static let safetyTimeout: TimeInterval = 30

    private let lock = NSLock()
    private let log = Log("actions.drag")
    private var isHeld = false
    private var generation = 0
    private var tap: CFMachPort?

    deinit {
        end(postMouseUp: true)
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return isHeld
    }

    func begin() throws {
        let source: CGEventSource = try SyntheticEvents.makeSource()
        let location: CGPoint = try SyntheticEvents.pointerLocation()
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: location,
                                 mouseButton: .left) else {
            throw ActionError.failed("Could not create the mouse event.")
        }

        let mask: CGEventMask = DragSession.bit(.mouseMoved) | DragSession.bit(.leftMouseDown) | DragSession.bit(.leftMouseUp)
        let context: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: dragSessionTapCallback,
                                           userInfo: context) else {
            throw ActionError.failed("Could not start the drag lock (event tap unavailable).")
        }
        guard let runLoopSource: CFRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            throw ActionError.failed("Could not start the drag lock (run loop source unavailable).")
        }

        lock.lock()
        if isHeld {
            lock.unlock()
            CFMachPortInvalidate(port)
            return
        }
        isHeld = true
        generation += 1
        let currentGeneration: Int = generation
        tap = port
        lock.unlock()

        // The thread keeps `self` alive for as long as the tap can call back into it.
        let thread = Thread { [self] in
            guard let runLoop = CFRunLoopGetCurrent() else { return }
            CFRunLoopAddSource(runLoop, runLoopSource, CFRunLoopMode.commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            while self.isCurrent(currentGeneration) {
                _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, false)
            }
            CFRunLoopRemoveSource(runLoop, runLoopSource, CFRunLoopMode.commonModes)
        }
        thread.name = "com.magicforge.drag-lock"
        thread.qualityOfService = .userInteractive
        thread.start()

        SyntheticEvents.post(down)
        log.info("Drag lock started")

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + DragSession.safetyTimeout) { [weak self] in
            guard let self, self.isCurrent(currentGeneration) else { return }
            self.log.notice("Drag lock released by safety timeout")
            self.end(postMouseUp: true)
        }
    }

    /// Ends the drag. `postMouseUp` is false when a real mouse-up has already ended it.
    func end(postMouseUp: Bool) {
        lock.lock()
        guard isHeld else {
            lock.unlock()
            return
        }
        isHeld = false
        generation += 1
        let port: CFMachPort? = tap
        tap = nil
        lock.unlock()

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if postMouseUp {
            if let source = try? SyntheticEvents.makeSource(),
               let location = try? SyntheticEvents.pointerLocation(),
               let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location,
                                mouseButton: .left) {
                SyntheticEvents.post(up)
            } else {
                log.error("Could not post the mouse-up that ends the drag lock")
            }
        }
        log.info("Drag lock ended")
    }

    // MARK: Event tap

    /// Runs on the drag-lock thread for every event selected by the tap.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough: Unmanaged<CGEvent> = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            let port: CFMachPort? = isHeld ? tap : nil
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return passThrough
        case .mouseMoved:
            guard isActive else { return passThrough }
            event.type = .leftMouseDragged
            return passThrough
        case .leftMouseDown:
            // Our own press passes; a physical press while holding is swallowed so the target
            // sees one continuous press that ends with the physical release below.
            if SyntheticEvents.isSynthetic(event) || !isActive { return passThrough }
            return nil
        case .leftMouseUp:
            if SyntheticEvents.isSynthetic(event) || !isActive { return passThrough }
            // The physical release drops the item. Tear down outside the callback.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.end(postMouseUp: false)
            }
            return passThrough
        default:
            return passThrough
        }
    }

    private func isCurrent(_ candidate: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isHeld && generation == candidate
    }

    private static func bit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }
}

/// C callback for the drag-lock event tap. `userInfo` is the owning `DragSession`.
private func dragSessionTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session: DragSession = Unmanaged<DragSession>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(type: type, event: event)
}
