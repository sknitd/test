# MagicForge — input feasibility

Scope: which macOS interfaces can deliver Magic Mouse input to a third-party app, what each one
really provides, and what MagicForge builds on. Written by the input agent on Linux.

**Read the "Verification status" section first: nothing in this document has been executed on a Mac
or with a Magic Mouse.** Statements are tagged with a confidence level:
`[doc]` documented public API behaviour, `[community]` consistent across reverse-engineered
open-source projects, `[inferred]` reasoning without a source, `[unverified]` open question.

## Summary

- Raw finger contacts on a Magic Mouse are **not available through any public API**. The only known
  route is Apple's private `MultitouchSupport.framework` `[community]`.
- Public APIs deliver only what the system already derived from the touches: pointer motion, button
  clicks, continuous scroll events with phases and momentum, device presence and battery.
- MagicForge therefore has two tiers: a private-API adapter (`MultitouchSupportAdapter`, optional,
  loaded with `dlopen`/`dlsym`, can be missing) and a public-API fallback (`EventTapPointerSource`:
  modifier chords, hot keys, scroll rewriting).
- Consequences: no App Sandbox, no Mac App Store; Developer ID signing + notarization is the
  distribution path.

## Public APIs

### NSEvent global / local monitors
`NSEvent.addGlobalMonitorForEvents` observes copies of events sent to other apps; it cannot modify
or swallow them, and key events need Accessibility trust `[doc]`. Local monitors only see the app's
own events. A Magic Mouse appears as mouse-moved, button and `scrollWheel` events (with
`hasPreciseScrollingDeltas`, `phase`, `momentumPhase`). Monitors with gesture masks (`.gesture`,
`.swipe`, `.magnify`, …) exist, but per-finger data is not part of global events. Not sufficient:
cannot rewrite scroll deltas, cannot swallow chords.

### CGEventTap (Quartz Event Services)
What a Magic Mouse produces at a session tap `[doc]` for the fields, `[community]` for the device:
- left / right mouse down, up, dragged (the mouse has one physical switch; left vs right is decided
  by the driver from finger position), mouse moved;
- `scrollWheel` events flagged continuous (`scrollWheelEventIsContinuous = 1`) with pixel deltas
  (`…PointDeltaAxis1/2`), fixed-point line deltas, integer line deltas, a scroll phase and, after
  the finger lifts, momentum-phase events.
- Gesture events: the system-level Magic Mouse gestures (two-finger swipe between pages / spaces,
  smart-zoom double tap) are turned into private gesture event types (29/30-range `NSEventTypeGesture`
  family) and into actions by the Dock / WindowServer. A tap can see some of these opaque events, but
  their payload is undocumented and **they do not contain finger positions**. `[community]`
  We do not build on them. Whether they reach a tap for every gesture on current macOS is `[unverified]`.
- An event does **not** identify its source device. A continuous scroll event from a Magic Mouse is
  indistinguishable from a trackpad's by documented fields. MagicForge's "is from Magic Mouse" is a
  heuristic: continuous event whose gesture began while the multitouch adapter saw a finger on a
  Magic Mouse (`MagicMouseActivity`); momentum events inherit the verdict. Without the adapter the
  app can only assume (off by default).

Active taps (`.defaultTap`) can modify events in place and drop them; that is how Smart Scroll
rewrites deltas on the same event (line delta first, then fixed-point, then point delta — the order
used by long-standing scroll utilities such as Scroll Reverser `[community]`) and how chords and hot
keys are swallowed. The system disables a tap that is too slow (`tapDisabledByTimeout`); the tap
re-enables itself.

### NSTouch / NSEvent.touches
`NSEvent.touches(matching:in:)` / `NSResponder.touchesBegan` deliver normalized touches **for
trackpads only, to a view of the app that has focus** `[doc]`. Not global, and Magic Mouse touches
are not delivered through it `[community]`. Not usable.

### IOKit HID (IOHIDManager)
- Enumeration, matching/removal notifications and property reads (name, vendor, product, transport,
  serial) work without opening the device `[community: hidapi enumerates this way]`.
