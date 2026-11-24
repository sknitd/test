# WidgetForge

**The Programmable Desktop.** A native macOS app for creating, scripting, automating, arranging and
sharing desktop widgets, from a simple clock to live system dashboards and API-powered panels.

- macOS 14 Sonoma or newer, Apple silicon and Intel
- Swift, SwiftUI, AppKit, WidgetKit, App Intents, Swift Charts, JavaScriptCore, SQLite
- No Electron, no account, no cloud. Everything except widgets you point at an online API works offline.

> **Status.** Read [`docs/PROGRESS.md`](docs/PROGRESS.md) first. It records, per feature, what is
> implemented, compiled, unit-tested and verified on real hardware, and it does not round up.

## Two rendering backends

| | Live Desktop Overlay | Native WidgetKit |
| --- | --- | --- |
| What it is | WidgetForge's own borderless windows at desktop level | A real macOS widget from the system gallery |
| Updates | Real time (metrics every 1–10 s, clocks every second) | Timeline entries; the system budgets reloads |
| Interaction | Full: text entry, sliders, drag, resize, tooltips | App Intent buttons and toggles only |
| JavaScript widgets | Yes, when you trust the script | No (shows the last layout the app rendered) |
| Placement | Anywhere, any size, per display, per profile | System sizes, placed by macOS |

Overlay windows are not WidgetKit widgets and are never described as such. See
[`docs/FEASIBILITY.md`](docs/FEASIBILITY.md).

## Features

- **Desktop widgets**: create, duplicate, delete with restore, move, resize, lock, pin above windows,
  hide, per-widget opacity and appearance, group, align, snap to grid, saved layouts, multi-display aware.
- **Three interaction modes**: Edit (drag and resize), Normal (widgets act), Click-through (pointer
  passes to the desktop).
- **Visual builder**: component palette, canvas with multi-selection, alignment guides, snapping, layers,
  grouping, undo/redo, copy/paste, responsive pinning, inspector, data binding, script editor, console and
  a live preview running real data.
- **25 templates**: clocks, calendar, pomodoro, CPU / RAM / network / battery / disk monitors, weather,
  stocks, crypto, GitHub activity, API status, server health, notes, to-do, clipboard, countdown, REST
  and JavaScript starters, media controls, shortcut launcher, habit tracker, multi-metric dashboard.
- **Real system metrics** from Mach, BSD and IOKit interfaces. No simulated numbers anywhere.
- **Data engine**: REST, WebSocket, local HTTP, JSON and CSV files, calendar, system metrics; caching,
  retry with backoff, rate limiting, offline fallback, validation.
- **Automation**: timer, app launch/activation, network change, battery threshold, widget interaction and
  data-condition triggers; show/hide, profile, refresh, notify, open URL, launch app, run Shortcut and
  set-state actions; cooldowns, edge triggering and loop protection.
- **Profiles**: Work / Development / Personal / Focus style desktops, switched by hand, time, frontmost
  app or connected display, with automatic restoration.
- **Command Center** (⌃⌥Space): fuzzy search over widgets, templates, profiles, automations and commands.
- **Security**: declarative by default, per-widget permission manifests, host allowlists, Keychain
  secrets bound to hosts, validated imports, scripts disabled until trusted. See
  [`docs/SECURITY.md`](docs/SECURITY.md).
- **Optional AI builder** for any OpenAI-compatible endpoint; off by default; output is declarative,
  validated, previewed and approved before it is saved.

## Getting started

```bash
cd WidgetForge
open WidgetForge.xcodeproj        # then Run, or:
Scripts/build_app.sh && Scripts/make_dmg.sh
swift test                        # core unit tests
```

Full instructions: [`docs/BUILD.md`](docs/BUILD.md). Writing widgets: [`docs/SDK.md`](docs/SDK.md).

## Documentation

| | |
| --- | --- |
| [PROGRESS](docs/PROGRESS.md) | What is done, tested and verified; measured numbers; next steps |
| [FEASIBILITY](docs/FEASIBILITY.md) | Platform investigation behind the two-backend design |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Modules, data flow, concurrency, persistence |
| [SECURITY](docs/SECURITY.md) | Threat model, permission enforcement, limits of the script runtime |
| [COMPATIBILITY](docs/COMPATIBILITY.md) | macOS versions, hardware, signing configurations |
| [LIMITATIONS](docs/LIMITATIONS.md) | Known gaps and unsupported features |
| [BUILD](docs/BUILD.md) · [TESTING](docs/TESTING.md) · [SDK](docs/SDK.md) | How to build, test and write widgets |
