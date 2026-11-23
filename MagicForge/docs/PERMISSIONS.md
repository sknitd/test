# MagicForge permissions

MagicForge asks macOS for as little as it can. This page lists every privacy (TCC) permission
the app can use, exactly which features depend on it, what happens without it, and how to
recover when macOS gets confused.

The code lives in `Sources/Actions/SystemPermissions.swift` (status / request / deep links) and
`Sources/Actions/SystemActionPerformer.swift` (`requiredPermission(for:)`, `availability(of:)`).

## Summary

| Permission | System Settings pane | Needed for | Prompted by |
| --- | --- | --- | --- |
| Accessibility | Privacy & Security › Accessibility | Posting keys / clicks / scrolls, window management, reading the selection, the global event tap | MagicForge, once per launch, only when you ask |
| Input Monitoring | Privacy & Security › Input Monitoring | Listen-only observation of input (only if the input probe shows it is required) | MagicForge, once per launch, only when you ask |
| Automation | Privacy & Security › Automation | AppleScript actions that control other apps | macOS itself, the first time a script talks to each app |
| Notifications | Notifications › MagicForge | Workflow "notify" steps and status messages | macOS, the first time a notification is posted |

MagicForge does **not** use Screen Recording, Full Disk Access, Camera, Microphone, Contacts or
Location.

## Rules the app follows

- **Checking never prompts.** `status(of:)` only reads state (`AXIsProcessTrusted()`,
  `IOHIDCheckAccess`). Opening the Permissions screen or the dashboard never shows a dialog.
- **Running an action never prompts.** When a permission is missing the action fails with
  `permissionDenied(<kind>)`, the failure is shown in the activity list, and nothing else happens.
- **At most one prompt per permission per launch.** `request(_:)` remembers which kinds it has
  already asked for; later calls are no-ops. Use the "Open System Settings" button after that.
- **No fake success.** Actions that cannot work on this Mac are reported as unavailable with a
  reason (`availability(of:)`), not silently ignored.

## Accessibility

Needed by:

- **Keyboard shortcut actions** and everything implemented by pressing a shortcut:
  Spotlight (⌘Space), Lock Screen (⌃⌘Q), screenshots (⇧⌘3, ⇧⌘4, ⇧⌘4 then Space), Copy (⌘C),
  Paste (⌘V), Paste Text.
- **Media keys**: volume up / down / mute, brightness up / down, play / pause, next, previous
  (posted as the same system-defined events Apple keyboards send).
- **Mouse actions**: left / right / middle / double click, drag lock, scroll.
- **Window actions**: snap, maximize, centre, resize, restore, move to next display, minimize,
  close (Accessibility API on the focused window of the frontmost app).
- **Reading the selected text** for AI prompts (Accessibility attribute first, synthetic ⌘C as
  fallback).
- The **global event tap** used for fallback triggers, hot keys and Smart Scroll (input module).

Not needed by: Mission Control, App Exposé, Show Desktop, Launchpad, launching / switching /
hiding / quitting apps, opening URLs and files, Copy Text (clipboard only), scripts.

Without it: the actions above fail with `permissionDenied(accessibility)` and show
"needs Accessibility" in the UI. macOS silently drops synthetic events from untrusted apps, so
MagicForge checks first instead of pretending.

Status caveat: macOS cannot tell "never asked" from "refused" for Accessibility. MagicForge shows
*not determined* until it has shown the prompt during the current launch, and *denied* after that
if access is still missing.

## Input Monitoring

Only relevant when the feasibility probe shows that listen-only input observation needs it on
your macOS version. The status comes from `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` and
the prompt from `IOHIDRequestAccess`. Nothing in the Actions module depends on it. Without it,
features that would need listen-only observation are disabled and say so.

## Automation (Apple Events)

Only AppleScript actions that send Apple Events to other applications (`tell application "…"`)
need it. Consent is stored **per target application**, so:

- There is no global "granted" state. MagicForge reports *not determined* for this permission.
- MagicForge has no prompt of its own. macOS asks ("MagicForge wants to control …") the first
  time a script addresses a given app. `request(.automation)` intentionally does nothing.
- If you refuse, the script fails with error −1743 and MagicForge reports
  `permissionDenied(automation)`. Re-enable it under Privacy & Security › Automation › MagicForge.
- The app's `Info.plist` must contain `NSAppleEventsUsageDescription`; without it macOS denies
  Apple Events without asking.

AppleScript runs in `/usr/bin/osascript` (source passed on standard input), started by
MagicForge, so macOS attributes the request to MagicForge.

