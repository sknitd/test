import Foundation

// Display metadata for gestures. Pure data: no behaviour lives here.
// Symbol names are SF Symbols that ship with macOS 14.

public extension GestureKind.Direction {
    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Up"
        case .down: return "Down"
        }
    }

    /// Plain arrow symbol for this direction.
    var symbolName: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        }
    }
}

public extension GestureKind.Category {
    var displayName: String {
        switch self {
        case .oneFinger: return "One Finger"
        case .twoFinger: return "Two Fingers"
        case .threeFinger: return "Three Fingers"
        case .zones: return "Zones"
        case .compound: return "Compound"
        case .fallback: return "Modifier Chords"
        }
    }

    var symbolName: String {
        switch self {
        case .oneFinger: return "hand.point.up.left"
        case .twoFinger: return "hand.draw"
        case .threeFinger: return "hand.raised"
        case .zones: return "square.grid.3x3"
        case .compound: return "arrow.triangle.branch"
        case .fallback: return "keyboard"
        }
    }

    /// One line describing what the category contains.
    var summary: String {
        switch self {
        case .oneFinger: return "Taps, holds and edge slides made with a single finger."
        case .twoFinger: return "Taps, swipes, pinches and rotations made with two fingers."
        case .threeFinger: return "Taps, holds and swipes made with three fingers."
        case .zones: return "Taps in a specific corner or the centre of the surface."
        case .compound: return "A tap or hold followed immediately by a swipe."
        case .fallback: return "Control+Option with a click or scroll. Works without raw touch data."
        }
    }
}

public extension GestureKind {
    /// Movement direction for directional gestures, nil for everything else.
    var direction: Direction? {
        switch self {
        case .oneFingerSwipeLeft, .twoFingerSwipeLeft, .threeFingerSwipeLeft, .tapThenSwipeLeft, .holdThenSwipeLeft,
             .chordScrollLeft:
            return .left
        case .oneFingerSwipeRight, .twoFingerSwipeRight, .threeFingerSwipeRight, .tapThenSwipeRight,
             .holdThenSwipeRight, .chordScrollRight:
            return .right
        case .oneFingerSwipeUp, .twoFingerSwipeUp, .threeFingerSwipeUp, .tapThenSwipeUp, .holdThenSwipeUp,
             .chordScrollUp:
            return .up
        case .oneFingerSwipeDown, .twoFingerSwipeDown, .threeFingerSwipeDown, .tapThenSwipeDown, .holdThenSwipeDown,
             .chordScrollDown:
            return .down
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .oneFingerTap: return "One-Finger Tap"
        case .oneFingerDoubleTap: return "One-Finger Double Tap"
        case .oneFingerHold: return "One-Finger Hold"
        case .leftEdgeSwipe: return "Left Edge Slide"
        case .rightEdgeSwipe: return "Right Edge Slide"
        case .topEdgeSwipe: return "Front Edge Slide"
        case .bottomEdgeSwipe: return "Rear Edge Slide"
        case .oneFingerSwipeLeft: return "One-Finger Swipe Left"
        case .oneFingerSwipeRight: return "One-Finger Swipe Right"
        case .oneFingerSwipeUp: return "One-Finger Swipe Up"
        case .oneFingerSwipeDown: return "One-Finger Swipe Down"
        case .twoFingerTap: return "Two-Finger Tap"
        case .twoFingerDoubleTap: return "Two-Finger Double Tap"
        case .twoFingerHold: return "Two-Finger Hold"
        case .twoFingerSwipeLeft: return "Two-Finger Swipe Left"
        case .twoFingerSwipeRight: return "Two-Finger Swipe Right"
        case .twoFingerSwipeUp: return "Two-Finger Swipe Up"
        case .twoFingerSwipeDown: return "Two-Finger Swipe Down"
        case .pinchIn: return "Pinch In"
        case .pinchOut: return "Pinch Out"
        case .rotateClockwise: return "Rotate Clockwise"
        case .rotateCounterclockwise: return "Rotate Counterclockwise"
        case .threeFingerTap: return "Three-Finger Tap"
        case .threeFingerHold: return "Three-Finger Hold"
        case .threeFingerSwipeLeft: return "Three-Finger Swipe Left"
        case .threeFingerSwipeRight: return "Three-Finger Swipe Right"
        case .threeFingerSwipeUp: return "Three-Finger Swipe Up"
        case .threeFingerSwipeDown: return "Three-Finger Swipe Down"
        case .cornerTapTopLeft: return "Front-Left Corner Tap"
        case .cornerTapTopRight: return "Front-Right Corner Tap"
        case .cornerTapBottomLeft: return "Rear-Left Corner Tap"
        case .cornerTapBottomRight: return "Rear-Right Corner Tap"
        case .centerTap: return "Centre Tap"
        case .tapThenSwipeLeft: return "Tap, then Swipe Left"
        case .tapThenSwipeRight: return "Tap, then Swipe Right"
        case .tapThenSwipeUp: return "Tap, then Swipe Up"
        case .tapThenSwipeDown: return "Tap, then Swipe Down"
        case .holdThenSwipeLeft: return "Hold, then Swipe Left"
        case .holdThenSwipeRight: return "Hold, then Swipe Right"
        case .holdThenSwipeUp: return "Hold, then Swipe Up"
        case .holdThenSwipeDown: return "Hold, then Swipe Down"
        case .chordLeftClick: return "⌃⌥ Left Click"
        case .chordRightClick: return "⌃⌥ Right Click"
        case .chordScrollUp: return "⌃⌥ Scroll Up"
        case .chordScrollDown: return "⌃⌥ Scroll Down"
        case .chordScrollLeft: return "⌃⌥ Scroll Left"
        case .chordScrollRight: return "⌃⌥ Scroll Right"
        }
    }

