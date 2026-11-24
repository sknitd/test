# Compatibility

| | Supported | Notes |
| --- | --- | --- |
| macOS | 14 Sonoma and newer | Deployment target 14.0. Built and self-tested in CI on macOS 15 only; macOS 14 itself and macOS 26 are compiled-for but not run by this project. |
| Hardware | Apple silicon and Intel | Release builds are universal (`arm64` + `x86_64`); CI verifies both slices are present with `lipo`. Only the arm64 slice is executed in CI. |
| Xcode | 16 or newer | Required by the project format (synchronised folder groups). Swift language mode 5. |
| Swift package (core tests) | Swift 5.9+ on macOS; Swift 5.10 on Linux | Linux builds the platform-independent core only. |

## Behaviour by configuration

| Configuration | Overlay widgets | WidgetKit widget | Scripts |
| --- | --- | --- | --- |
| Developer ID or development team signing | Yes | Yes (App Group shared) | Yes, if the watchdog symbol is present |
| Ad-hoc / "Sign to Run Locally" | Yes | May be unable to read the shared snapshot; macOS 15+ may prompt for cross-app data access | Yes |
| Mac App Store | Yes | Yes | Should be disabled: the script watchdog uses WebKit SPI |

## Interaction modes and window configurations

| Mode | Desktop layer (default) | Pinned (floating) |
| --- | --- | --- |
| Normal | Above wallpaper and icons, below app windows; clickable; on all Spaces; absent from full-screen Spaces | Above normal windows; on all Spaces including full screen |
| Edit | Temporarily raised to floating level so widgets cannot be lost behind windows; drag, resize, arrow-key nudge | Same |
| Click-through | Pointer events pass to the desktop or window underneath; the widget cannot be interacted with until click-through is turned off from the menu bar, Command Center or My Widgets | Same |

Edit mode always overrides click-through, so a widget can never become unreachable.

## macOS version differences to be aware of

- **macOS 14+**: clicking the wallpaper can trigger "Show Desktop". Whether overlay widgets stay put
  when other windows move aside has not been verified on hardware (see `LIMITATIONS.md`). The setting is
  under *System Settings → Desktop & Dock → Click wallpaper to reveal desktop*.
- **macOS 15+**: accessing another app's group container shows a consent prompt when signatures do not
  share a team; relevant only to ad-hoc builds.
- **macOS 15.4+ / 16**: programmatic pasteboard reads may be announced to the user. The Clipboard widget
  reads only when its button is pressed.
- **Stage Manager**: untested.

## Displays

- Placement is stored relative to a display's visible frame and keyed by the display's UUID.
- When a display disappears its widgets are shown on the main display, clamped on-screen; the saved
  placement is kept, so they return when the display is reconnected (`testPlacementSurvivesDisplayDisconnect`).
- Retina and scaled modes need no special handling: everything is laid out in points and drawn by SwiftUI.
- Per-display profiles are supported through "display connected" profile rules. Per-Space layouts are
  not, because macOS exposes no public Space identity.
