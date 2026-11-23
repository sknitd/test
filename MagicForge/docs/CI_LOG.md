# MagicForge CI log

One entry per GitHub Actions run of `.github/workflows/magicforge.yml` on branch
`ccr-98b7fad9-jid67a` (repo `sknitd/test`). Only facts read from the job logs are recorded.
Runner facts: `macos-15` = macOS 15.8.2 (24H232), arm64 "Apple M1 (Virtual)", 3 cores, 7 GB;
`macos-26` = macOS 26.7.2 (25G332), same hardware class. No Magic Mouse on any runner.

## Run #1 — id 45043515937 — commit 86baaa6
Cancelled after 3 s (superseded by concurrency group). Nothing to learn.

## Run #2 — id 45174444697 — commit 1a01839 — conclusion: success
https://github.com/sknitd/test/actions/runs/45174444697

First compilation of the macOS-only modules against the real SDK. The tree at that commit already
contained all of MFDevices, MFInput, MFActions, MFApp, mfprobe and all of MFUI (77 MFUI files
compiled); `Sources/Engine` contained only the contract `AppModel.swift`.

| job | toolchain | swift build | swift test | mfprobe --self-check | xcodebuild | build_app.sh | make_dmg.sh | universal SwiftPM | launch smoke |
|---|---|---|---|---|---|---|---|---|---|
| macOS (macos-15) | Xcode 16.4 (16F6), Swift 6.1.2 | success | success, 293 tests, 0 failures | success | success | success | success | success (`x86_64 arm64`) | success |
| macOS (macos-15-xcode16.0) | Xcode 16.0 (16A242d), Swift 6.0 | success | success, 293 tests, 0 failures | success | success | success | success | not run (matrix) | success |
| macOS (macos-26) | Xcode 26.6 (17F113), Swift 6.3.3 | success | success, 293 tests, 0 failures | success | success | success | success | not run (matrix) | success |
| Linux portable modules (swift:6.0-noble) | Swift 6.0 | success | success | – | – | – | – | – | – |
| Linux portable modules (swift:5.10-noble) | Swift 5.10 (informational) | success | success | – | – | – | – | – | – |
| Project, scripts and resources | – | shell lint, plists, icons, Xcode project reproducible: all success | | | | | | | |

Compile errors: none on any toolchain. Compiler warnings: exactly one distinct warning on all three
macOS toolchains — `Sources/UI/Actions/ActionEditor.swift:130:9: warning: default will never be executed`.

xcodebuild: `** BUILD SUCCEEDED **`, universal (`x86_64 arm64`), `flags=0x10002(adhoc,runtime)`,
`Signature=adhoc`. DMGs: `MagicForge-0.1.0-<id>.dmg`, 3.2 MB each, `hdiutil verify` VALID.

mfprobe --self-check (identical on all three runners apart from the OS version): MultitouchSupport
loaded, all 5 required and all 7 optional symbols resolved, touch struct stride 96 (expected 96),
0 multitouch devices, adapter "unavailable: No Magic Mouse multitouch device is connected",
0 HID Magic Mouse devices, Accessibility trusted = true, listen/post event access = true, listen-only
and active event taps created. (The hosted runner image pre-grants TCC permissions to the runner's
shell, so "the app idles without Accessibility permission" is NOT what these runs exercise.)
Full JSON: docs/FEASIBILITY.md, "CI probe results".

Launch smoke test (SwiftPM-built `dist/MagicForge.app`, launched directly, 10 s + 20 s sampling):
process alive throughout on all three runners, empty stderr, no crash report.

| job | ps CPU % avg / max | ps RSS MB avg (min–max) | top CPU % avg / max | top idle wake-ups per sample avg / max |
|---|---|---|---|---|
| macos-15 | 0.03 / 0.60 | 86.7 (84.9–87.7) | 0.11 / 2.00 | 0.0 / 0 |
| macos-15-xcode16.0 | 0.11 / 0.70 | 86.2 (84.8–87.0) | 0.12 / 0.80 | 352.2 / 354 |
| macos-26 | 0.33 / 3.90 | 110.0 (108.2–110.9) | 0.14 / 1.80 | 0.0 / 0 |

The wake-up column disagrees between two jobs on the same OS image (0 vs ~352 per sample) while CPU
is equally low, so that column is not trustworthy as measured; only CPU and RSS are relied on.

Artifacts per macOS job: `MagicForge-dmg-<id>`, `MagicForge-app-<id>`, `probe-<id>`, `logs-<id>`;
Linux: `linux-logs-0`, `linux-logs-1`.

Changes made after this run:
- `Sources/UI/Actions/ActionEditor.swift`: removed the unreachable `default:` branch of the
  exhaustive `ActionCategory` switch (the only compiler warning). No behaviour change.