- Matching: vendor `0x05AC` (USB, and Magic Mouse 1 over Bluetooth) and `0x004C` (Apple's Bluetooth
  company id); product `0x030D` Magic Mouse 1, `0x0269` Magic Mouse 2, `0x0323` Magic Mouse USB-C
  (2024). Source: Linux `drivers/hid/hid-ids.h` (`USB_DEVICE_ID_APPLE_MAGICMOUSE`,
  `…MAGICMOUSE2`, `…MAGICMOUSE2_USBC`, `BT_VENDOR_ID_APPLE`), fetched while writing this.
- What the HID descriptor exposes to user space: a standard mouse collection (X/Y, buttons), battery
  information, and vendor-defined reports that carry the multitouch data (the Linux driver parses
  report ids 0x29 for the mouse, 0x12 for Magic Mouse 2) `[community]`. On macOS the Apple
  multitouch driver consumes those reports; whether a second user-space client receives the raw
  vendor reports through `IOHIDDeviceRegisterInputReportCallback` without seizing is `[unverified]`
  and reported as unreliable. Seizing (`kIOHIDOptionsTypeSeizeDevice`) would take the mouse away
  from the system (no pointer) and is never done.
- Permission: opening HID devices to receive other apps' input (keyboards in particular) requires
  **Input Monitoring** since macOS 10.15 `[doc]`. `HIDDeviceMonitor` never opens anything and never
  registers value/report callbacks, so it should need no permission `[inferred]`.
- Battery: Apple's drivers publish `BatteryPercent` in the IORegistry near the HID device
  `[community]`; undocumented, read best-effort.

### Bluetooth identification
`IOBluetooth` can list paired devices and addresses, but touching it triggers the Bluetooth privacy
prompt (`NSBluetoothAlwaysUsageDescription`). The HID properties (`Transport`, `SerialNumber`,
`DeviceAddress`) already identify the mouse, so MagicForge does not use IOBluetooth.

## Private API: MultitouchSupport.framework

PRIVATE AND UNSUPPORTED. No header, no documentation, no stability promise. It is what
MiddleClick (open source), OpenMultitouchSupport, Hammerspoon's touchdevice module and, by all
appearances, commercial tools such as BetterTouchTool and MultiTouch use for raw contacts
`[community]`.

Functions used (signatures as reverse engineered, e.g. OpenMultitouchSupport `OpenMTInternal.h`):

| Symbol | Signature (C) | Use |
|---|---|---|
| `MTDeviceCreateList` | `CFMutableArrayRef (void)` | enumerate devices (required) |
| `MTRegisterContactFrameCallback` | `void (MTDeviceRef, callback)` | required |
| `MTUnregisterContactFrameCallback` | `void (MTDeviceRef, callback)` | required |
| `MTDeviceStart` | `OSStatus/void (MTDeviceRef, int)` | required; return value not trusted |
| `MTDeviceStop` | `OSStatus/void (MTDeviceRef)` | required |
| `MTDeviceIsBuiltIn` | `bool (MTDeviceRef)` | classification |
| `MTDeviceGetFamilyID` | `OSStatus (MTDeviceRef, int *)` | classification |
| `MTDeviceGetSensorSurfaceDimensions` | `OSStatus (MTDeviceRef, int *, int *)` (1/100 mm) | classification |
| `MTDeviceGetDeviceID` | `OSStatus (MTDeviceRef, uint64_t *)` | reconnect handling |
| `MTDeviceIsRunning` | `bool (MTDeviceRef)` | diagnostics |
| `MTDeviceCreateDefault`, `MTDeviceRelease` | — | resolved and reported only |

Callback: `int (*)(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame)`.

Touch struct ("Finger" / `MTTouch`), 96 bytes on 64-bit, alignment 8 `[community]`:
`frame` int32 @0, (pad), `timestamp` double @8, `identifier` @16, `state` @20, `fingerID` @24,
`handID` @28, normalized position+velocity (4 floats) @32, `size`/total capacitance float @48,
unknown @52, `angle` @56, `majorAxis` @60, `minorAxis` @64, absolute position+velocity (mm) @68,
two unknown int32 @84/@88, density float @92. MagicForge mirrors it in Swift, checks stride,
alignment and every field offset at runtime, and refuses to start on a mismatch.

Touch states: 0 not tracking, 1 start in range, 2 hover, 3 make touch, 4 touching, 5 break touch,
6 linger, 7 out of range. Only 3 and 4 count as "on the surface".

