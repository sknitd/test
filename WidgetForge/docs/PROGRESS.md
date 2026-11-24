# Progress

Last updated: 2026-11-24.

## How to read this

Development happened on a Linux machine with no Swift toolchain, so every compile and test result below
comes from GitHub Actions (`.github/workflows/widgetforge.yml`) on hosted macOS 15 / Xcode 16.4 runners
and a Swift 5.10 Linux container. Columns:

- **Implemented**: the code exists in this repository.
- **Compiled**: it builds in CI as part of `WidgetForge.app` or the widget extension.
- **Tested**: automated unit tests exercise it (`swift test`), or the app self-test does.
- **Hardware verified**: a person has used it on a real Mac. **Nobody has yet**, so this column is "no"
  everywhere; the nearest substitute is the CI self-test, noted where it applies.

## Measured results

Pending. The first full app build is running in CI; the self-test output (window levels, idle CPU, memory,
update latency, live metric sample) will be recorded here from that run. No numbers are stated until then.

## Feature status

| Feature | Implemented | Compiled | Tested | Hardware verified | Known limitations |
| --- | --- | --- | --- | --- | --- |
| App shell, menu bar item, main window with 10 sections | yes | yes | launch only (self-test) | no | UI never seen by a person |
| Launch at login (`SMAppService`) | yes | yes | no | no | |
| Desktop overlay windows (levels, Spaces behaviour, click-through, opacity, appearance) | yes | yes | self-test reports live windows and levels | no | Show Desktop / Stage Manager behaviour unknown |
| Move / resize / snap / guides in Edit mode | yes | yes | layout maths and store path unit-tested; self-test moves a window through the store | no | Mouse tracking itself untested |
| Lock, pin, hide, restore, duplicate, delete with trash | yes | yes | unit | no | |
| Group, align, distribute, saved layouts | yes | yes | unit | no | |
| Layout persistence across launches (SQLite) | yes | yes | unit (incl. on-disk SQLite) | no | |
| Multi-display placement, disconnect / reconnect | yes | yes | unit | no | Only one display exists in CI |
| Sleep / wake / display sleep suspension | yes | yes | suspend/resume unit-tested in the data engine | no | Notifications themselves untested |
| Clock widget | yes | yes | renders in self-test | no | |
| CPU monitor (real `host_processor_info` data) | yes | yes | unit (real machine) + self-test | no | |
| Notes widget (persists text) | yes | yes | state persistence unit-tested | no | Typing in a non-activating panel untested |
| All 25 templates | yes | yes | validated by unit tests | no | Online ones need setup; see each template |
| System metrics: CPU, memory, storage, network, battery, system | yes | yes | unit (real machine) | no | Battery path only exercised as "no battery" in CI |
| Declarative runtime (components, placeholders, actions) | yes | yes | unit (model layer) | no | SwiftUI rendering untested |
| Swift Charts (line, bar, area, pie/donut, sparkline, thresholds, tooltips, CSV export) | yes | yes | no | no | |
| Data engine (REST, WebSocket, local HTTP, files, CSV, calendar, metrics) | yes | yes | unit (mock transports) | no | Real endpoints never contacted by tests |
| Caching, retry/backoff, rate limiting, offline fallback, validation | yes | yes | unit | no | |
| Permission manifests, allowlists, revocation | yes | yes | unit | no | |
| Keychain secrets bound to hosts | yes | yes | unit (in-memory store) | no | Real Keychain untested |
| Import / export, schema validation, secret scrubbing | yes | yes | unit | no | |
| Visual builder (palette, canvas, inspector, layers, undo/redo, copy/paste, guides, constraints, data binding, script editor, console, live preview) | yes | yes | canvas maths only | no | Largest untested surface |
| JavaScript SDK and runtime | yes | yes | unit on macOS (incl. loop termination) | no | In-process; SPI watchdog; see SECURITY.md |
| WidgetKit extension, App Intents, shared snapshot | yes | yes | snapshot hand-off unit-tested | no | Needs team signing to share data; never seen in the gallery |
| Automation engine (8 triggers, 10 actions) | yes | yes | unit | no | System notifications feeding it untested |
| Profiles (manual, time, app, display, restore) | yes | yes | unit | no | |
| Command Center + global shortcut | yes | yes | fuzzy search unit-tested | no | |
| Diagnostics (log, timings, resource usage) | yes | yes | unit + self-test output | no | |
| Optional AI builder | yes | yes | unit (mock transport) | no | Never called a real model |
| Release `.app` (universal, ad-hoc signed) | yes | yes | built and launched in CI | no | Not notarised |
| DMG | yes | n/a | created and verified by `hdiutil` in CI | no | Not notarised |

## Acceptance criteria

| Criterion | Status |
| --- | --- |
| Native macOS app builds | Pending: core and WidgetKit extension compile; first complete app build in progress in CI |
| Menu bar integration works | Implemented and compiled; **not seen by a person** |
| Desktop widgets render | Pending the CI self-test; not seen by a person |
| Widgets can be moved and resized | Store and layout maths unit-tested; self-test pending; mouse interaction unverified |
| Layouts persist | Unit-tested through SQLite, including reopening the database file |
| Clock widget works | Implemented; renders in the self-test run; not seen by a person |
| CPU monitor uses real metrics | Yes: `SystemMetricsTests` reads the real runner, and the self-test prints a live CPU reading |
| Notes widget saves user content | State persistence unit-tested; typing itself unverified |
| Widget builder works | Implemented and compiled; model logic sound; **interactive behaviour unverified** |
| Data sources update correctly | Unit-tested with mocks, including polling, suspension and failure paths |
| Profiles work | Unit-tested |
| Permissions are handled correctly | Unit-tested at every enforcement point listed in SECURITY.md |
| Tests pass | Yes: all core suites pass on macOS 15 and Linux in CI |
| Unsupported features are documented | Yes: LIMITATIONS.md, COMPATIBILITY.md |
| Core app works offline | Yes by construction: no network use without a network widget; tests make no network calls |
| No critical known crashes | Unknown until the self-test has run and a person has used the app |
| Installation instructions exist | Yes: BUILD.md |

## Blockers encountered

1. **No macOS build tools locally, and installing a Swift toolchain in the development sandbox was
   declined.** Fallback: all compiling and testing was done through GitHub Actions.
2. **`macos-14` hosted runners cancel immediately** (image retired). CI uses `macos-15`. Consequence:
   the app has not been run on macOS 14 itself, only built for it.
3. **No signing identity.** Builds are ad-hoc signed; notarisation and team-signed App Group sharing are
   documented but not exercised.

## Next steps (in priority order)

1. Run the app on a real Mac and walk through "Not verified on real hardware" in LIMITATIONS.md; fix
   what breaks. Start with Edit-mode dragging and text entry in Notes.
2. Sign both targets with a development team and confirm the WidgetKit widget reads the snapshot and
   its buttons round-trip through `pending.json`.
3. Add XCUITest coverage for the builder and the overlay.
4. Build the XPC script host described in SECURITY.md.
5. Developer ID signing and notarisation in CI (needs secrets).

Resume command for an agent continuing this work:

```
Read WidgetForge/docs/PROGRESS.md and LIMITATIONS.md, then continue from "Next steps". Verify every
change with the WidgetForge GitHub Actions workflow (core tests, app build, self-test) before reporting.
```
