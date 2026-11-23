# Troubleshooting

Start with the app's own screens: **Dashboard** (overall state and recent activity),
**Devices** (mouse and input adapter), **Permissions** (state of each permission). They
report the real state, including the reason something is unavailable. For anything
involving hardware, also run the probe:

```sh
Scripts/run_probe.sh --self-check
```

## The app will not open

**"MagicForge can't be opened because Apple cannot check it for malicious software" / "is
damaged and can't be opened".** The build is ad-hoc signed and not notarized, and the
download is quarantined.

- macOS 14: right-click the app → **Open** → **Open**.
- macOS 15 or later: try to open it, then **System Settings → Privacy & Security → Open
  Anyway**.
- Or: `xattr -dr com.apple.quarantine /Applications/MagicForge.app`

Do this only for a build you trust.

**It quits immediately or never shows a window.** Run the executable from Terminal to see
its output, and look at the log:

```sh
/Applications/MagicForge.app/Contents/MacOS/MagicForge
log show --last 5m --predicate 'subsystem == "com.magicforge.app"'
ls ~/Library/Logs/DiagnosticReports | grep -i MagicForge
```

**"Bad CPU type" or it will not launch on an Intel Mac.** The app was built for one
architecture. Check with `lipo -archs /Applications/MagicForge.app/Contents/MacOS/MagicForge`
and rebuild with `UNIVERSAL=1 Scripts/build_app.sh` or `Scripts/build_xcode.sh`.

**It requires a newer macOS.** MagicForge needs macOS 14.0 or later.

## Permissions are granted but the app says they are missing

macOS ties a permission to the app's code signature. An ad-hoc signed build has a different
signature every time it is built, so after a rebuild or update the entry in System Settings
still shows a switch that is on, but it belongs to the old build.

1. System Settings → Privacy & Security → Accessibility: select MagicForge, remove it with
   **−**, then add the current app again (or let the app prompt again).
2. Or reset from Terminal, then relaunch and grant again:

   ```sh
   tccutil reset Accessibility com.magicforge.app
   tccutil reset AppleEvents com.magicforge.app
   tccutil reset ListenEvent com.magicforge.app      # Input Monitoring
   ```

