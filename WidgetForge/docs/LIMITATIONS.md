# Limitations and unsupported features

Stated plainly so nobody discovers them the hard way.

## Not verified on real hardware
This project was written on Linux. Everything was compiled and unit-tested on macOS in CI, and the built
app was launched there by an automated self-test, but **no person has used the UI on a Mac**. Until
someone does, treat these as untested:

- dragging and resizing widgets with the mouse in Edit mode (the store path it calls is tested; the
  AppKit mouse tracking is not)
- how desktop-level widgets behave with Show Desktop, Stage Manager, Mission Control and Spaces switches
- text entry in Notes / To-do widgets inside non-activating panels
- the Builder's canvas gestures, drop from palette, keyboard shortcuts and marquee selection
- the Command Center panel and its global shortcut
- the WidgetKit widget in the system gallery, its configuration UI and App Intent buttons
- multi-display rearrangement while running, sleep/wake, launch at login
- calendar, notification, Apple Events (Music) and Keychain consent prompts
- VoiceOver output (labels are provided; nobody has listened to them)

## Platform limits (by design of macOS)
- **WidgetKit widgets are not real-time** and cannot run scripts, show web content or accept text input.
  Their metrics are labelled "as of" the last timeline reload.
- **No per-Space widget placement or profiles**: there is no public API to identify Spaces.
- **Widgets cover desktop icons beneath them.** Move them, hide them or make them click-through.
- **Click-through is per widget, all or nothing.**
- **Media controls work with Apple Music only.** macOS has no public system-wide media control API.
- **Per-core CPU, disk activity and memory pressure** come from Mach/IOKit/sysctl interfaces that are
  long-standing but not all formally documented; each degrades to "unavailable" rather than a fake value.

## Security limits
- The script runtime is a capability-restricted interpreter, **not an OS sandbox**. See `SECURITY.md`.
- Runaway-script termination depends on a WebKit SPI. If it is missing, scripts are disabled.
- The out-of-process (XPC) script host that would make unattended third-party scripts safe is designed
  but not built.
- Widget files are checksummed against corruption, not signed. There is no publisher identity.

## Limits of the newer features
- **Backups** are plain JSON, not encrypted, and include your widget state (notes, to-dos). They exclude
  secrets and file choices, so API keys and file data sources must be set up again after a restore.
  Restore replaces the whole setup; there is no merge.
- **Tidy Up** keeps widget order and sizes and packs greedily; it does not try to minimise empty space,
  and widgets that cannot fit on a display are clamped (they may overlap in that case).
- **Themes** restyle the container only. A component with its own explicit colours keeps them.
- **Sustained-metric triggers** are evaluated on metric samples (every 1–10 s), so durations are accurate
  to one sampling interval, and they only run while WidgetForge is running and not paused.
- **URL scheme and Shortcuts actions** are unit-tested as a parser and compiled, but have not been invoked
  from Shortcuts or a browser by anyone.

## Product gaps
- **Marketplace is local only**: a library plus import/export of `.wfwidget` files. No online catalogue.
- **Builder edits absolute (canvas) layouts.** Flow-layout widgets (most templates) open wrapped as one
  canvas child; their inner structure is edited through the layer list and inspector, not by dragging.
- **Component grouping** selects and moves members together; it does not create a nested container.
- **Undo granularity**: each keystroke in an inspector text field is its own undo step.
- **Animations** are limited to fade, pulse and bounce on a component.
- **Chart tooltips** exist in the overlay only; **data export** is CSV of a chart's current points.
- **Stocks** need a Finnhub key; **weather** needs coordinates typed in (no location lookup, by choice:
  it would need Location Services).
- **Automations run with the user's authority**, not a widget's permissions, because the user writes them.
- **No localisation** beyond English. **No UI tests.** **No Xcode test target** (tests run with `swift test`).
- **Profiles hide and show widgets**; a widget's state and data are shared across profiles.
- **Notarised release**: not produced. CI builds are ad-hoc signed.
