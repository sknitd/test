# Platform feasibility

This is the investigation that shaped WidgetForge's design. Each finding is labelled with how it is known:

- **[Doc]** stated in Apple's public documentation or headers
- **[CI]** observed by the automated self-test on a GitHub-hosted macOS runner (see `PROGRESS.md` for the run)
- **[Unverified]** reasoned from documentation and experience, not yet confirmed on real hardware by this project

The development machine for this project was Linux, so nothing here was verified interactively on a Mac
by the author. Where that matters, it says so.

## 1. WidgetKit on macOS 14

| Question | Finding |
| --- | --- |
| Desktop placement | macOS 14 lets users place WidgetKit widgets on the desktop as well as in Notification Centre. Apps cannot place, move or size them; the user does, from the widget gallery. **[Doc]** |
| Execution model | A widget is not a running view. The extension returns a **timeline** of entries; the system archives the SwiftUI view for each entry and shows it at the entry's date. No code of ours runs while a widget is on screen. **[Doc]** |
| Refresh | The extension asks for the next reload (`.after(date)`, `.atEnd`) or the app calls `WidgetCenter.reloadTimelines`. The system budgets reloads per widget (Apple's guidance is on the order of tens per day) and may defer them. Continuous or per-second updates are not possible. **[Doc]** |
| Time display | `Text(date, style:)` and pre-computed minute entries keep clocks current without reloads. **[Doc]** |
| Interactivity | Since macOS 14, `Button(intent:)` and `Toggle(isOn:intent:)` run an **App Intent** in the extension process, after which the timeline reloads. No text fields, sliders, gestures, scrolling or hover. **[Doc]** |
| Configuration | `AppIntentConfiguration` with a `WidgetConfigurationIntent`; parameters can be `AppEntity` values supplied by an `EntityQuery`. **[Doc]** |
| Sizes | `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge` on macOS. **[Doc]** |
| JavaScript | JavaScriptCore can technically be linked into an extension, but there is no lifetime to run it in: the process is launched briefly for a timeline and may be killed at any time. WebKit views are not supported in widgets. **[Doc]** |
| Shared data | The extension is sandboxed and separate from the app. Data is shared through an **App Group** container. On macOS the group id must be prefixed with the Team ID (or be provisioned), so correct sharing needs both targets signed by the same team. **[Doc]** |
| Appearance | On the desktop, widgets are drawn desaturated when a window is in front; `containerBackground(for: .widget)` is required. **[Doc]** |

**Conclusion.** WidgetKit cannot host arbitrary, continuously running, scripted widgets, and WidgetForge
does not try to make it. It is used for what it is good at: battery-efficient, system-integrated,
timeline-driven views of a widget, with App Intent buttons for state changes.

## 2. Desktop-level windows

| Question | Finding |
| --- | --- |
| Window type | A borderless `NSPanel` with `.nonactivatingPanel` receives clicks without activating the app or stealing focus from the frontmost app. `becomesKeyOnlyIfNeeded` limits key status to text entry. **[Doc]** |
| Level | `CGWindowLevelForKey(.desktopIconWindow) + 1` places a window above the wallpaper and desktop icons and below every normal application window. The numeric level is not documented as stable, so it is computed at runtime, never hard-coded. **[Doc]** for the API, **[Unverified]** for visual stacking on every macOS release. |
| Clicks at that level | Windows above the icon layer receive mouse events normally. Windows at or below `desktopWindow` level sit under Finder's desktop window and do not, which is why WidgetForge does not use that level. **[Unverified]** |
| Covering icons | A widget covers the icons beneath it. Mitigations: widgets are freely movable, any widget can be made click-through, and "Hide Widgets" removes them all. There is no public API to learn where icons are. **[Doc]** |
| Spaces | `collectionBehavior = [.canJoinAllSpaces, .stationary]` shows a window on every Space and keeps it still during Mission Control. **[Doc]** There is **no public API to identify or enumerate Spaces**, so per-Space placement cannot be implemented reliably and is not offered. |
| Full screen | `.fullScreenNone` keeps desktop widgets out of full-screen Spaces; pinned widgets use `.fullScreenAuxiliary`. **[Doc]** |
| Show Desktop / Stage Manager | On macOS 14, clicking the wallpaper can reveal the desktop and move windows aside. How overlay panels at icon level behave under that gesture and under Stage Manager is **[Unverified]** and listed in `LIMITATIONS.md`. |
| Click-through | `ignoresMouseEvents = true` passes all events to whatever is underneath. It is all-or-nothing per window. **[Doc]** |
| Multiple displays | `NSScreen.screens`, `visibleFrame`, `backingScaleFactor`; `didChangeScreenParametersNotification` on any change. `CGDisplayCreateUUIDFromDisplayID` gives an id that survives reconnection, unlike `CGDirectDisplayID`. **[Doc]** |
| Sleep/wake | `NSWorkspace` posts `willSleep`, `didWake`, `screensDidSleep`, `screensDidWake`. **[Doc]** |
| Active app | `NSWorkspace.didActivateApplicationNotification` and `frontmostApplication`; no permission required. **[Doc]** |
| Wallpaper changes | Widgets use translucent system materials (`.regularMaterial`), which resample whatever is behind them, so no wallpaper tracking is needed. **[Doc]** |

## 3. Scripting

| Question | Finding |
| --- | --- |
| JavaScriptCore capability | A `JSContext` exposes only the ECMAScript standard library. Network, files, timers and DOM exist only if the host adds them. **[Doc]** |
| Isolation | JavaScriptCore runs in-process. It is an interpreter boundary, not a security boundary: an engine bug is a host compromise. **[Doc]** |
| Interrupting scripts | The public API has no way to stop a running script. `JSContextGroupSetExecutionTimeLimit` exists in `JSContextRefPrivate.h` (SPI) and is exported by the framework. **[CI]** confirms it is present and terminates `while(true){}` on the tested macOS build. Because it is SPI it may be rejected by App Store review and could disappear. |
| JIT | With the hardened runtime and without `com.apple.security.cs.allow-jit`, JavaScriptCore runs its interpreter tiers only. Acceptable for widget scripts. **[Doc]** |
| Stronger isolation | An XPC service with its own sandbox profile gives process-level isolation and a kill switch. Designed in `SECURITY.md`, not implemented. |
| WKWebView | Web content runs in WebKit's separate, sandboxed processes. Navigation can be confined with `WKNavigationDelegate`; a non-persistent data store avoids shared cookies. **[Doc]** |

**Conclusion.** Scripts are supported in the overlay only, only for widgets the user explicitly trusts, with
a time limit, and the product does not claim OS-level isolation it does not have.

## 4. Sandbox, entitlements and distribution

| Need | Finding |
| --- | --- |
| Outbound network | `com.apple.security.network.client`. **[Doc]** |
| User files | `files.user-selected.read-write` plus security-scoped bookmarks to keep access across launches. **[Doc]** |
| System metrics | `host_processor_info`, `host_statistics64`, `getifaddrs`, `IOPSCopyPowerSourcesInfo`, `ProcessInfo`, volume resource values and IOKit registry reads need no entitlement. **[CI]** confirms they return values inside the sandbox on the runner (which has no battery). |
| Global shortcut | Carbon `RegisterEventHotKey` works without Accessibility permission. **[Doc]**; registration success is reported by **[CI]**. |
| Launch at login | `SMAppService.mainApp` (macOS 13+). **[Doc]** |
| Shortcuts | Opening `shortcuts://run-shortcut?name=…`. **[Doc]** |
| Media control | No public API for system-wide now-playing control. Apple Events to Music are possible in the sandbox with a `scripting-targets` entitlement and user consent. **[Doc]** |
| Calendar | EventKit with `personal-information.calendars` and `NSCalendarsFullAccessUsageDescription` (macOS 14 API). **[Doc]** |
| Notifications | `UNUserNotificationCenter`, user-authorised. **[Doc]** |
| Clipboard | `NSPasteboard` needs no entitlement; newer macOS releases may alert the user about programmatic reads. WidgetForge reads only on an explicit click. **[Doc]** |
| Signing | Ad-hoc signing is enough to run locally. Distribution outside the App Store needs Developer ID signing, the hardened runtime and notarisation. **[Doc]** CI produces ad-hoc builds only. |

## 5. Resulting design

Two backends, one definition format, one renderer:

- **Native WidgetKit backend**: timeline-driven, App Intent interactions, system sizes, sampled metrics
  labelled with the time they were taken, no scripts, no web content.
- **Live Desktop Overlay backend**: WidgetForge's own windows, real-time data, full interaction,
  optional trusted scripts, free placement and sizing, profiles and automation.

They are presented to the user as different things, because they are.
