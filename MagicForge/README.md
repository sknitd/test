# MagicForge

MagicForge is a native macOS menu-bar utility that turns the touch surface of an Apple Magic
Mouse into configurable gestures: swipes, taps, zones, multi-finger and compound gestures that
trigger shortcuts, window management, app control, scripts, workflows, a radial menu and
(opt-in) AI text actions, with per-app profiles.

It is written in Swift (SwiftUI + AppKit), has no third-party dependencies, and targets
macOS 14 or later on Apple silicon and Intel.

> **Status.** This README describes what the project is designed to do. It does not claim that
> any feature has been verified on real hardware. The authoritative record of what has been
> built, tested and verified (and what has not) is [docs/PROGRESS.md](docs/PROGRESS.md).
> Read [docs/LIMITATIONS.md](docs/LIMITATIONS.md) before relying on it.

## What to expect

| Area | Design | Depends on | Details |
|---|---|---|---|
| Raw-touch gestures (one, two, three fingers, zones, compound) | Recognised from per-finger contact frames | Apple's **private** `MultitouchSupport.framework`, loaded at runtime; can be unavailable | [GESTURES](docs/GESTURES.md), [FEASIBILITY](docs/FEASIBILITY.md) |
| Fallback triggers (button chords, hot keys) | Recognised from ordinary pointer and key events | Public `CGEventTap` + Accessibility permission | [GESTURES](docs/GESTURES.md) |
| Smart scrolling | Rewrites scroll deltas in the event tap | Accessibility permission | [GESTURES](docs/GESTURES.md) |
| Actions (keys, windows, apps, media, text) | Synthetic events and the Accessibility API | Accessibility permission | [PERMISSIONS](docs/PERMISSIONS.md) |
| Scripts, shell commands, Shortcuts | Run only after you approve the exact script (hash-based trust) | Automation permission for AppleScript | [AUTOMATION](docs/AUTOMATION.md) |
| Workflows and radial menu | Multi-step actions, on-screen menu | Same as the actions they contain | [AUTOMATION](docs/AUTOMATION.md) |
| Per-app profiles, import and export | JSON configuration in Application Support | Nothing extra | [PROFILES](docs/PROFILES.md) |
| AI text actions | Off by default; OpenAI-compatible endpoint you configure | Network + your API key (Keychain) | [AUTOMATION](docs/AUTOMATION.md) |
| Hardware | Magic Mouse (1st generation), Magic Mouse 2, Magic Mouse (USB-C) | Which models and macOS versions are actually verified | [COMPATIBILITY](docs/COMPATIBILITY.md), [PROGRESS](docs/PROGRESS.md) |

When raw touch input is unavailable (framework missing, symbols changed, no supported device),
the app says so and offers only the fallback triggers. It never fabricates finger positions;
synthetic test input in the Touch Lab is always labelled as synthetic.

MagicForge is not sandboxed and cannot be distributed through the Mac App Store. See
[docs/LIMITATIONS.md](docs/LIMITATIONS.md) for why.

## Install from the DMG

1. Open `MagicForge-<version>.dmg` and drag **MagicForge** onto **Applications**.
2. Launch it. Builds produced by this repository's scripts and CI are **ad-hoc signed and not
   notarized**, so Gatekeeper blocks the first launch:
   - macOS 14: right-click (Control-click) the app → **Open** → **Open**.
   - macOS 15 and later: try to open it once, then go to **System Settings → Privacy &
     Security**, scroll to the message about MagicForge and click **Open Anyway**.
   - Or remove the quarantine flag yourself:
     `xattr -dr com.apple.quarantine /Applications/MagicForge.app`
3. Grant permissions when asked (next section).

Only do this for a build you trust: one you built yourself or downloaded from this project's
CI. A notarized Developer ID build (see [docs/RELEASE.md](docs/RELEASE.md)) opens without any
of these steps.

## Permissions quick start

| Permission | Why | Where |
|---|---|---|
| Accessibility | Event tap for fallback triggers and scrolling, posting key and mouse events, moving windows | System Settings → Privacy & Security → Accessibility |
| Automation | Only if you use AppleScript or app-control actions; asked per target app | System Settings → Privacy & Security → Automation |
| Input Monitoring | Only if the Permissions screen says it is needed on your system | System Settings → Privacy & Security → Input Monitoring |

