import Foundation
import MFCore

/// App-specific default profiles. They use deliberate gestures (hold-then-swipe, rotate, corner
/// and multi-finger taps) that never collide with scrolling, and plain keyboard shortcuts so the
/// result is visible and easy to change.
enum DefaultProfiles {
    static func appProfiles() -> [Profile] { [safari(), chrome(), finder(), vsCode(), photos()] }

    static func safari() -> Profile {
        browser(scope: "safari", name: "Safari", symbol: "safari", bundleID: DefaultConfiguration.safariBundleID)
    }

    static func chrome() -> Profile {
        browser(scope: "chrome", name: "Google Chrome", symbol: "globe", bundleID: DefaultConfiguration.chromeBundleID)
    }

    private static func browser(scope: String, name: String, symbol: String, bundleID: String) -> Profile {
        var builder = BindingBuilder(scope: scope)
        builder.add(.holdThenSwipeLeft, .keyboard(DefaultKeys.back), note: "Back")
        builder.add(.holdThenSwipeRight, .keyboard(DefaultKeys.forward), note: "Forward")
        builder.add(.rotateClockwise, .keyboard(DefaultKeys.nextTab), note: "Next tab")
        builder.add(.rotateCounterclockwise, .keyboard(DefaultKeys.previousTab), note: "Previous tab")
        builder.add(.cornerTapTopRight, .keyboard(DefaultKeys.newTab), note: "New tab")
        return profile(scope, name, symbol, bundleID, builder)
    }

    static func finder() -> Profile {
        var builder = BindingBuilder(scope: "finder")
        builder.add(.holdThenSwipeLeft, .keyboard(DefaultKeys.back), note: "Back")
        builder.add(.holdThenSwipeRight, .keyboard(DefaultKeys.forward), note: "Forward")
        builder.add(.holdThenSwipeUp, .keyboard(DefaultKeys.enclosingFolder), note: "Enclosing folder")
        builder.add(.holdThenSwipeDown, .keyboard(DefaultKeys.goToDownloads), note: "Go to Downloads")
        builder.add(.threeFingerTap, .keyboard(DefaultKeys.quickLook), note: "Quick Look")
        builder.add(.cornerTapTopRight, .keyboard(DefaultKeys.newFolder), note: "New folder")
        return profile("finder", "Finder", "folder", DefaultConfiguration.finderBundleID, builder)
    }

    static func vsCode() -> Profile {
        var builder = BindingBuilder(scope: "vscode")
        builder.add(.threeFingerTap, .keyboard(DefaultKeys.commandPalette), note: "Command Palette")
        builder.add(.twoFingerSwipeDown, .keyboard(DefaultKeys.toggleTerminal), note: "Toggle terminal")
        builder.add(.rotateClockwise, .keyboard(DefaultKeys.nextTab), note: "Next editor")
        builder.add(.rotateCounterclockwise, .keyboard(DefaultKeys.previousTab), note: "Previous editor")
        builder.add(.holdThenSwipeLeft, .keyboard(DefaultKeys.codeGoBack), note: "Go back")
        builder.add(.holdThenSwipeRight, .keyboard(DefaultKeys.codeGoForward), note: "Go forward")
        return profile("vscode", "Visual Studio Code", "chevron.left.forwardslash.chevron.right",
                       DefaultConfiguration.vsCodeBundleID, builder)
    }

    static func photos() -> Profile {
        var builder = BindingBuilder(scope: "photos")
        builder.add(.pinchOut, .keyboard(DefaultKeys.zoomIn), note: "Zoom in")
        builder.add(.pinchIn, .keyboard(DefaultKeys.zoomOut), note: "Zoom out")
        builder.add(.rotateClockwise, .keyboard(DefaultKeys.rotateClockwise), note: "Rotate clockwise")
        builder.add(.rotateCounterclockwise, .keyboard(DefaultKeys.rotateCounterclockwise), note: "Rotate counterclockwise")
        builder.add(.holdThenSwipeLeft, .keyboard(DefaultKeys.previousItem), note: "Previous photo")
        builder.add(.holdThenSwipeRight, .keyboard(DefaultKeys.nextItem), note: "Next photo")
        return profile("photos", "Photos", "photo.on.rectangle", DefaultConfiguration.photosBundleID, builder)
    }

    /// Not part of the default configuration (it has no app): shipped as a sample file and
    /// meant to be switched on manually.
    static func windowManagement() -> Profile {
        var builder = BindingBuilder(scope: "windows")
        builder.add(.holdThenSwipeLeft, .window(.snapLeft))
        builder.add(.holdThenSwipeRight, .window(.snapRight))
        builder.add(.holdThenSwipeUp, .window(.maximize))
        builder.add(.holdThenSwipeDown, .window(.restorePreviousFrame))
        builder.add(.threeFingerTap, .window(.center))
        builder.add(.pinchOut, .window(.resize(byFraction: 0.1)), note: "Grow the window")
        builder.add(.pinchIn, .window(.resize(byFraction: -0.1)), note: "Shrink the window")
        builder.add(.cornerTapTopRight, .window(.moveToNextDisplay))
        return Profile(id: DefaultConfiguration.id("profile.windows"), name: "Window Management",
                       symbolName: "macwindow.on.rectangle", bindings: builder.bindings)
    }

    private static func profile(_ scope: String, _ name: String, _ symbol: String, _ bundleID: String,
                                _ builder: BindingBuilder) -> Profile {
        Profile(id: DefaultConfiguration.id("profile." + scope), name: name, symbolName: symbol,
                bundleIdentifiers: [bundleID], bindings: builder.bindings)
    }
}
