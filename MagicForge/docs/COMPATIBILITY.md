# MagicForge — compatibility

Status legend: **CI** = will be exercised by CI (`swift build`, `mfprobe --self-check`; no hardware),
**unverified** = never executed, expectation only. As of writing nothing has run on macOS or with a
Magic Mouse; see `FEASIBILITY.md` → Verification status. The lead appends CI results.

## Magic Mouse models

| Model | USB / BT product id | Vendor id | Detection (IOHID) | Raw contacts (private) | Notes |
|---|---|---|---|---|---|
| Magic Mouse (1st gen, A1296, AA batteries) | 0x030D | 0x05AC | unverified | unverified; family id believed 112 | Bluetooth only |
| Magic Mouse 2 (A1657, Lightning) | 0x0269 | 0x004C (BT), 0x05AC (USB) | unverified | unverified; family id believed 113 | Unusable while charging over USB; shows up as a USB device then |
| Magic Mouse (USB-C, 2024) | 0x0323 | 0x004C (BT), 0x05AC (USB) | unverified | unverified; family id unknown → classified by sensor shape | Same touch surface as Magic Mouse 2 as far as known |
| Unknown future model | other | Apple | by product name containing "Magic Mouse" | by sensor shape | reported as `unknownMagicMouse` |

Product ids are confirmed against the Linux kernel's `hid-ids.h`; the rest is community knowledge.
Surface geometry is assumed to be 52 × 90 mm for all models (`SurfaceGeometry.magicMouse`).

## macOS versions

| macOS | Build / CI | Public tier (event tap, HID) | Private tier (MultitouchSupport) |
|---|---|---|---|
| 14 Sonoma (deployment target) | **No CI runner and no Xcode 15 available** — not built or run anywhere | unverified; all APIs used exist since ≤ 10.15 | unverified; MiddleClick-style tools are reported to work |
| 15 Sequoia | CI: macos-15, Xcode 16.0–16.4 (Swift 6.0–6.1 compilers in Swift 5 mode) | compile + self-check on CI; behaviour unverified | symbol resolution + struct stride on CI; frames unverified (MiddleClick advertises macOS 15 support) |
| 26 Tahoe | CI: macos-26, Xcode 26.x | compile + self-check on CI; behaviour unverified | symbol resolution on CI; frames unverified. No independent source confirming Magic Mouse contact frames on 26 was found — highest risk row |

The code avoids Swift features newer than 5.9, but it has only been syntax-checked and type-checked
on Linux with Swift 6.0.3 against stub declarations. Xcode 15.x compatibility is untested because CI
has no such toolchain.

## Architectures

| Architecture | Status |
|---|---|
| Apple Silicon (arm64) | unverified; touch struct layout (96 bytes) follows from standard alignment rules; CI runners are arm64 |
| Intel (x86_64) | unverified and not covered by CI unless an Intel runner is added; same struct layout verified on x86_64 Linux |
| Rosetta | not a target |

## Environment requirements

- Not sandboxed; Developer ID signed (stable signature so TCC grants persist); hardened runtime is fine.
- Accessibility permission for the event tap, event posting and window management.
- No permission is expected for device detection and raw contacts (unverified).
- Not distributable through the Mac App Store.

## Known risks

1. Private framework changes (symbols, struct layout, device classification) with any macOS update —
   mitigated by runtime symbol lookup, layout assertion and the fallback tier.
2. Native Magic Mouse gestures (scroll, two-finger swipe, smart zoom) keep working alongside
   MagicForge gestures; conflicting ones must be disabled by the user in System Settings.
3. Scroll-origin detection is heuristic when a trackpad is used at the same time.
4. Secure input (password fields) suspends key event delivery to taps, so hot keys pause.