## Run #3 — id 45176093182 — commit cdb7a6d — superseded before completion
https://github.com/sknitd/test/actions/runs/45176093182

Same tree as run #2 plus the finished Sources/UI/{Actions,Automation,RadialMenu,AI} edits and the
warning fix; Sources/Engine still the contract-only `AppModel.swift`.
- macOS (macos-15) and macOS (macos-26): every step success (swift build, swift test, mfprobe,
  xcodebuild, build_app.sh, make_dmg.sh, smoke; universal SwiftPM build success on macos-15).
- macOS (macos-15-xcode16.0): started late (runner queue); swift build, swift test and mfprobe
  success, xcodebuild still running when run #4 was pushed (job cancelled by the concurrency group).
- Linux (6.0, 5.10) and project lint: success.

Changes made after this run (pushed as run #4, together with the finished engine,
Sources/Engine/** and Tests/EngineTests/**):
- `Package.swift`: test targets now declare every module they import (MFUtilities for all;
  MFGestures, MFProfiles, MFAutomation, MFIntegrations for EngineTests). They previously built
  only because SwiftPM exposes transitive modules.
- `Sources/App/CompositionRoot.swift`: the composition root keeps the `SystemActionPerformer` and
  calls `releaseHeldInput()` when gestures become paused (Observation tracking of
  `AppModel.isPaused`) and on app termination. Behaviour change: a held drag lock is now released
  on pause/quit instead of staying down.
- Linux here (Swift 6.0.3) after these changes: `swift test` 362 tests, 0 failures.

## Run #4 — id 45177608947 — commit fed7c5c — conclusion: all jobs success
https://github.com/sknitd/test/actions/runs/45177608947

First run with the finished engine (Sources/Engine/**, Tests/EngineTests/**) and the changes
listed under run #3. (Run #3 itself ended as "cancelled", as expected.)

| job | toolchain | swift build | swift test | mfprobe --self-check | xcodebuild | build_app.sh | make_dmg.sh | universal SwiftPM | launch smoke |
|---|---|---|---|---|---|---|---|---|---|
| macOS (macos-15) | Xcode 16.4, Swift 6.1.2 | success | success, 362 tests, 0 failures | success | success | success | success | success (`x86_64 arm64`) | success |
| macOS (macos-15-xcode16.0) | Xcode 16.0, Swift 6.0 | success | success, 362 tests, 0 failures | success | success | success | success | not run (matrix) | success |
| macOS (macos-26) | Xcode 26.6, Swift 6.3.3 | success | success, 362 tests, 0 failures | success | success | success | success | not run (matrix) | success |
| Linux portable modules (swift:6.0-noble) | Swift 6.0 | success | success | – | – | – | – | – | – |
| Linux portable modules (swift:5.10-noble) | Swift 5.10 (informational) | success | success | – | – | – | – | – | – |
| Project, scripts and resources | – | all steps success | | | | | | | |

Compile errors: none. Compiler warnings in the `swift build` logs: none on any of the three toolchains.
xcodebuild: `** BUILD SUCCEEDED **` on all three. DMGs 3.4 MB each, `hdiutil verify` VALID.

mfprobe --self-check: the JSON of each runner is byte-identical to the one recorded from run #2
(docs/FEASIBILITY.md, "CI probe results").

Launch smoke test, now with the real engine started: alive after 10 s and after 20 s of sampling on
all three runners, empty stderr, no crash report. The app's own unified-log lines on each runner:
`[com.magicforge.app:devices] Device monitor started, 0 Magic Mouse device(s) present` and
`[com.magicforge.app:eventtap] Event tap started`.

| job | ps CPU % avg / max | ps RSS MB avg (min–max) | top CPU % avg / max | top idle wake-ups per sample avg / max |
|---|---|---|---|---|
| macos-15 | 0.29 / 4.40 | 91.9 (90.5–92.8) | 0.23 / 2.90 | 0.0 / 0 |
| macos-15-xcode16.0 | 0.17 / 1.10 | 91.3 (90.0–92.1) | 0.31 / 3.60 | 185.6 / 189 |
| macos-26 | 0.37 / 4.10 | 114.4 (112.6–115.4) | 0.23 / 1.90 | 193.4 / 195 |

(The wake-up column is again inconsistent between jobs; see run #2.) These are numbers from a
virtualised runner with no Magic Mouse and with the event tap installed; they say nothing about
CPU use while touch frames arrive.

Artifacts: `MagicForge-dmg-<id>`, `MagicForge-app-<id>`, `probe-<id>`, `logs-<id>` for
`<id>` in macos-15, macos-15-xcode16.0, macos-26; `linux-logs-0`, `linux-logs-1`.

Not exercised by any run: real touch input, macOS 14, Intel hardware, missing TCC permissions
(the runner shell has Accessibility / event access granted), and any interactive UI path beyond
launching the main window.