3. To stop this happening on every build, sign with a stable identity
   ([BUILD.md](BUILD.md#signing)).

If you run the binary with `swift run` or from Xcode, the permission is attributed to
Terminal or Xcode, not MagicForge. Test permissions with the app bundle.

After granting Accessibility, use the refresh control on the Permissions screen; if input
still does not start, quit and relaunch.

## No raw touch input ("gestures unavailable")

The Devices screen names the active adapter and, when raw touch is unavailable, the reason.

| Reason shown / probe result | Meaning | What to do |
|---|---|---|
| No Magic Mouse found | No supported device is connected | Check Bluetooth, power, pairing; see below |
| Framework could not be loaded, or a symbol is missing | The private `MultitouchSupport.framework` changed or is absent on this macOS version | Nothing locally. Use fallback triggers and report the macOS version with probe output |
| Framework loads but no multitouch device is listed | The system does not expose the mouse as a multitouch device right now | Reconnect the mouse; restart input from the Devices screen |
| Adapter running, no frames | Device is present but silent | Touch the surface; turn the mouse off and on; check the Touch Lab |

When raw touch is unavailable only the fallback triggers (button chords, hot keys) work.
That is by design ([LIMITATIONS.md](LIMITATIONS.md)).

## The mouse is not detected

- Confirm macOS itself sees it: System Settings → Bluetooth (or Mouse).
- Turn the mouse off and on, or toggle Bluetooth. The device list updates on connect and
  disconnect.
- A Magic Mouse 2 or USB-C model that is charging over its cable cannot be used while
  plugged in.
- Third-party mice are not Magic Mice: they have no touch surface, and only fallback
  triggers apply.

## Gestures trigger twice, or the system also reacts

macOS's own mouse gestures are still active: swipe between pages, swipe between full-screen
apps, smart zoom, Mission Control. MagicForge can see touches but cannot hide them from the
system. Turn off the overlapping gesture in **System Settings → Mouse**, or bind a different
gesture. See [LIMITATIONS.md](LIMITATIONS.md#overlap-with-system-gestures).

## Gestures fire by accident, or are not recognised

- Open the **Touch Lab** and watch the contacts while you perform the gesture: are the
  fingers detected as you expect?
- Use **Gesture Studio** to test a gesture without running its action, and adjust its
  thresholds; run calibration for your device.
- Disable gestures you do not use; fewer active gestures means fewer ambiguous cases.
- Resting fingers count as contacts. Multi-finger gestures are sensitive to how you hold
  the mouse.
- Check the **Dashboard** recent-gesture list to see what was recognised and which binding
  (if any) it matched.

## A gesture is recognised but nothing happens

- Gestures paused? Check the menu-bar item.
- Wrong profile? The Dashboard shows the active profile; an app-specific profile or a manual
  override may be in effect.
- The activity log on the Dashboard shows the action's result and error.
- Action unavailable: the action editor shows why (missing permission, unapproved script).
- Keyboard actions do nothing while **secure input** is active (password fields; some
  terminals enable it permanently).
- Window actions do nothing in apps that do not expose standard windows to Accessibility.

## Scripts do not run

- Scripts, shell commands and Shortcuts run only after you approve that exact content.
  Editing a script, or importing a profile, leaves it unapproved until you approve it.
- AppleScript that controls another app needs Automation permission for that app. If you
  once clicked **Don't Allow**, enable it in System Settings → Privacy & Security →
  Automation, or `tccutil reset AppleEvents com.magicforge.app`.
- Shell commands run with a minimal environment; use absolute paths to tools.

## Scrolling feels wrong

Turn Smart Scroll off on the Scrolling screen: scroll events then pass through untouched. If
scrolling is still wrong, the cause is not MagicForge. If it is only wrong with Smart Scroll
on, note the settings and report it. Scroll handling needs Accessibility permission.

## Clicks or scrolling stop working system-wide

MagicForge's event tap sits in the path of pointer events. If input ever misbehaves, quit
MagicForge (menu-bar item → Quit, or `killall MagicForge`); the tap disappears with the
process and input returns to normal immediately. Then report what you were doing.

## AI actions fail

- AI is off by default; enable it and enter endpoint, model and key on the AI screen.
- Use **Test connection**; it reports HTTP and authentication errors from the endpoint.
- The endpoint must be OpenAI-compatible. The key is stored in the Keychain; if macOS asks
  to allow Keychain access after a rebuild, that is the changed code signature again.

## Configuration problems

- Location: `~/Library/Application Support/MagicForge/`.
- If the file cannot be read or written, the app shows a persistence error instead of
  silently discarding your settings. Fix permissions on the folder, or move the damaged file
  aside and relaunch to start from defaults.
- Make a backup first: Settings → export backup. Backups contain no secrets.

## High CPU or memory use

Measure before reporting:

```sh
Scripts/measure_idle.sh --pid "$(pgrep -x MagicForge)" --duration 60 --output idle.txt
```

Leave the mouse alone while it samples, then repeat while using it. The Touch Lab draws
continuously while it is open; close it for an idle measurement.

## Build problems

| Symptom | Cause / fix |
|---|---|
| `error: Building the app needs macOS` | The app can only be built on macOS; on Linux only `swift test` of the portable modules works |
| `swift build --arch arm64 --arch x86_64` fails | Universal SwiftPM builds need full Xcode, not just Command Line Tools: `sudo xcode-select -s /Applications/Xcode.app` |
| Xcode: "Missing package product 'MFApp'" | Package resolution failed. File ▸ Packages ▸ Reset Package Caches; make sure `Package.swift` is next to `MagicForge.xcodeproj` |
| Xcode: signing error asking for a team | A local signing override. The committed project is ad-hoc; regenerate it with `ruby Scripts/generate_xcodeproj.rb` |
| CI: "MagicForge.xcodeproj is stale" | The project was edited by hand or the spec changed; regenerate and commit |
| `codesign` fails with "resource fork, Finder information, or similar detritus" | `xattr -cr dist/MagicForge.app`, then run the script again |
| A module fails to compile while you work on another | `Scripts/test.sh --module <Module>` builds one portable module in isolation |
| Stale build results | Remove `.build`, `build` and `dist`, then rebuild |

## Reporting a problem

Include:

- macOS version and Mac model (Apple silicon or Intel);
- mouse model and connection (Bluetooth or cable);
- output of `Scripts/run_probe.sh --self-check`;
- the diagnostics export from Settings (leave "include touch frames" off unless asked; the
  default export contains no touch coordinates);
- `log show --last 10m --predicate 'subsystem == "com.magicforge.app"'`;
- what you did, what you expected and what happened.
