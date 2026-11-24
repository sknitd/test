# Building and installing

## Requirements
- macOS 14 Sonoma or newer (Apple silicon or Intel)
- Xcode 16 or newer (the project uses file-system-synchronised groups)

## Build in Xcode
1. Open `WidgetForge/WidgetForge.xcodeproj`.
2. Select the **WidgetForge** scheme and *My Mac*.
3. For WidgetKit data sharing, select your team under *Signing & Capabilities* for **both** targets
   (see "Signing" below). To just try the overlay widgets you can leave signing as "Sign to Run Locally".
4. Run (⌘R).

## Build from the command line
```bash
cd WidgetForge
Scripts/build_app.sh            # Release, universal, ad-hoc signed → build/WidgetForge.app
Scripts/make_dmg.sh             # → build/WidgetForge.dmg
```
With a Developer ID:
```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID Scripts/build_app.sh
Scripts/make_dmg.sh
NOTARY_PROFILE=widgetforge Scripts/notarize.sh
```

## Install
- From a DMG: open it and drag **WidgetForge** to **Applications**.
- An ad-hoc signed build (CI artifacts, or your own unsigned build) is not notarised. The first time,
  Control-click the app → **Open**, or allow it under *System Settings → Privacy & Security*.
- Launch WidgetForge. Three starter widgets (clock, CPU monitor, notes) appear on the desktop and a grid
  icon appears in the menu bar.
- To add a native WidgetKit widget: right-click the desktop → **Edit Widgets…** → WidgetForge, then
  right-click the placed widget → **Edit "WidgetForge"** to choose which of your widgets it shows.

## Signing
- **App Group.** The app and its widget extension share `snapshot.json` through an App Group whose id is
  `$(TeamIdentifierPrefix)com.widgetforge.shared` (build setting `WF_APP_GROUP`). macOS only grants silent
  access when both targets are signed by the same team. With ad-hoc signing the overlay backend is
  unaffected, but the WidgetKit widget may show "Open WidgetForge once to set up widgets", and macOS 15+
  may ask for permission to access data from other apps.
- **Hardened runtime** is enabled. JavaScriptCore then runs without JIT (no `allow-jit` entitlement is
  requested), which is slower but fine for widget scripts.
- **Notarisation** needs a Developer ID certificate and Apple ID credentials; neither is in this
  repository, so CI produces ad-hoc signed artifacts only.

## Regenerating the Xcode project
Only needed when folders, targets or build settings change:
```bash
python3 Scripts/generate_xcodeproj.py
python3 Scripts/make_icon.py      # needs Pillow; only if you change the icon
```

## Continuous integration
`.github/workflows/widgetforge.yml` (repository root) runs on every push that touches `WidgetForge/`:
core tests on Linux and macOS, then a Release build of the app, a launch self-test that prints measured
values, a screenshot, and a DMG uploaded as the `WidgetForge` artifact.
