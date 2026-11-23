import CoreGraphics
import Foundation
import MFCore

/// Synthetic mouse clicks, drag lock and scrolling at the current pointer location.
/// Requires Accessibility.
final class MouseExecutor: Sendable {
    private let dragSession = DragSession()

    func perform(_ action: MouseAction) async throws {
        switch action {
        case .leftClick:
            try await click(button: .left, down: .leftMouseDown, up: .leftMouseUp, count: 1)
        case .rightClick:
            try await click(button: .right, down: .rightMouseDown, up: .rightMouseUp, count: 1)
        case .middleClick:
            try await click(button: .center, down: .otherMouseDown, up: .otherMouseUp, count: 1)
        case .doubleClick:
            try await click(button: .left, down: .leftMouseDown, up: .leftMouseUp, count: 2)
        case .toggleDrag:
            if dragSession.isActive {
                dragSession.end(postMouseUp: true)
            } else {
                try dragSession.begin()
            }
        case .scroll(let dx, let dy):
            try scroll(dx: dx, dy: dy)
        }
    }

    /// Releases a held drag (used when the performer is torn down or actions are cancelled).
    func releaseDrag() {
        dragSession.end(postMouseUp: true)
    }

    private func click(button: CGMouseButton, down: CGEventType, up: CGEventType, count: Int) async throws {
        // A click while the drag lock is held would confuse the target app: drop first.
        if dragSession.isActive { dragSession.end(postMouseUp: true) }
        let source: CGEventSource = try SyntheticEvents.makeSource()
        let location: CGPoint = try SyntheticEvents.pointerLocation()
        for clickNumber in 1...max(1, count) {
            guard let downEvent = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: location,
                                          mouseButton: button),
                  let upEvent = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: location,
                                        mouseButton: button) else {
                throw ActionError.failed("Could not create the mouse event.")
            }
            // Click state 1 = single click, 2 = second click of a double click.
            downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            SyntheticEvents.post(downEvent)
            await SyntheticEvents.gap(0.01)
            SyntheticEvents.post(upEvent)
            if clickNumber < count { await SyntheticEvents.gap(0.03) }
        }
    }

    /// `dx` / `dy` are lines; positive dy scrolls up, positive dx scrolls right.
    private func scroll(dx: Double, dy: Double) throws {
        let vertical: Int32 = MouseExecutor.lines(dy)
        // Quartz axis 2 is positive towards the left, MagicForge's dx is positive towards the right.
        let horizontal: Int32 = -MouseExecutor.lines(dx)
        guard vertical != 0 || horizontal != 0 else { return }
        let source: CGEventSource = try SyntheticEvents.makeSource()
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2,
                                  wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
            throw ActionError.failed("Could not create the scroll event.")
        }
        SyntheticEvents.post(event)
    }

    /// Rounds to whole lines, but never rounds a non-zero request down to nothing.
    private static func lines(_ value: Double) -> Int32 {
        guard value.isFinite, value != 0 else { return 0 }
        let clamped: Double = min(max(value, -1000), 1000)
        let rounded: Double = clamped.rounded()
        if rounded == 0 { return clamped > 0 ? 1 : -1 }
        return Int32(rounded)
    }
}
