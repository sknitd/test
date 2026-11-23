import Foundation
import MFCore

/// One tracked finger contact. All distances are millimetres on the surface.
struct ContactTrack {
    enum Role {
        /// May join (or is part of) the current episode.
        case candidate
        /// Resting finger: ignored until it lifts.
        case resting
        /// Palm-sized contact: ignored until it lifts.
        case palm
        /// Survived a frame gap: ignored until it lifts.
        case quarantined
    }

    let id: Int
    let startTime: TimeInterval
    let startX: Double
    let startY: Double
    let startXMM: Double
    let startYMM: Double
    var x: Double
    var y: Double
    var xMM: Double
    var yMM: Double
    /// Where the current stroke is measured from (the landing point, or the hold point).
    var originXMM: Double
    var originYMM: Double
    /// Path length travelled since `origin`.
    var pathMM: Double = 0
    /// Largest distance from the landing point ever seen.
    var maxDisplacementMM: Double = 0
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    /// Resting detection: the contact has stayed within `restRadiusMM` of the anchor since `anchorTime`.
    var anchorXMM: Double
    var anchorYMM: Double
    var anchorTime: TimeInterval
    var maxSize: Double
    var role: Role = .candidate
    var isMember = false
    var seen = true
    var endedCancelled = false

    init(contact: TouchContact, now: TimeInterval, widthMM: Double, heightMM: Double) {
        id = contact.id
        startTime = now
        startX = contact.x; startY = contact.y
        x = contact.x; y = contact.y
        xMM = contact.x * widthMM; yMM = contact.y * heightMM
        startXMM = xMM; startYMM = yMM
        originXMM = xMM; originYMM = yMM
        minX = contact.x; maxX = contact.x; minY = contact.y; maxY = contact.y
        anchorXMM = xMM; anchorYMM = yMM; anchorTime = now
        maxSize = contact.size
    }

    mutating func reanchorOrigin() {
        originXMM = xMM; originYMM = yMM; pathMM = 0
    }
}

/// One touch "episode": from the first counted finger landing until every counted finger has
/// lifted (or turned into a resting finger).
struct Episode {
    enum Phase { case idle, tracking, held, fired, cancelled }

    var phase: Phase = .idle
    var startTime: TimeInterval = 0
    var lastLandTime: TimeInterval = 0
    /// Number of fingers that landed inside the landing window.
    var peakCount = 0
    /// Members currently on the surface.
    var touching = 0
    var liftedAny = false
    /// Largest displacement from its landing point of any member, ever.
    var maxDisplacementMM: Double = 0
    /// Last time the stroke was still within the motion slop (start of the current stroke).
    var moveStartTime: TimeInterval = 0
    var holdTime: TimeInterval = 0
    var holdConfidence: Double = 0
    var sumStartX: Double = 0
    var sumStartY: Double = 0
    /// The pending single tap is waiting on this episode (double tap / tap-then-swipe).
    var claimsPending = false
    var cancelReason = ""
    var firedKind: GestureKind?
    var firedConfidence: Double = 0

    var originX: Double { peakCount > 0 ? sumStartX / Double(peakCount) : 0.5 }
    var originY: Double { peakCount > 0 ? sumStartY / Double(peakCount) : 0.5 }
}

/// A completed tap that has not been emitted yet because a double tap or tap-then-swipe with
/// the same finger count is enabled.
struct PendingTap {
    var count: Int
    var startTime: TimeInterval
    var liftTime: TimeInterval
    var originX: Double
    var originY: Double
    /// Most specific enabled single-tap kind, nil when no single-tap kind is enabled.
    var kind: GestureKind?
    var confidence: Double
    /// Unclaimed pending taps are emitted at this time.
    var deadline: TimeInterval
    /// A new episode began inside the window; resolution now depends on that episode.
    var claimed = false
}