    var symbolName: String {
        switch self {
        case .oneFingerTap, .twoFingerTap, .threeFingerTap: return "hand.tap"
        case .oneFingerDoubleTap, .twoFingerDoubleTap: return "hand.tap.fill"
        case .oneFingerHold, .twoFingerHold, .threeFingerHold: return "hand.point.up.left.fill"
        case .leftEdgeSwipe, .rightEdgeSwipe: return "arrow.up.and.down"
        case .topEdgeSwipe, .bottomEdgeSwipe: return "arrow.left.and.right"
        case .oneFingerSwipeLeft, .twoFingerSwipeLeft, .threeFingerSwipeLeft: return "arrow.left"
        case .oneFingerSwipeRight, .twoFingerSwipeRight, .threeFingerSwipeRight: return "arrow.right"
        case .oneFingerSwipeUp, .twoFingerSwipeUp, .threeFingerSwipeUp: return "arrow.up"
        case .oneFingerSwipeDown, .twoFingerSwipeDown, .threeFingerSwipeDown: return "arrow.down"
        case .pinchIn: return "arrow.down.right.and.arrow.up.left"
        case .pinchOut: return "arrow.up.left.and.arrow.down.right"
        case .rotateClockwise: return "arrow.clockwise"
        case .rotateCounterclockwise: return "arrow.counterclockwise"
        case .cornerTapTopLeft: return "arrow.up.left"
        case .cornerTapTopRight: return "arrow.up.right"
        case .cornerTapBottomLeft: return "arrow.down.left"
        case .cornerTapBottomRight: return "arrow.down.right"
        case .centerTap: return "scope"
        case .tapThenSwipeLeft: return "arrow.left.circle"
        case .tapThenSwipeRight: return "arrow.right.circle"
        case .tapThenSwipeUp: return "arrow.up.circle"
        case .tapThenSwipeDown: return "arrow.down.circle"
        case .holdThenSwipeLeft: return "arrow.left.circle.fill"
        case .holdThenSwipeRight: return "arrow.right.circle.fill"
        case .holdThenSwipeUp: return "arrow.up.circle.fill"
        case .holdThenSwipeDown: return "arrow.down.circle.fill"
        case .chordLeftClick: return "cursorarrow.click"
        case .chordRightClick: return "cursorarrow.click.2"
        case .chordScrollUp: return "arrow.up.square"
        case .chordScrollDown: return "arrow.down.square"
        case .chordScrollLeft: return "arrow.left.square"
        case .chordScrollRight: return "arrow.right.square"
        }
    }