The app's **Permissions** screen shows the current state of each permission, explains what it
is used for with your current configuration, and links to the right settings pane. Full
details: [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

Ad-hoc signed builds get a new code identity on every build, so macOS forgets previously
granted permissions after you rebuild or update; see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#permissions-are-granted-but-the-app-says-they-are-missing).

## Build from source

Requirements: macOS 14 or later with Xcode 16.0 or later (the oldest toolchain the CI builds
with). Details and options: [docs/BUILD.md](docs/BUILD.md).

Without the Xcode project (SwiftPM + a packaging script):

```sh
Scripts/build_app.sh             # → dist/MagicForge.app (native arch, ad-hoc signed)
UNIVERSAL=1 Scripts/build_app.sh # arm64 + x86_64
Scripts/make_dmg.sh              # → dist/MagicForge-<version>.dmg
```

With Xcode:

```sh
open MagicForge.xcodeproj        # scheme "MagicForge", then Run
Scripts/build_xcode.sh           # or from the command line → dist/MagicForge.app (universal)
```

Tests and diagnostics:

```sh
Scripts/test.sh                  # swift test
Scripts/run_probe.sh --self-check   # hardware / input diagnostics (mfprobe)
Scripts/measure_idle.sh          # measured idle CPU and memory of the built app
```

The portable modules also build and test on Linux (`swift test`); see
[docs/TESTING.md](docs/TESTING.md).

## Privacy

- MagicForge has no telemetry, analytics, crash reporting or update checks. It makes no
  network connections unless you enable AI and trigger an AI action yourself.
- Touch data is processed in memory and is not stored. Logs never contain touch coordinates,
  clipboard contents, typed text or script bodies. A diagnostics export contains touch frames
  only if you explicitly include them.
- Configuration is stored locally as JSON in `~/Library/Application Support/MagicForge/`.
  Exports and backups do not contain secrets.
- The AI API key is stored in the macOS Keychain. AI is off by default; when you use it, the
  text you chose (selection or clipboard) is sent to the endpoint you configured, and nothing
  else.
- Scripts, shell commands and Shortcuts run only if you approved that exact content. Imported
  profiles never bring approval with them.

## Project layout

```
Package.swift            Swift package: all modules, tests, mfprobe, the SwiftPM app executable
MagicForge.xcodeproj     Generated Xcode project: one app target that links the package (MFApp)
Sources/
  Utilities/ Core/       Logging, clock, shared model types and service protocols
  Gestures/ Profiles/ Automation/ Integrations/ Engine/    portable logic (macOS + Linux)
  Devices/ Input/ Actions/ UI/ App/                        macOS-only modules
  AppMain/               main.swift, the entry point shared by SwiftPM and Xcode
  Probe/                 mfprobe command-line diagnostics
Tests/                   Unit tests for the portable modules
Resources/               Info.plist, entitlements, Version.xcconfig, asset catalog, AppIcon.icns,
                         SampleProfiles/
Scripts/                 Build, packaging, notarization, test, probe and measurement scripts;
                         project and icon generators
docs/                    Documentation (index below)
```

## Documentation

| Document | Contents |
|---|---|
| [docs/PROGRESS.md](docs/PROGRESS.md) | What is implemented, tested and verified, and what is not |
| [docs/FEASIBILITY.md](docs/FEASIBILITY.md) | What macOS allows for Magic Mouse touch input and how that was established |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | Hardware and macOS version matrix |
| [docs/LIMITATIONS.md](docs/LIMITATIONS.md) | Known limits and risks |
| [docs/PERMISSIONS.md](docs/PERMISSIONS.md) | Each permission, why it is needed, how to grant and reset it |
| [docs/GESTURES.md](docs/GESTURES.md) | Gesture catalogue and tuning |
| [docs/PROFILES.md](docs/PROFILES.md) | Profiles, per-app switching, import and export |
| [docs/AUTOMATION.md](docs/AUTOMATION.md) | Actions, workflows, scripts and trust, AI |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data flow, threading, trust model |
| [docs/BUILD.md](docs/BUILD.md) | Building with SwiftPM and Xcode, signing options, CI |
| [docs/TESTING.md](docs/TESTING.md) | Unit tests, synthetic touch input, probe, hardware checklist |
| [docs/RELEASE.md](docs/RELEASE.md) | Versioning, Developer ID signing, notarization, DMG |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptoms and fixes |

## Trademarks

Magic Mouse, macOS and Mac are trademarks of Apple Inc. MagicForge is an independent project
and is not affiliated with or endorsed by Apple.
