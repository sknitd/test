# MagicForge progress

Status legend: **verified** = executed and observed; **written** = code exists but has not been
compiled/run in the environment that matters; **pending** = not done.

This file is updated by the lead after each milestone. See the bottom for how to resume.

## Environment
- Development container: Linux x86_64, Swift 6.0.3. No macOS SDK, no Xcode, no Magic Mouse.
- macOS verification: GitHub Actions runners `macos-15` (Xcode 16.0–16.4) and `macos-26` (Xcode 26.x).
  No macOS 14 runner and no Xcode 15 exist, so macOS 14 is a compile-time deployment target only.
- Hardware verification (real Magic Mouse touch frames): **pending** — cannot be done here.

## Milestones
| Area | State |
|---|---|
| Core contract (MFCore, MFUtilities) | verified on Linux (builds) |
| Catalog, automation, AI client | verified on Linux (unit tests) |
| Profiles, persistence, import/export | verified on Linux (unit tests) |
| Gesture engine + synthetic generator | written; tests in progress |
| Engine integration (AppModel) | in progress |
| macOS input (MultitouchSupport adapter, event tap, HID monitor, mfprobe) | written; not yet compiled on macOS |
| macOS action executors | written; not yet compiled on macOS |
| UI (shell, gestures, touch lab, actions, automation, radial menu, AI) | written / in progress; not yet compiled on macOS |
| Xcode project, scripts, CI | written; structure validated on Linux only |
| macOS build + tests on CI | pending |
| .app / .dmg packaging on CI | pending |
