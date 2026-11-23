import CoreGraphics
import Foundation
import MFCore
import MFUtilities

/// The C callback of the event tap. It captures nothing; `userInfo` is the owning session.
private let eventTapCallback: CGEventTapCallBack = { (_: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                                      userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<EventTapSession>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(type: type, event: event)
}

/// One live event tap with its dedicated run-loop thread. Created by `start`, discarded by `stop`.
///
/// Threading: `start()` / `stop()` are called by `EventTapPointerSource` under its lifecycle lock.
/// `handle(type:event:)` and the "tap thread only" fields run exclusively on the tap thread. The
/// thread keeps the session alive until its run loop has exited, so the unretained `userInfo`
/// pointer can never dangle while callbacks are possible.
final class EventTapSession: @unchecked Sendable {
    private static let log = Log("eventtap")
    /// Scroll events closer together than this belong to one chord-scroll burst.
    static let chordScrollDebounce: TimeInterval = 0.25

    private let configuration: Locked<EventTapConfiguration>
    private let stopRequested = Locked<Bool>(false)
    private let runLoop = Locked<CFRunLoop?>(nil)
    private var port: CFMachPort?

    // Tap thread only.
    private var swallowedButtonUps = Set<Int>()
    private var swallowedKeyUps = Set<UInt16>()
    private var lastChordScrollTime: TimeInterval = -1
    private var chordBurstDecided = false
    private var chordBurstSwallowed = false
    private var scrollGestureFromMagicMouse = false

    init(configuration: Locked<EventTapConfiguration>) {
        self.configuration = configuration
    }

    var isEnabled: Bool {
        guard let port = port, !stopRequested.current else { return false }
        return CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port)
    }

    /// Creates the tap and its thread. Returns false when the system refuses the tap.
    func start() -> Bool {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: EventTapLogic.eventMask,
                                              callback: eventTapCallback, userInfo: userInfo) else {
            EventTapSession.log.error("CGEvent.tapCreate returned nil (Accessibility permission missing?)")
            return false
        }
        port = created
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            self.runTapThread(port: created, ready: ready)
        }
        thread.name = "com.magicforge.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
    }

    /// Disables and invalidates the tap and asks the thread to exit. Does not block on the thread,
    /// so it is safe to call from the tap thread itself. Idempotent.
    func stop() {
        let alreadyStopped: Bool = stopRequested.withLock { flag in
            let previous = flag
            flag = true
            return previous
        }
        guard !alreadyStopped, let port = port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let loop = runLoop.current { CFRunLoopStop(loop) }
    }

    private func runTapThread(port: CFMachPort, ready: DispatchSemaphore) {
        // Explicit optionals: these CoreFoundation calls are imported as implicitly unwrapped.
        let createdSource: CFRunLoopSource? = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let currentLoop: CFRunLoop? = CFRunLoopGetCurrent()
        guard let source = createdSource, let current = currentLoop else {
            EventTapSession.log.error("Could not create the event tap run loop source")
            ready.signal()
            return
        }
        CFRunLoopAddSource(current, source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        runLoop.withLock { $0 = current }
        ready.signal()
        while !stopRequested.current {
            // Returns early when `stop()` calls CFRunLoopStop; the timeout only bounds the exit delay.
            _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.5, false)
        }
        CFRunLoopRemoveSource(current, source, CFRunLoopMode.commonModes)
        runLoop.withLock { $0 = nil }
    }

    // MARK: Event handling (tap thread)

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !stopRequested.current, let port = port {
                CGEvent.tapEnable(tap: port, enable: true)
                EventTapSession.log.notice("Event tap was disabled by the system and has been re-enabled")
            }
            return passThrough
        }
        // Events MagicForge posted itself are never interpreted or modified.
        if event.getIntegerValueField(.eventSourceUserData) == EventTapLogic.syntheticEventUserData {
            return passThrough
        }
        let config: EventTapConfiguration = configuration.current
        guard let handlers = config.handlers else { return passThrough }
        let now: TimeInterval = MonotonicClock.now()

        switch type {
        case .leftMouseDown:
            return handleButton(0, isDown: true, event: event, config: config, handlers: handlers, now: now)
        case .leftMouseUp:
            return handleButton(0, isDown: false, event: event, config: config, handlers: handlers, now: now)
        case .rightMouseDown:
            return handleButton(1, isDown: true, event: event, config: config, handlers: handlers, now: now)
        case .rightMouseUp:
            return handleButton(1, isDown: false, event: event, config: config, handlers: handlers, now: now)
        case .otherMouseDown, .otherMouseUp:
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            handlers.onButton(number, type == .otherMouseDown, now)
            return passThrough
        case .scrollWheel:
            return handleScroll(event: event, config: config, handlers: handlers, now: now)
        case .keyDown:
            return handleKeyDown(event: event, config: config, handlers: handlers)
        case .keyUp:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            return swallowedKeyUps.remove(keyCode) != nil ? nil : passThrough
        default:
            return passThrough
        }
    }

    private func handleButton(_ button: Int, isDown: Bool, event: CGEvent, config: EventTapConfiguration,
                              handlers: PointerEventHandlers, now: TimeInterval) -> Unmanaged<CGEvent>? {
        // Every physical transition is reported, also when the click is consumed as a chord.
        handlers.onButton(button, isDown, now)
        if isDown {
            let kind: GestureKind = button == 0 ? .chordLeftClick : .chordRightClick
            if config.enabledChords.contains(kind) && EventTapLogic.isChordModifierState(event.flags)
                && handlers.onChord(kind, now) {
                swallowedButtonUps.insert(button)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        // The release of a swallowed press is swallowed too, whatever the modifiers are by then.
        if swallowedButtonUps.remove(button) != nil { return nil }
        return Unmanaged.passUnretained(event)
    }

    private func handleScroll(event: CGEvent, config: EventTapConfiguration, handlers: PointerEventHandlers,
                              now: TimeInterval) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        let chordsWanted: Bool = !config.enabledChords.isDisjoint(with: EventTapLogic.chordScrollKinds)
        guard chordsWanted || config.scrollInterceptionEnabled else { return passThrough }
        let fields = ScrollEventRewriter(event: event)

        if chordsWanted {
            let withinBurst: Bool = lastChordScrollTime >= 0
                && now - lastChordScrollTime <= EventTapSession.chordScrollDebounce
            let modifiersHeld: Bool = EventTapLogic.isChordModifierState(event.flags)
            if withinBurst && chordBurstDecided {
                // The burst continues (including momentum after the modifiers were released).
                lastChordScrollTime = now
                if chordBurstSwallowed { return nil }
            } else if modifiersHeld {
                if !withinBurst {
                    chordBurstDecided = false
                    chordBurstSwallowed = false
                }
                lastChordScrollTime = now
                if let kind = EventTapLogic.chordScrollKind(deltaX: fields.sampleDeltaX, deltaY: fields.sampleDeltaY) {
                    chordBurstDecided = true
                    chordBurstSwallowed = config.enabledChords.contains(kind) && handlers.onChord(kind, now)
                    if chordBurstSwallowed { return nil }
                }
            } else if !withinBurst {
                chordBurstDecided = false
                chordBurstSwallowed = false
            }
        }

        guard config.scrollInterceptionEnabled else { return passThrough }
        let isMomentum: Bool = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let isFromMagicMouse: Bool = scrollOrigin(isContinuous: fields.isContinuous, isMomentum: isMomentum,
                                                  config: config)
        let sample = ScrollSample(deltaX: fields.sampleDeltaX, deltaY: fields.sampleDeltaY,
                                  isContinuous: fields.isContinuous, isFromMagicMouse: isFromMagicMouse,
                                  isMomentum: isMomentum, timestamp: now)
        switch handlers.onScroll(sample) {
        case .passThrough:
            break
        case .rewrite(let deltaX, let deltaY):
            fields.apply(deltaX: deltaX, deltaY: deltaY, to: event)
        }
        return passThrough
    }

    /// Best-effort "did this scroll come from a Magic Mouse" (see `EventTapPointerSource`).
    private func scrollOrigin(isContinuous: Bool, isMomentum: Bool, config: EventTapConfiguration) -> Bool {
        guard isContinuous else {
            // Line-based deltas come from classic wheel mice, never from a Magic Mouse.
            scrollGestureFromMagicMouse = false
            return false
        }
        // Momentum events arrive after the finger lifted: inherit the verdict of the gesture.
        if isMomentum { return scrollGestureFromMagicMouse }
        if let probe = config.magicMouseActivityProbe {
            scrollGestureFromMagicMouse = probe()
        } else {
            scrollGestureFromMagicMouse = config.assumeContinuousScrollIsMagicMouse
        }
        return scrollGestureFromMagicMouse
    }

    private func handleKeyDown(event: CGEvent, config: EventTapConfiguration,
                               handlers: PointerEventHandlers) -> Unmanaged<CGEvent>? {
        guard !config.hotKeys.isEmpty else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard let identifier = EventTapLogic.hotKey(for: keyCode, flags: event.flags, in: config.hotKeys) else {
            return Unmanaged.passUnretained(event)
        }
        let isRepeat: Bool = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat { handlers.onHotKey(identifier) }
        swallowedKeyUps.insert(keyCode)
        return nil
    }
}