    /// One line explaining how to perform the gesture.
    var summary: String {
        switch self {
        case .oneFingerTap: return "Touch the surface briefly with one finger, without pressing the button."
        case .oneFingerDoubleTap: return "Tap twice in quick succession with one finger."
        case .oneFingerHold: return "Rest one finger still on the surface for about half a second."
        case .leftEdgeSwipe: return "Slide one finger forwards or backwards along the left edge."
        case .rightEdgeSwipe: return "Slide one finger forwards or backwards along the right edge."
        case .topEdgeSwipe: return "Slide one finger sideways along the front edge, nearest the screen."
        case .bottomEdgeSwipe: return "Slide one finger sideways along the rear edge, nearest your palm."
        case .oneFingerSwipeLeft: return "Swipe left with one finger. This also scrolls, so every scroll fires it."
        case .oneFingerSwipeRight: return "Swipe right with one finger. This also scrolls, so every scroll fires it."
        case .oneFingerSwipeUp: return "Swipe forwards with one finger. This also scrolls, so every scroll fires it."
        case .oneFingerSwipeDown: return "Swipe backwards with one finger. This also scrolls, so every scroll fires it."
        case .twoFingerTap: return "Touch the surface briefly with two fingers at the same time."
        case .twoFingerDoubleTap: return "Tap twice in quick succession with two fingers."
        case .twoFingerHold: return "Rest two fingers still on the surface for about half a second."
        case .twoFingerSwipeLeft: return "Swipe left with two fingers side by side."
        case .twoFingerSwipeRight: return "Swipe right with two fingers side by side."
        case .twoFingerSwipeUp: return "Swipe forwards, towards the screen, with two fingers."
        case .twoFingerSwipeDown: return "Swipe backwards, towards your palm, with two fingers."
        case .pinchIn: return "Move two fingers towards each other."
        case .pinchOut: return "Spread two fingers apart."
        case .rotateClockwise: return "Twist two fingers clockwise around their midpoint."
        case .rotateCounterclockwise: return "Twist two fingers counterclockwise around their midpoint."
        case .threeFingerTap: return "Touch the surface briefly with three fingers at the same time."
        case .threeFingerHold: return "Rest three fingers still on the surface for about half a second."
        case .threeFingerSwipeLeft: return "Swipe left with three fingers."
        case .threeFingerSwipeRight: return "Swipe right with three fingers."
        case .threeFingerSwipeUp: return "Swipe forwards, towards the screen, with three fingers."
        case .threeFingerSwipeDown: return "Swipe backwards, towards your palm, with three fingers."
        case .cornerTapTopLeft: return "Tap the front-left corner of the surface with one finger."
        case .cornerTapTopRight: return "Tap the front-right corner of the surface with one finger."
        case .cornerTapBottomLeft: return "Tap the rear-left corner of the surface with one finger."
        case .cornerTapBottomRight: return "Tap the rear-right corner of the surface with one finger."
        case .centerTap: return "Tap the middle of the surface with one finger."
        case .tapThenSwipeLeft: return "Tap once, then immediately swipe left with one finger."
        case .tapThenSwipeRight: return "Tap once, then immediately swipe right with one finger."
        case .tapThenSwipeUp: return "Tap once, then immediately swipe forwards with one finger."
        case .tapThenSwipeDown: return "Tap once, then immediately swipe backwards with one finger."
        case .holdThenSwipeLeft: return "Hold one finger still, then swipe left without lifting."
        case .holdThenSwipeRight: return "Hold one finger still, then swipe right without lifting."
        case .holdThenSwipeUp: return "Hold one finger still, then swipe forwards without lifting."
        case .holdThenSwipeDown: return "Hold one finger still, then swipe backwards without lifting."
        case .chordLeftClick: return "Hold Control and Option, then click the left button."
        case .chordRightClick: return "Hold Control and Option, then click the right button."
        case .chordScrollUp: return "Hold Control and Option, then scroll up."
        case .chordScrollDown: return "Hold Control and Option, then scroll down."
        case .chordScrollLeft: return "Hold Control and Option, then scroll left."
        case .chordScrollRight: return "Hold Control and Option, then scroll right."
        }
    }
}

public extension GestureTrigger {
    /// A single gesture's name, or the sequence joined with arrows.
    var displayName: String {
        switch self {
        case .single(let kind):
            return kind.displayName
        case .sequence(let kinds):
            if kinds.isEmpty { return "Empty Sequence" }
            return kinds.map(\.displayName).joined(separator: " → ")
        }
    }

    var symbolName: String {
        switch self {
        case .single(let kind): return kind.symbolName
        case .sequence: return "list.number"
        }
    }
}
