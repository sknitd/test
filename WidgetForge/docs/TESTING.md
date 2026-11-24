# Testing

## Running
```bash
cd WidgetForge
swift test                        # all core suites; no app launch, no network
swift test --filter DataSourceTests
```
CI runs the same command on macOS 15 (Xcode toolchain) and in a `swift:5.10` Linux container. The Linux
run skips suites that need Apple frameworks (JavaScriptCore, SQLite3 module, Mach/IOKit metrics).

Unit tests never touch the real network: HTTP goes through `MockTransport`, WebSockets through a fake
`StreamTransport`, secrets through `InMemorySecretStore`, time through injected clocks and sleepers.

## What is covered

| Area | Suite | Cases |
| --- | --- | --- |
| Widget lifecycle | `WidgetLifecycleTests` | create, update, delete to trash, restore, duplicate, reload from store, corrupt record skipped, SQLite on disk |
| Layout | `LayoutTests` | snap, move with lock, resize minimums, grouped move, align/distribute, alignment guides, display disconnect/reconnect, free slot, responsive constraints, saved layout restore |
| Data | `DataSourceTests` | success + transform, 4xx no retry, 5xx retry with exponential backoff, give-up, timeout, `Retry-After`, cache TTL, offline fallback across relaunch, validation, allowlist, revoked permission hides cache, secret/host binding, settings placeholders, local-only HTTP, request de-duplication, files, metrics permission, interval clamping, suspend/resume/unsubscribe, one-shot, WebSocket delivery and fallback |
| Scripts | `ScriptRuntimeTests` | SDK example end to end, compile errors, missing definition, invalid `render()` output, runtime errors, no ambient authority, unauthorised metrics/fetch and revocation, infinite-loop termination, async timeout, resource limits (output, fetch count, storage, logs), storage/settings/data/actions, cancellation |
| Schema & packages | `SecurityTests`, `ExampleFilesTests` | valid schema, 13 invalid shapes, depth/size limits, undeclared capabilities, export scrubbing, round trip, bad packages, checksum tamper, bare definitions, shipped example files |
| Automation | `AutomationTests` | trigger → ordered actions, edge triggering, conditions, cooldown, cancellation, failure, loop guard, self-retrigger guard, timer and data-condition triggers, disabled/paused/removed rules, Codable |
| Profiles | `ProfileTests` | switching, per-profile layout restore, persistence across relaunch, rule resolution (time, overnight, app, display, priority), automatic switch and restoration |
| Templates | `TemplateTests` | 25 unique, all validate, all declare what they use, Codable round trip, setup instructions, no sample data |
| AI builder | `AIGeneratorTests` | fenced JSON extraction, script stripping, permission recomputation, invalid/unsafe output, request shape, disabled/missing key never calls out, service errors |
| Core | `JSONAndTemplateTests`, `SharedSnapshotTests` | JSON paths, placeholders and filters, conditions, node decoding, actions, fuzzy search, diagnostics, CSV, WidgetKit snapshot hand-off |
| Real metrics | `SystemMetricsTests` | reads the actual machine and checks plausibility (ranges, core count, total memory, no fabricated battery) |

## Self-test of the built app
`WidgetForge.app/Contents/MacOS/WidgetForge --self-test` launches the real application, waits, moves and
resizes a widget through the store, toggles edit mode, and prints a JSON report: overlay window levels and
visibility, runtime count, measured idle CPU and memory, update latency, a real metrics sample, and any
logged errors. CI runs it and takes a screenshot. Results are recorded in `PROGRESS.md`.

## What is not automated
SwiftUI views, the edit overlay's mouse handling, the Builder canvas gestures, the Command Center and the
WidgetKit extension are compiled in CI but have no UI tests. They need a person at a Mac; `PROGRESS.md`
lists each as "Hardware verified: no" and `LIMITATIONS.md` says what to check.
