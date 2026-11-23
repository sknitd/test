import XCTest
import MFCore
@testable import MFGestures

typealias Point = SyntheticTouch.Point

/// All gesture kinds the recognizer is responsible for.
let rawKinds: [GestureKind] = GestureKind.allCases.filter { $0.requirement == .rawContacts }

/// Drives an engine the way the host does: frames in order, `advance(to:)` whenever a deadline
/// falls before the next frame, physical clicks at their timestamps, and (optionally) the
/// remaining deadlines after the last frame.
@discardableResult
func drive(_ engine: GestureEngine, _ frames: [TouchFrame], clicks: [TimeInterval] = [],
         settle: Bool = true) -> [GestureEvent] {
    var events: [GestureEvent] = []
    var remainingClicks = clicks.sorted()
    for frame in frames {
        var guardCount = 0
        while let deadline = engine.nextDeadline, deadline < frame.timestamp, guardCount < 8 {
            events += engine.advance(to: deadline)
            guardCount += 1
        }
        while let click = remainingClicks.first, click <= frame.timestamp {
            engine.notePhysicalClick(at: click)
            remainingClicks.removeFirst()
        }
        events += engine.process(frame)
    }
    for click in remainingClicks { engine.notePhysicalClick(at: click) }
    if settle {
        var guardCount = 0
        while let deadline = engine.nextDeadline, guardCount < 8 {
            events += engine.advance(to: deadline)
            guardCount += 1
        }
    }
    return events
}

func makeEngine(enabled: [GestureKind]? = nil, configure: ((inout RecognizerConfig) -> Void)? = nil) -> GestureEngine {
    var config = RecognizerConfig()
    configure?(&config)
    let engine = GestureEngine(config: config)
    if let enabled = enabled { engine.enabledKinds = Set(enabled) }
    return engine
}

func kinds(_ events: [GestureEvent]) -> [GestureKind] { events.map(\.kind) }

func render(_ paths: [SyntheticTouch.ContactPath], at start: TimeInterval = 10,
            endStyle: SyntheticTouch.EndStyle = .endedPhase) -> [TouchFrame] {
    SyntheticTouch.render(paths, startTime: start, endStyle: endStyle)
}

/// Kinds a canonical synthetic stream is expected to produce when everything is enabled.
func expectedWithAllEnabled(_ kind: GestureKind) -> [GestureKind] {
    switch kind {
    case .holdThenSwipeLeft, .holdThenSwipeRight, .holdThenSwipeUp, .holdThenSwipeDown:
        return [.oneFingerHold, kind]   // the hold fires first, then the compound gesture
    default:
        return [kind]
    }
}