Family ids `[community, from memory — not re-confirmed online]`: 112 / 113 Magic Mouse / Magic
Mouse 2, 128–130 Magic Trackpads, ~98–105 built-in trackpads. The USB-C Magic Mouse id is unknown,
so classification also uses "not built in + narrow portrait sensor surface".

Open points `[unverified]`: orientation of normalized y on the Magic Mouse (assumed 0 = rear,
1 = front; `invertY` exists), the timestamp timebase (assumed uptime seconds; falls back to arrival
time when implausible), maximum simultaneous contacts (declared 5), the size scale, whether the
device array returned by `MTDeviceCreateList` retains its elements (assumed; the failure mode of
the assumption being wrong is a small leak, not a crash), and behaviour after sleep (streams are
restarted on wake as other tools do).

Permissions in practice: reading contact frames has historically needed **no TCC permission**, only
a non-sandboxed process `[community]`; MiddleClick asks for Accessibility only because it posts
clicks. Whether recent macOS versions gate it behind Input Monitoring is `[unverified]`.

## Permissions

| Capability | API | Permission |
|---|---|---|
| Active event tap (modify / swallow), posting CGEvents | `CGEvent.tapCreate(.defaultTap)`, `CGEvent.post` | Accessibility |
| Listen-only tap, reading other apps' HID input | `.listenOnly` tap, `IOHIDDeviceOpen` + callbacks | Input Monitoring |
| Window management | AXUIElement | Accessibility |
| Device presence / properties | IOHIDManager without open | none `[inferred]` |
| Raw contacts | MultitouchSupport (private) | none known `[community]` |
| AppleScript to other apps | Apple Events | Automation (per target app) |

`AXIsProcessTrusted()`, `CGPreflightListenEventAccess()` and `CGPreflightPostEventAccess()` check
without prompting; MagicForge never prompts implicitly.

## Sandbox, signing, notarization, App Store

- **App Sandbox**: incompatible. A sandboxed app cannot create an active session event tap, cannot
  use the Accessibility API on other apps, and is denied the IOKit user clients the multitouch
  driver needs `[doc]`/`[community]`. MagicForge must ship non-sandboxed.
- **Hardened runtime + Developer ID + notarization**: compatible. Notarization scans for malware
  and signing problems; it does not reject private API use `[community: every tool in this category
  ships notarized]`. `dlopen` of a system framework needs no special entitlement.
- **Mac App Store**: not possible — sandbox is mandatory there and App Review rejects private API.
- TCC grants are tied to the code signature; ad-hoc or changing signatures lose Accessibility
  trust after each rebuild.

## Capability matrix

| Feature | Public API | Private API | Supported | Limitations |
|---|---|---|---|---|
| Device detection (connect / disconnect, model) | IOHIDManager matching | — | Yes | Unknown future product ids recognised by name only |
| Battery level | IORegistry `BatteryPercent` (undocumented property, public call) | — | Best effort | May be absent; polled every 120 s |
| Raw contacts (positions, ids) | None | MultitouchSupport contact frames | Yes, private only | Can break in any macOS update; unavailable → fallback tier |
| Contact size / ellipse | None | MTTouch size, axes, angle | Yes, private only | Scale uncalibrated |
| One-finger tap / double tap / hold | None | Raw contacts | Private only | Must be separated from resting fingers and clicks |
| One-finger swipes | Only as scroll events | Raw contacts | Private only | Overlaps native scrolling; off by default |
| Edge swipes, corner / centre taps (zones) | None | Raw contacts | Private only | Depends on unverified y orientation |
| Two-finger tap / hold / swipes | None (system consumes two-finger swipes) | Raw contacts | Private only | System gesture may fire as well unless disabled in System Settings |
| Pinch / rotate | None for Magic Mouse | Raw contacts | Private only | Small surface; reliability unverified |
| Three-finger tap / hold / swipes | None | Raw contacts | Private only | Needs ≥ 3 tracked contacts (unverified on hardware) |
| Compound (tap-then-swipe, hold-then-swipe) | None | Raw contacts | Private only | — |
| Fallback chords (⌃⌥ + click / scroll) | Active CGEventTap | — | Yes | Needs Accessibility; applies to any pointing device |
| Global hot keys | Active CGEventTap | — | Yes | Needs Accessibility; blocked during secure input |
| Scroll modification (speed, invert, acceleration) | Active CGEventTap, in-place rewrite | Origin heuristic uses private adapter | Yes | "Magic Mouse only" is a heuristic; without adapter origin is unknown |
| Click synthesis | `CGEvent` posting | — | Yes | Needs Accessibility; synthetic events are tagged and ignored by the tap |
| Keyboard shortcut synthesis | `CGEvent` posting | — | Yes | Needs Accessibility |
| Window management | Accessibility (AXUIElement) | — | Yes | Needs Accessibility; some apps expose no AX windows |
| Mission Control / Launchpad etc. | Synthesised shortcuts / opening system apps | CoreDock symbols (not used) | Partly | Depends on the user's shortcut settings |
| Suppressing native Magic Mouse gestures | None | None used | No | User must change System Settings |

