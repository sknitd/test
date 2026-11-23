import CoreFoundation
import Foundation

/// Lifecycle phase of one finger contact inside a frame.
public enum ContactPhase: String, Codable, Sendable {
    case began, moved, stationary, ended, cancelled
}

/// One finger contact on the mouse surface.
///
/// Coordinates are normalized to the touch surface: `x` 0 = left edge … 1 = right edge,
/// `y` 0 = rear edge (nearest the user's palm) … 1 = front edge (toward the screen).
/// Convert to millimetres with `SurfaceGeometry` before comparing distances, because the
/// surface is not square.
public struct TouchContact: Codable, Sendable, Equatable, Identifiable {
    /// Stable for as long as this finger stays on the surface.
    public var id: Int
    public var x: Double
    public var y: Double
    /// Velocity in normalized units per second (0 when the adapter cannot report it).
    public var vx: Double
    public var vy: Double
    /// Contact size / pressure proxy reported by the sensor (roughly 0…3; 0 when unknown).
    public var size: Double
    /// Contact ellipse in millimetres (0 when unknown).
    public var majorAxis: Double
    public var minorAxis: Double
    /// Ellipse orientation in radians.
    public var angle: Double
    public var phase: ContactPhase

    public init(id: Int, x: Double, y: Double, vx: Double = 0, vy: Double = 0, size: Double = 0.5,
                majorAxis: Double = 0, minorAxis: Double = 0, angle: Double = 0, phase: ContactPhase = .moved) {
        self.id = id; self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.size = size
        self.majorAxis = majorAxis; self.minorAxis = minorAxis; self.angle = angle; self.phase = phase
    }

    /// True while the finger is physically on the surface in this frame.
    public var isTouching: Bool { phase == .began || phase == .moved || phase == .stationary }
}

/// One sample of the whole touch surface. A frame with no touching contacts marks "all fingers lifted".
public struct TouchFrame: Codable, Sendable, Equatable {
    /// Seconds on the monotonic clock (`MonotonicClock.now()` timebase).
    public var timestamp: TimeInterval
    /// Identifies the originating device (adapter specific; 0 for synthetic input).
    public var deviceID: UInt64
    public var contacts: [TouchContact]

    public init(timestamp: TimeInterval, deviceID: UInt64 = 0, contacts: [TouchContact]) {
        self.timestamp = timestamp; self.deviceID = deviceID; self.contacts = contacts
    }

    public var touching: [TouchContact] { contacts.filter(\.isTouching) }
}

/// Physical size of the touch-sensitive area, used to convert normalized coordinates to millimetres.
public struct SurfaceGeometry: Codable, Sendable, Equatable {
    public var widthMM: Double
    public var heightMM: Double
    public init(widthMM: Double, heightMM: Double) { self.widthMM = widthMM; self.heightMM = heightMM }
    /// Approximate touch area of Magic Mouse 2 / USB-C (the first generation is nearly identical).
    public static let magicMouse = SurfaceGeometry(widthMM: 52, heightMM: 90)
}

/// What an input adapter can actually deliver. Gestures are only offered when the active
/// adapter satisfies `GestureKind.requirement`.
public struct InputCapabilities: Codable, Sendable, Equatable {
    /// Per-finger coordinates are available.
    public var rawContacts: Bool
    /// Maximum simultaneous contacts the adapter reports (0 when `rawContacts` is false).
    public var maxContacts: Int
    /// Contact size / ellipse data is available (enables resting-finger and palm rejection).
    public var contactSize: Bool
    /// Global mouse button / scroll events can be observed and modified (CGEventTap).
    public var pointerEvents: Bool

    public init(rawContacts: Bool, maxContacts: Int, contactSize: Bool, pointerEvents: Bool) {
        self.rawContacts = rawContacts; self.maxContacts = maxContacts
        self.contactSize = contactSize; self.pointerEvents = pointerEvents
    }
    public static let none = InputCapabilities(rawContacts: false, maxContacts: 0, contactSize: false, pointerEvents: false)
}