## Notifications

Requested lazily the first time MagicForge posts a notification (alerts and sound only). If you
decline, notifications are skipped and a log line is written. When MagicForge is run without an
app bundle (`swift run`), the notification centre is unavailable and messages go to the log only.

## Screen Recording — deliberately not used

Screenshot actions press the system shortcuts (⇧⌘3 / ⇧⌘4) instead of running `screencapture`
from MagicForge, because the latter would require the Screen Recording permission for
MagicForge. The system takes the screenshot itself; MagicForge never sees the pixels.

## Things that follow your own macOS settings

Some actions press the **default** macOS shortcut. If you changed or disabled that shortcut in
System Settings › Keyboard › Keyboard Shortcuts, the action presses the default keys and will do
whatever those keys now do (often nothing):

| Action | Keys pressed |
| --- | --- |
| Spotlight | ⌘Space |
| Lock Screen | ⌃⌘Q |
| Screenshot (full screen) | ⇧⌘3 |
| Screenshot (selection) | ⇧⌘4 |
| Screenshot (window) | ⇧⌘4, then Space |

If you use different shortcuts, bind the gesture to a Keyboard Shortcut action with your keys.

Mission Control, App Exposé and Show Desktop do not depend on shortcuts: they start
`/System/Applications/Mission Control.app` (with mode arguments `2` and `1` for App Exposé and
Show Desktop). Launchpad opens `Launchpad.app`, or `Apps.app` on macOS versions that replaced it;
if neither exists the action is shown as unavailable.

**Notification Center** has no public API and no default shortcut, so the action is always
reported as unavailable rather than faked. If you assign your own shortcut to "Show Notification
Center" in System Settings, bind a Keyboard Shortcut action to it.

Brightness keys only affect displays that respond to the keyboard brightness keys (built-in and
Apple displays).

## Clipboard behaviour

- **Paste Text** puts the text on the clipboard, presses ⌘V and restores the previous clipboard
  contents about 0.6 s later, unless something else changed the clipboard in between. The
  temporary entry is marked `org.nspasteboard.TransientType` so clipboard managers can skip it.
- **Reading the selection** via ⌘C (fallback only) waits up to 300 ms for the clipboard to
  change, then restores the previous contents.
- Clipboard text, typed text and script bodies are never logged.

## Scripts run your code

AppleScript, shell and Shortcuts actions execute arbitrary code with your user privileges.
MagicForge only runs a script whose hash you approved (`Configuration.approvedScriptHashes`);
the engine checks this before the executor is called. Scripts imported from someone else's
profile stay blocked until you review and approve them.

Execution details: `/bin/zsh -c` for shell commands (falls back to `/bin/sh`),
`/usr/bin/osascript` for AppleScript, `/usr/bin/shortcuts run <name>` for Shortcuts; a minimal
environment (`PATH`, `HOME`, `USER`, `LOGNAME`, `LANG`, `TMPDIR`, `SHELL`), working directory
`~`, standard input closed, output captured (first 64 KB), and a hard timeout (20 s by default):
SIGTERM, then SIGKILL two seconds later, sent to the script's process group when it has its own.
A non-zero exit status is reported as a failure with the first lines of the error output.

## Troubleshooting

**The switch is on but MagicForge still says "not granted".**
TCC ties a grant to the app's code signature. Development and ad-hoc signed builds get a new
signature every time the binary changes, so the old entry no longer matches even though the
checkbox still looks enabled. Remove the entry with the "–" button (or reset it, below), start
MagicForge again and grant it afresh. Builds signed with a stable Developer ID do not have this
problem.

**Reset a permission** (replace the bundle identifier with the one of your build):

```sh
tccutil reset Accessibility com.magicforge.app
tccutil reset ListenEvent com.magicforge.app      # Input Monitoring
tccutil reset AppleEvents com.magicforge.app      # Automation
tccutil reset All com.magicforge.app              # everything for MagicForge
```

Quit MagicForge first, run the command, then start it again and re-grant.

**Granted while the app was running.** Accessibility usually takes effect immediately;
MagicForge re-checks the status whenever the Permissions screen is shown. If synthetic input
still does nothing, quit and reopen MagicForge.

**Running from Terminal / Xcode.** A bare executable started with `swift run` inherits the
permissions of the *launching* app (Terminal, Xcode), so grant Accessibility to that app, or
build and run the `.app` bundle.

**Deep links** used by the "Open System Settings" buttons:

- `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`