## Verification status

**Verified by execution (on Linux, Swift 6.0.3, x86_64 — not on macOS):**
- `MTTouch` Swift mirror: stride 96, alignment 8 and all documented field offsets (the layout rules
  for these field types are the same on macOS arm64 / x86_64).
- Pure logic, run with a throw-away harness: contact phase tracking (began / moved / ended, lift
  frame), timestamp fallback, device classification rules, scroll delta rewrite arithmetic, HID
  interface grouping, argument parsing, `dlsym` → `@convention(c)` cast pattern (against libc), and
  the "framework missing → unavailable with reason" path.
- Type-checking of all MFInput / MFDevices / mfprobe sources against **hand-written stubs** of the
  Apple APIs. This catches Swift mistakes but proves nothing about the real SDK signatures.
- Product ids against the Linux kernel's `hid-ids.h`.

**Not verified (everything else), in particular:**
- Compilation against the macOS SDK (first happens on CI: macos-15 / Xcode 16.x, macos-26 / Xcode 26.x).
- That MultitouchSupport loads, that the symbols resolve and have the assumed signatures on macOS 14, 15, 26.
- That a Magic Mouse delivers contact frames, at what rate, with how many contacts; y orientation;
  family ids; sensor dimensions; timestamp timebase; behaviour across sleep, reconnect and stop.
- That no TCC permission is required for contact frames or for unopened IOHIDManager enumeration.
- Event tap behaviour: in-place scroll rewrite effect in real apps, chord swallowing, hot keys,
  horizontal sign convention, origin heuristic quality.
- Battery property lookup.
- No Mac and no Magic Mouse were available; **nothing has been verified on hardware.**

`mfprobe --self-check` is designed to answer the software questions on CI (no hardware);
`mfprobe --frames` / `--gestures` answer the hardware questions and need a person with a mouse.

<!-- CI probe results are appended below by the lead. -->

### CI probe results

Source: GitHub Actions run 45174444697 (commit 1a01839), step "mfprobe --self-check"
(`swift run mfprobe --self-check`), hosted runners, **no Magic Mouse attached**. See docs/CI_LOG.md.

What these runs establish (software questions only):
- MFDevices, MFInput and mfprobe compile against the real macOS SDK with Xcode 16.0 (Swift 6.0),
  Xcode 16.4 (Swift 6.1.2) and Xcode 26.6 (Swift 6.3.3), without errors.
- On macOS 15.8.2 and macOS 26.7.2 (arm64) `MultitouchSupport.framework` loads with `dlopen` and
  all 5 required and all 7 optional symbols resolve with `dlsym`.
- `MTDeviceCreateList` can be called on a machine with no multitouch device and returns 0 devices
  without crashing; the adapter reports "unavailable: No Magic Mouse multitouch device is connected".
- The Swift touch struct has stride 96 on macOS arm64 (matches the expected 96).
- Unopened IOHIDManager enumeration runs and returns 0 Magic Mouse devices.
- Listen-only and active CGEvent taps can be created when permissions are granted.

What they do NOT establish:
- Anything about real contact frames (run-time callback signature, rate, orientation, family ids,
  sensor dimensions): no device was present, so no callback ever fired.
- Behaviour on macOS 14 (no runner exists) or on Intel hardware (all runners are arm64).
- Behaviour without TCC permissions: the hosted runners report Accessibility trusted, listen-event
  and post-event access all `true` for the runner shell, so the "permission missing" paths were
  not exercised by these runs.

