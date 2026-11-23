# Building MagicForge

There are two supported ways to produce `MagicForge.app`. Both compile the same sources: the
Swift package in `Package.swift`. The Xcode project is a thin wrapper around that package.

| | SwiftPM + script | Xcode project |
|---|---|---|
| Command | `Scripts/build_app.sh` | `Scripts/build_xcode.sh` or Xcode ▸ Run |
| Needs | Swift toolchain (Xcode or Command Line Tools) | Full Xcode |
| Architectures | Native; `UNIVERSAL=1` for arm64 + x86_64 (needs full Xcode) | Debug: active arch. Release: universal |
| Bundle assembly | By the script (Info.plist substitution, icon, `codesign`) | By Xcode |
| Asset catalog | `AppIcon.icns` always; `Assets.car` when `actool` is available | Compiled by Xcode |
| Debugging / previews | No | Yes |

## Requirements

- macOS 14 or later to build and run. The deployment target is macOS 14.0.
- **Xcode 16.0 or later.** This is the oldest toolchain the CI builds with (Swift 6.0
  compiler in Swift 5 language mode). The package manifest declares tools version 5.9 and the
  project file uses a format Xcode 15 can read, but no Xcode 15 or macOS 14 CI runner exists,
  so older toolchains are not verified.
- The macOS 14.0 deployment target is checked at compile time only (availability checking).
  Running on macOS 14 is not verified by CI; see [PROGRESS.md](PROGRESS.md).
- No third-party dependencies; nothing is downloaded during the build.
- Linux (Swift 5.10 or 6.0) can build and test the portable modules only; see
  [TESTING.md](TESTING.md).

## Build without the Xcode project

```sh
Scripts/build_app.sh
open dist/MagicForge.app
```

What the script does:

1. `swift build -c release --product MagicForgeApp` (adds `--arch arm64 --arch x86_64` when
   `UNIVERSAL=1`).
2. Assembles `dist/MagicForge.app`:
   - `Contents/MacOS/MagicForge`: the built executable, renamed.
   - `Contents/Info.plist`: `Resources/Info.plist` with the `$(…)` build variables replaced.
   - `Contents/Resources/AppIcon.icns`, `Contents/PkgInfo`.
   - `Contents/Resources/Assets.car` if `xcrun actool` exists (accent colour); optional.
3. Signs it: `codesign --force --options runtime --entitlements
   Resources/MagicForge.entitlements --sign "${CODESIGN_IDENTITY:--}"`, then verifies the
   signature.

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `UNIVERSAL` | `0` | `1` builds arm64 + x86_64 |
| `CODESIGN_IDENTITY` | `-` | Signing identity; `-` is ad-hoc |
| `DIST_DIR` | `dist` | Output directory |
| `MF_VERSION`, `MF_BUILD_NUMBER` | from `Resources/Version.xcconfig` | Version stamp |
| `BINARY` | unset | Package an existing executable instead of building |

For day-to-day development you can also run the executable directly, without a bundle:
`swift run MagicForgeApp`. Without a bundle there is no Info.plist, so the app has no bundle
identifier, and permissions are attributed to the terminal that launched it. Use the bundle
for anything involving permissions.

## Build with Xcode

Open `MagicForge.xcodeproj`, select the **MagicForge** scheme and Run. From the command line:

```sh
Scripts/build_xcode.sh                       # Release → dist/MagicForge.app
CONFIGURATION=Debug Scripts/build_xcode.sh
```

which runs

```sh
xcodebuild -project MagicForge.xcodeproj -scheme MagicForge -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build
```

### How the project is put together

`MagicForge.xcodeproj` is **generated** by `Scripts/generate_xcodeproj.rb` and committed. Do
not edit it in Xcode and expect the change to survive; change
`Scripts/lib/project_spec.rb` or the generator and regenerate:

```sh
gem install xcodeproj
ruby Scripts/generate_xcodeproj.rb
ruby Scripts/verify_xcodeproj.rb
```

The generator output is deterministic, so regenerating without changes produces no diff. CI
fails if the committed project differs from the generator's output.

- One target: the macOS application **MagicForge** (`com.magicforge.app`).
- Its only compiled source is `Sources/AppMain/main.swift` (`import MFApp`, then
  `MagicForgeApp.main()`). Everything else comes from the local Swift package.
- The package is referenced as a local package at `.` (the project sits next to
  `Package.swift`) and the target links the package's `MFApp` library product. The package's
  own executable is named `MagicForgeApp`, so there is no name clash with the Xcode target.
- Resources: `Resources/Assets.xcassets` (AppIcon, AccentColor). Info.plist:
  `Resources/Info.plist` (`GENERATE_INFOPLIST_FILE = NO`). Entitlements:
  `Resources/MagicForge.entitlements`.
