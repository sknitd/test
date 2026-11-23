# MagicForge progress

Status legend: **verified** = executed and observed; **written** = code exists but has not been
compiled/run in the environment that matters; **pending** = not done.

This file is updated by the lead after each milestone. See the bottom for how to resume.

## Environment
- Development container: Linux x86_64, Swift 6.0.3. No macOS SDK, no Xcode, no Magic Mouse.
- macOS verification: GitHub Actions runners `macos-15` (Xcode 16.0–16.4) and `macos-26` (Xcode 26.x).
  No macOS 14 runner and no Xcode 15 exist, so macOS 14 is a compile-time deployment target only.
- Hardware verification (real Magic Mouse touch frames): **pending** — cannot be done here.

## Milestones (as of CI run #4, commit fed7c5c)
CI run: https://github.com/sknitd/test/actions/runs/45177608947 — details in docs/CI_LOG.md.

| Area | State |
|---|---|
| Portable modules (core, gestures, profiles, automation, AI client, engine) | **verified**: 362 tests pass on Linux and on macOS 15 / 26 runners |
| macOS modules (input, devices, actions, UI, app, mfprobe) | **verified to compile** with Xcode 16.0, 16.4 and 26.6 (`swift build`, no errors) |
| Xcode project | **verified**: `xcodebuild` Release build succeeds on all three macOS jobs |
| Packaging | **verified**: `Scripts/build_app.sh` and `Scripts/make_dmg.sh` produce a signed (ad-hoc) .app and a valid .dmg; uploaded as CI artifacts |
| Launch | **verified**: app starts and stays alive 20 s on the runners (no mouse attached); idle CPU 0.2–0.4 % avg, RSS 91–114 MB |
| MultitouchSupport bridge | **verified**: framework loads and all symbols resolve on macOS 15.8 and 26.7 (arm64); 0 devices on the runners |
| Real Magic Mouse touch frames, every touch gesture on hardware | **pending** — needs a Mac with a Magic Mouse (`Scripts/run_probe.sh --frames 10`) |
| Interactive UI behaviour (every screen, radial menu, onboarding) | **written**, compiled, never exercised by a person or UI test |
| Action executors against the real OS (window snapping, media keys, Mission Control, scripts) | **written**, compiled, not exercised |
| Missing-permission behaviour | **pending** — runners report Accessibility as granted |
| macOS 14 runtime, Intel hardware | **pending** — no runner available (universal binary builds) |
| Developer ID signing / notarization | **pending** — needs your Apple Developer account (docs/RELEASE.md) |

## Acceptance criteria
- [x] Xcode project exists and builds
- [x] Native macOS app builds
- [x] Tests run successfully (362)
- [x] Device detection implemented (compiled; 0 devices on CI)
- [x] Profiles persist across launches (engine tests)
- [x] Unsupported features disclosed (FEASIBILITY.md, LIMITATIONS.md)
- [x] README documents installation
- [x] Final build packaged (.app, .dmg artifacts)
- [ ] Menu bar controls work — compiled, not exercised
- [ ] Permission onboarding works — compiled, not exercised
- [ ] Supported gestures recognized on a real mouse — synthetic input only
- [ ] Actions execute correctly on macOS — mocks only
- [ ] Native mouse functionality remains usable — not checked on hardware
- [ ] No critical known crashes — only a 20 s idle launch was observed

## Resume
1. On a Mac with a Magic Mouse: `Scripts/run_probe.sh --self-check`, then `--frames 10`, then `--gestures 20`.
2. Build and run (`Scripts/build_app.sh && open dist/MagicForge.app`), grant Accessibility, walk docs/TESTING.md's manual checklist.
3. Record results here.