Verbatim JSON, job "macOS (macos-15)" (Xcode 16.4). The job "macOS (macos-15-xcode16.0)" (Xcode 16.0,
same OS image) printed byte-identical JSON.

```json
{
  "eventTap" : {
    "activeCreated" : true,
    "attempted" : true,
    "listenOnlyCreated" : true
  },
  "hid" : {
    "devices" : [

    ],
    "magicMouseCount" : 0
  },
  "mode" : "self-check",
  "multitouchSupport" : {
    "adapterAvailability" : "unavailable: No Magic Mouse multitouch device is connected",
    "deviceCount" : 0,
    "devices" : [

    ],
    "expectedTouchStride" : 96,
    "frameworkPath" : "\/System\/Library\/PrivateFrameworks\/MultitouchSupport.framework\/MultitouchSupport",
    "layoutProblem" : "",
    "loaded" : true,
    "loadError" : "",
    "symbols" : [
      {
        "name" : "MTDeviceCreateList",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTRegisterContactFrameCallback",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTUnregisterContactFrameCallback",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceStart",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceStop",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceCreateDefault",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceRelease",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceIsRunning",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceIsBuiltIn",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetFamilyID",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetDeviceID",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetSensorSurfaceDimensions",
        "required" : false,
        "resolved" : true
      }
    ],
    "touchStride" : 96,
    "unavailableReason" : ""
  },
  "os" : {
    "architecture" : "arm64",
    "major" : 15,
    "minor" : 8,
    "patch" : 2,
    "versionString" : "Version 15.8.2 (Build 24H232)"
  },
  "permissions" : {
    "accessibilityTrusted" : true,
    "listenEventAccess" : true,
    "postEventAccess" : true
  },
  "tool" : "mfprobe"
}
```

Verbatim JSON, job "macOS (macos-26)" (Xcode 26.6):

```json
{
  "eventTap" : {
    "activeCreated" : true,
    "attempted" : true,
    "listenOnlyCreated" : true
  },
  "hid" : {
    "devices" : [

    ],
    "magicMouseCount" : 0
  },
  "mode" : "self-check",
  "multitouchSupport" : {
    "adapterAvailability" : "unavailable: No Magic Mouse multitouch device is connected",
    "deviceCount" : 0,
    "devices" : [

    ],
    "expectedTouchStride" : 96,
    "frameworkPath" : "\/System\/Library\/PrivateFrameworks\/MultitouchSupport.framework\/MultitouchSupport",
    "layoutProblem" : "",
    "loaded" : true,
    "loadError" : "",
    "symbols" : [
      {
        "name" : "MTDeviceCreateList",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTRegisterContactFrameCallback",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTUnregisterContactFrameCallback",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceStart",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceStop",
        "required" : true,
        "resolved" : true
      },
      {
        "name" : "MTDeviceCreateDefault",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceRelease",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceIsRunning",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceIsBuiltIn",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetFamilyID",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetDeviceID",
        "required" : false,
        "resolved" : true
      },
      {
        "name" : "MTDeviceGetSensorSurfaceDimensions",
        "required" : false,
        "resolved" : true
      }
    ],
    "touchStride" : 96,
    "unavailableReason" : ""
  },
  "os" : {
    "architecture" : "arm64",
    "major" : 26,
    "minor" : 7,
    "patch" : 2,
    "versionString" : "Version 26.7.2 (Build 25G332)"
  },
  "permissions" : {
    "accessibilityTrusted" : true,
    "listenEventAccess" : true,
    "postEventAccess" : true
  },
  "tool" : "mfprobe"
}
```

## Sources
- Linux kernel `drivers/hid/hid-ids.h`, `hid-magicmouse.c` (product ids, report ids): https://github.com/torvalds/linux/blob/master/drivers/hid/hid-ids.h
- OpenMultitouchSupport `OpenMTInternal.h` (MTTouch layout, states, MTDevice functions): https://github.com/Kyome22/OpenMultitouchSupport
- MiddleClick (Magic Mouse + trackpad via MultitouchSupport, macOS 15 support): https://github.com/artginzburg/MiddleClick
- Apple documentation: Quartz Event Services, `NSEvent`, `NSTouch`, IOHIDManager, TN on Input Monitoring / `IOHIDCheckAccess`.