- Versions come from `Resources/Version.xcconfig`, the target's base configuration.
- A shared scheme, `MagicForge`, is committed so `xcodebuild -scheme MagicForge` works on CI.

Key build settings:

| Setting | Value | Why |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Observation framework, current SwiftUI |
| `SWIFT_VERSION` | `5.0` | Swift 5 language mode on every toolchain |
| `ARCHS` / `ONLY_ACTIVE_ARCH` | standard / `NO` in Release | Universal release builds |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization; good default |
| `ENABLE_APP_SANDBOX` | `NO` | See below |
| `CODE_SIGN_STYLE` / `CODE_SIGN_IDENTITY` | `Manual` / `-` | Ad-hoc: builds anywhere without a team |

### Why the App Sandbox is off

The sandbox forbids the things this app exists to do: session-wide event taps, posting
synthetic keyboard and mouse events, controlling other apps' windows through the
Accessibility API, and loading the private `MultitouchSupport.framework`. The entitlements
file therefore contains no `com.apple.security.app-sandbox` key. The hardened runtime stays
on, with a single entitlement: `com.apple.security.automation.apple-events` (AppleScript and
app-control actions).

`LSUIElement` is deliberately not set: MagicForge is a regular app with a Dock icon and a
main window, plus a menu-bar extra.

## Signing

The default is an ad-hoc signature (`-`). It needs no Apple account and works on any Mac and
on CI. Consequences:

- Gatekeeper blocks downloaded copies until the user overrides it (see the README).
- macOS ties privacy permissions (Accessibility and so on) to the code signature. An ad-hoc
  signature changes with every build, so permissions must be re-granted after each rebuild.
  Signing with any stable identity (a free "Apple Development" certificate is enough for
  local work) avoids that.

To sign with your own identity:

```sh
security find-identity -v -p codesigning        # list identities

# SwiftPM path
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" Scripts/build_app.sh

# Xcode path
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID \
  Scripts/build_xcode.sh
```

In the Xcode UI, override *Signing & Capabilities* locally (choose your team, or keep manual
signing and pick the identity). Do not commit that change; the committed project stays
ad-hoc. Distribution builds (Developer ID + notarization) are covered in
[RELEASE.md](RELEASE.md).

## DMG

```sh
Scripts/make_dmg.sh                    # dist/MagicForge.app → dist/MagicForge-<version>.dmg
Scripts/make_dmg.sh path/to/MagicForge.app
```

Creates a compressed (UDZO) image containing the app and an `/Applications` symlink.

## App icon

`Scripts/generate_icon.py` (Python 3 + Pillow) draws the icon and writes every size into
`Resources/Assets.xcassets/AppIcon.appiconset`, the `AccentColor` colour set and
`Resources/AppIcon.icns`. Run it again after changing the artwork;
`python3 Scripts/generate_icon.py --check` validates the files and pixel sizes.

## Continuous integration

`.github/workflows/magicforge.yml` (at the repository root; the package lives in
`MagicForge/`) runs on pushes to the development branch and on manual dispatch.

| Job | Runner | What it does |
|---|---|---|
| `linux-core` | `ubuntu-24.04`, `swift:6.0-noble` (and `swift:5.10-noble`, informational) | `swift build`, `swift test` of the portable modules |
| `project-lint` | `ubuntu-24.04` | `bash -n` + shellcheck, plist validation, icon check, regenerates and verifies the Xcode project |
| `macos` | `macos-15` (default Xcode), `macos-26` (default Xcode), `macos-15` with Xcode 16.0 | Full build, tests, probe, `xcodebuild`, app bundle, DMG, launch smoke test, idle measurement |

The macOS job is built to reveal as much as possible in one run:

- `swift build` output goes to a log; on failure the unique `error:` lines are printed and
  added to the job summary.
- If the build fails, each target is then built separately with
  `-Xswiftc -continue-building-after-errors`, so errors in independent modules all show up.
- Later steps (`swift test`, `xcodebuild`, packaging) still run when earlier ones fail.
- `mfprobe --self-check`, the universal SwiftPM build, and the launch smoke test with idle
  measurement are non-fatal; their outcome is listed in the job summary.
- Artifacts: the DMG, zipped app bundles (SwiftPM and Xcode builds), probe output, all logs
  and the idle measurement.

CI runners have no Magic Mouse and no granted privacy permissions, so CI can show that the
app builds, launches and stays alive, not that gestures work. Hardware verification is
manual; see [TESTING.md](TESTING.md).

## Build outputs

`dist/`, `dist-*/`, `build/`, `.build/`, `.build-*/` and `ci-artifacts/` are build products
and should not be committed.
