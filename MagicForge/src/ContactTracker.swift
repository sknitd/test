import CoreFoundation
import Foundation

/// One contact of a MultitouchSupport frame reduced to the fields MagicForge uses.
struct RawTouch {
    var identifier: Int
    var state: Int32
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var size: Double
    var majorAxis: Double
    var minorAxis: Double
    var angle: Double
}

/// Turns the per-frame contact list of one device into `TouchFrame`s with explicit phases.
///
/// State mapping (private `MTTouch.state` → `ContactPhase`):
/// - 3 (make touch) and 4 (touching) are the only "on the surface" stages. The first frame in
///   which an identifier is on the surface is `.began`; later frames are `.moved`
///   (`.stationary` when the normalized position did not change at all).
/// - 5 (break touch), 6 (lingering), 7 (out of range), 1/2 (hover) and a missing identifier all
///   mean "not on the surface". A contact that was on the surface is reported once as `.ended`
///   and then forgotten. Hovering fingers that never touched are not reported.
///
/// When the last finger lifts, the emitted frame contains only `.ended` contacts, so
/// `TouchFrame.touching` is empty: that is the "all fingers lifted" marker. No further frames
/// are emitted until a finger touches again.
struct ContactTracker {
    private var onSurface: [Int: TouchContact] = [:]

    var hasContacts: Bool { !onSurface.isEmpty }

    init() {}

    mutating func frame(from touches: [RawTouch], timestamp: TimeInterval, deviceID: UInt64) -> TouchFrame? {
        var contacts: [TouchContact] = []
        var ended: [TouchContact] = []
        var seen = Set<Int>()
        for touch in touches {
            guard !seen.contains(touch.identifier) else { continue }
            seen.insert(touch.identifier)
            let previous: TouchContact? = onSurface[touch.identifier]
            var contact = TouchContact(id: touch.identifier, x: touch.x, y: touch.y, vx: touch.vx, vy: touch.vy,
                                       size: touch.size, majorAxis: touch.majorAxis, minorAxis: touch.minorAxis,
                                       angle: touch.angle, phase: .moved)
            if MTTouchState.isOnSurface(touch.state) {
                if let previous = previous {
                    contact.phase = (previous.x == contact.x && previous.y == contact.y) ? .stationary : .moved
                } else {
                    contact.phase = .began
                }
                onSurface[touch.identifier] = contact
                contacts.append(contact)
            } else if previous != nil {
                contact.phase = .ended
                contact.vx = 0
                contact.vy = 0
                onSurface[touch.identifier] = nil
                ended.append(contact)
            }
        }
        // Identifiers that vanished without a break-touch stage.
        let vanished: [Int] = onSurface.keys.filter { !seen.contains($0) }.sorted()
        for identifier in vanished {
            guard var contact = onSurface[identifier] else { continue }
            contact.phase = .ended
            contact.vx = 0
            contact.vy = 0
            onSurface[identifier] = nil
            ended.append(contact)
        }
        contacts.append(contentsOf: ended)
        guard !contacts.isEmpty else { return nil }
        return TouchFrame(timestamp: timestamp, deviceID: deviceID, contacts: contacts)
    }

    /// The device went away (disconnect, adapter stop): report every tracked contact as cancelled.
    mutating func cancelAll(timestamp: TimeInterval, deviceID: UInt64) -> TouchFrame? {
        guard !onSurface.isEmpty else { return nil }
        var contacts: [TouchContact] = []
        for identifier in onSurface.keys.sorted() {
            guard var contact = onSurface[identifier] else { continue }
            contact.phase = .cancelled
            contact.vx = 0
            contact.vy = 0
            contacts.append(contact)
        }
        onSurface.removeAll()
        return TouchFrame(timestamp: timestamp, deviceID: deviceID, contacts: contacts)
    }
}

/// Conversion helpers between MultitouchSupport values and MFCore types.
enum TouchConversion {
    /// Callback timestamps are assumed to be seconds on the same timebase as `MonotonicClock`
    /// (`mach_absolute_time`, i.e. uptime excluding sleep). That assumption is unverified, so the
    /// value is only trusted when it is finite and within `tolerance` of "now"; otherwise the
    /// arrival time is used. The result never exceeds `now` and never goes backwards.
    static func timestamp(reported: Double, now: TimeInterval, previous: TimeInterval,
                          tolerance: TimeInterval = 1.0) -> TimeInterval {
        var value = now
        if reported.isFinite && reported > 0 && abs(now - reported) <= tolerance {
            value = min(reported, now)
        }
        return max(value, previous)
    }

    static func unit(_ value: Float) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, Double(value)))
    }

    static func finite(_ value: Float) -> Double {
        value.isFinite ? Double(value) : 0
    }

    /// `invertY` flips the vertical axis for devices whose normalized y grows toward the rear.
    static func rawTouch(from touch: MTTouch, invertY: Bool) -> RawTouch {
        let y: Double = unit(touch.normalized.position.y)
        let vy: Double = finite(touch.normalized.velocity.y)
        return RawTouch(identifier: Int(touch.identifier), state: touch.state,
                        x: unit(touch.normalized.position.x), y: invertY ? 1 - y : y,
                        vx: finite(touch.normalized.velocity.x), vy: invertY ? -vy : vy,
                        size: max(0, finite(touch.total)),
                        majorAxis: max(0, finite(touch.majorAxis)), minorAxis: max(0, finite(touch.minorAxis)),
                        angle: finite(touch.angle))
    }
}
