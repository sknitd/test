import CoreFoundation
import Foundation

// PRIVATE / UNSUPPORTED
// ---------------------
// Everything in this file mirrors data structures of Apple's private MultitouchSupport.framework
// as reverse engineered by the community (MiddleClick, OpenMultitouchSupport, M5MultitouchSupport,
// Hammerspoon's undocumented touchdevice module, …). Apple publishes no header and gives no
// stability guarantee: the layout can change in any macOS release. `MTTouchLayout.validate()`
// is checked before any stream is started so that a mismatch disables the adapter instead of
// reading garbage.

/// PRIVATE/UNSUPPORTED. Two packed 32-bit floats (C `struct { float x, y; }`). 8 bytes.
struct MTPoint {
    var x: Float
    var y: Float
}

/// PRIVATE/UNSUPPORTED. Position + velocity (C `struct { MTPoint position, velocity; }`). 16 bytes.
struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// PRIVATE/UNSUPPORTED. One contact as delivered to a contact-frame callback.
///
/// C layout on 64-bit macOS (arm64 and x86_64), as commonly reverse engineered:
///
///     offset size field
///          0    4 int32   frame            frame counter
///          4    4 (padding so that the double is 8-byte aligned)
///          8    8 double  timestamp        seconds
///         16    4 int32   identifier       path id, stable while the finger stays down
///         20    4 int32   state            MTTouchState (see below)
///         24    4 int32   fingerID         finger classification (thumb, index, …)
///         28    4 int32   handID
///         32   16 MTVector normalized      position 0…1 and velocity (1/s)
///         48    4 float   total            total capacitance ("size", roughly 0…3)
///         52    4 int32/float field9       unknown (some headers call it pressure)
///         56    4 float   angle            ellipse orientation, radians
///         60    4 float   majorAxis        ellipse, millimetres
///         64    4 float   minorAxis        ellipse, millimetres
///         68   16 MTVector absolute        position (mm) and velocity (mm/s)
///         84    4 int32   field14          unknown
///         88    4 int32   field15          unknown
///         92    4 float   density          capacitance density
///         96      total (alignment 8)
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector
    var total: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var field14: Int32
    var field15: Int32
    var density: Float
}

/// PRIVATE/UNSUPPORTED. Values of `MTTouch.state` ("path stage").
///
/// Only `makeTouch`, `touching` and `breakTouch` describe a finger that is (or just was) in
/// contact with the surface. The other stages describe a finger hovering within sensing range
/// and are never reported as touching contacts.
enum MTTouchState {
    static let notTracking: Int32 = 0
    static let startInRange: Int32 = 1
    static let hoverInRange: Int32 = 2
    static let makeTouch: Int32 = 3
    static let touching: Int32 = 4
    static let breakTouch: Int32 = 5
    static let lingerInRange: Int32 = 6
    static let outOfRange: Int32 = 7

    /// True for the stages in which the finger is physically on the surface.
    static func isOnSurface(_ state: Int32) -> Bool {
        state == makeTouch || state == touching
    }
}

/// Runtime verification that the Swift mirror of `MTTouch` has the documented C layout.
enum MTTouchLayout {
    static let expectedStride = 96
    static let expectedAlignment = 8

    /// Returns nil when the layout matches, otherwise a description of the first mismatch.
    static func validate() -> String? {
        if MemoryLayout<MTTouch>.stride != expectedStride {
            return "MTTouch stride is \(MemoryLayout<MTTouch>.stride) bytes, expected \(expectedStride)"
        }
        if MemoryLayout<MTTouch>.alignment != expectedAlignment {
            return "MTTouch alignment is \(MemoryLayout<MTTouch>.alignment), expected \(expectedAlignment)"
        }
        let checks: [(String, Int?, Int)] = [
            ("frame", MemoryLayout<MTTouch>.offset(of: \MTTouch.frame), 0),
            ("timestamp", MemoryLayout<MTTouch>.offset(of: \MTTouch.timestamp), 8),
            ("identifier", MemoryLayout<MTTouch>.offset(of: \MTTouch.identifier), 16),
            ("state", MemoryLayout<MTTouch>.offset(of: \MTTouch.state), 20),
            ("fingerID", MemoryLayout<MTTouch>.offset(of: \MTTouch.fingerID), 24),
            ("handID", MemoryLayout<MTTouch>.offset(of: \MTTouch.handID), 28),
            ("normalized", MemoryLayout<MTTouch>.offset(of: \MTTouch.normalized), 32),
            ("total", MemoryLayout<MTTouch>.offset(of: \MTTouch.total), 48),
            ("field9", MemoryLayout<MTTouch>.offset(of: \MTTouch.field9), 52),
            ("angle", MemoryLayout<MTTouch>.offset(of: \MTTouch.angle), 56),
            ("majorAxis", MemoryLayout<MTTouch>.offset(of: \MTTouch.majorAxis), 60),
            ("minorAxis", MemoryLayout<MTTouch>.offset(of: \MTTouch.minorAxis), 64),
            ("absolute", MemoryLayout<MTTouch>.offset(of: \MTTouch.absolute), 68),
            ("field14", MemoryLayout<MTTouch>.offset(of: \MTTouch.field14), 84),
            ("field15", MemoryLayout<MTTouch>.offset(of: \MTTouch.field15), 88),
            ("density", MemoryLayout<MTTouch>.offset(of: \MTTouch.density), 92),
        ]
        for (name, actual, expected) in checks where actual != expected {
            let found: String = actual.map { String($0) } ?? "unknown"
            return "MTTouch.\(name) is at offset \(found), expected \(expected)"
        }
        return nil
    }
}
