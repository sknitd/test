# Limitations

This is the list of things MagicForge cannot do, does not guarantee, or has not verified.
For the current verification status of each feature see [PROGRESS.md](PROGRESS.md).

## Raw touch input depends on a private Apple framework

- Finger positions come from `MultitouchSupport.framework`, a private framework with no
  documentation, no stability guarantee and no supported use by third parties. Apple can
  change or remove it in any macOS update, including minor ones, without notice.
- The app loads it at runtime and checks every symbol. If loading fails, raw-touch gestures
  are disabled and the app says why; only fallback triggers remain. That is the designed
  behaviour, not an error to work around.
- The layout of the contact data is not published. A change in layout that still loads
  could produce wrong data rather than a clean failure. The adapter applies sanity checks,
  but this risk cannot be eliminated.
- There is no public alternative. Public APIs expose pointer movement, buttons and scroll
  events only. See [FEASIBILITY.md](FEASIBILITY.md).

## Distribution

- **No Mac App Store.** The App Store requires the App Sandbox and forbids private API use.
- **No App Sandbox.** Session event taps, synthetic input events, Accessibility control of
  other apps and loading the private framework are all incompatible with the sandbox. The
  app therefore runs with the user's full privileges; the mitigations are described under
  "Trust model" in [ARCHITECTURE.md](ARCHITECTURE.md).
- **Builds from this repository are ad-hoc signed and not notarized.** Gatekeeper blocks
  them until the user overrides it, and privacy permissions must be re-granted after every
  rebuild. A Developer ID signed, notarized build avoids both, but needs a paid Apple
  Developer account ([RELEASE.md](RELEASE.md)). Notarization of this app has not been
  attempted; whether Apple's notary service accepts it is unverified.
- No automatic updates.

## Permissions

- Without Accessibility permission there is no event tap and no synthetic input: fallback
  triggers, Smart Scroll and most actions are unavailable.
- macOS can disable an event tap that responds slowly or after certain system events. The
  app re-enables it when notified, but a short gap is possible.
- Secure input (password fields, some terminal modes, the login window) blocks synthetic
  keystrokes and key observation system-wide. Keyboard actions do nothing there.
- AppleScript and app-control actions prompt once per target app (Automation). If denied,
  the action fails until the user changes it in System Settings.

## Overlap with system gestures

macOS has its own Magic Mouse gestures (System Settings → Mouse): one-finger scrolling,
secondary click, smart zoom (double-tap), swipe between pages (one-finger horizontal),
swipe between full-screen apps (two-finger horizontal) and Mission Control (two-finger
double-tap).

- Reading contacts through the private framework is passive. MagicForge sees the touches,
  but it cannot stop the system from also acting on them. A MagicForge gesture that
  resembles an enabled system gesture triggers both.
- The practical remedy is to turn off the overlapping system gesture, or bind MagicForge to
  gestures the system does not use. [GESTURES.md](GESTURES.md) notes the overlaps.
- Every touch movement also scrolls or moves the pointer as usual. Swipe gestures on the
  surface produce scroll events in the app under the pointer unless Smart Scroll is
  configured to suppress them. Suppression happens in the event tap and needs Accessibility.
- Events are attributed to the Magic Mouse on a best-effort basis. With a trackpad or second
  mouse in use at the same time, scroll handling may apply to the wrong device.

## Recognition

- Gesture recognition is heuristic. Expect some false positives and missed gestures;
  thresholds are adjustable and calibration is per device, but no setting is right for
  every hand.
- The Magic Mouse surface is small and curved, and resting fingers are normal while
  clicking. Three-finger and compound gestures are inherently less reliable than
  one-finger ones.
- The test suite uses synthetic touch frames built from a model of the surface, not
  recordings from a device. Passing tests show the recogniser is consistent with the model,
  not that the model matches real contact data.

## Actions

- Window actions use the Accessibility API. Apps that do not expose standard windows, or
  refuse to be moved or resized, will not respond.
- Some system actions rely on synthesised key or media events and therefore depend on the
  user's system shortcut settings.
- "Selected text" is obtained through the pasteboard (a synthesised copy); it briefly
  touches the clipboard and does not work in apps that block copying.
- Scripts run with the user's privileges. Hash-based approval protects against a script
  changing behind your back, not against approving a harmful script.

## AI

- Off by default. When used, the selected or clipboard text is sent to the endpoint you
  configured; that provider's privacy terms apply. Only OpenAI-compatible chat endpoints
  are supported. There is no on-device model.

## Platform and toolchain

- macOS 14.0 or later only. The deployment target is enforced at compile time; running on
  macOS 14 is not exercised by CI, which has only macOS 15 and macOS 26 runners.
- The minimum build toolchain verified by CI is Xcode 16.0. Earlier Xcode versions are not
  verified.
- CI machines have no Magic Mouse and no privacy permissions. CI demonstrates that the app
  builds, launches and stays alive, nothing about gestures.

## Not verified on hardware

Anything involving a physical Magic Mouse (which models work, over Bluetooth or cable,
frame rates, latency, battery reporting, reconnect behaviour, recognition accuracy, idle
CPU and memory) is unverified until someone runs the checklist in
[TESTING.md](TESTING.md) and records the result. The current list of verified and
unverified items is kept in [PROGRESS.md](PROGRESS.md); hardware and OS combinations are in
[COMPATIBILITY.md](COMPATIBILITY.md). Treat anything not listed there as verified as
untested.
