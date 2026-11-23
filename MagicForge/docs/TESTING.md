# Testing MagicForge

Testing has three layers. Only the first runs automatically.

| Layer | Runs where | Covers |
|---|---|---|
| Unit tests of the portable modules | macOS and Linux, CI | Recognition, profiles, workflows, integrations, engine wiring |
| Build, launch and probe on CI | macOS runners (no Magic Mouse, no permissions) | Everything compiles, the app starts and stays up, the probe runs |
| Manual hardware tests | A Mac with a Magic Mouse | Real touch input, permissions, actions against real apps |

Results are recorded in [PROGRESS.md](PROGRESS.md). This document describes how to test, not
what passed.

## Unit tests

```sh
Scripts/test.sh                          # swift test (whole package)
Scripts/test.sh -- --filter GestureTests # pass arguments through to swift test
Scripts/test.sh --per-module             # each portable module in isolation
Scripts/test.sh --module MFGestures      # one module in isolation
```

Test targets and what they exercise:

| Test target | Module | Subject |
|---|---|---|
| `ActionTests` | MFCore | Action model and catalogue |
| `GestureTests` | MFGestures | Gesture recognition, sequences, synthetic touch generator |
| `ProfileTests` | MFProfiles | Storage, validation, profile resolution, conflicts, import/export, script trust |
| `AutomationTests` | MFAutomation | Workflow runner and validator, scroll transformer |
| `IntegrationTests` | MFIntegrations | AI client, secret stores |
| `EngineTests` | MFEngine | The pipeline from touch frames to executed actions, using mocks |

### Linux

The portable modules (MFUtilities, MFCore, MFGestures, MFProfiles, MFAutomation,
MFIntegrations, MFEngine) use Foundation only and build on Linux, which makes the logic
testable without a Mac:

```sh
swift test                                # all portable modules
MF_ONLY=MFGestures swift test --scratch-path .build-only/MFGestures
```

`MF_ONLY=<Module>` (see the top of `Package.swift`) reduces the package to MFUtilities,
MFCore, that module (plus its dependencies for MFEngine) and its tests. It exists so one
module can be built and tested while another does not compile. Use a separate
`--scratch-path` per value, because changing `MF_ONLY` changes the package graph;
`Scripts/test.sh --per-module` does this for you. The macOS-only modules (MFDevices, MFInput,
MFActions, MFUI, MFApp, mfprobe) are not part of the package on Linux.

### Mocks

The engine depends only on the service protocols in `Sources/Core/Services.swift`
(`TouchInputAdapter`, `DeviceMonitoring`, `PointerEventSource`, `PermissionsProviding`,
`ActionPerforming`, `ConfigurationStoring`, `SecretStoring`, `AICompleting`, …) bundled in
the `Services` struct. Tests construct an `AppModel` with in-memory implementations of those
protocols, feed it touch frames, and assert on which actions the mock performer received. No
test touches real devices, the event system, the Keychain or the network.

### Synthetic touch generator

`SyntheticTouch` (MFGestures) produces deterministic `TouchFrame` sequences:

- `SyntheticTouch.frames(for:startTime:surface:frameInterval:)`: the frames of one gesture.
- `SyntheticTouch.demoReel(startTime:)`: a sequence of several gestures.

The recognition tests use it as input. The app uses the same generator in the Touch Lab
("test input"), played through the real recognition pipeline via `AppModel.playSynthetic`.
Synthetic frames are flagged as synthetic end to end and shown as such; they demonstrate the
recogniser, not the hardware path.

Synthetic input is modelled on the documented surface geometry, not recorded from a device.
Passing tests therefore say the recogniser is self-consistent; whether real contact data
looks like the model is a hardware question (below).

## What CI checks on macOS

See [BUILD.md](BUILD.md#continuous-integration). In short: debug build of every target,
`swift test`, `mfprobe --self-check`, a Release `xcodebuild`, the SwiftPM app bundle and DMG,
a launch smoke test (the process must still be alive after about 10 seconds, with stderr and
the unified log captured), and a short idle measurement.

CI runners have no Magic Mouse and no Accessibility permission. On CI the app is expected to
report raw touch input and the event tap as unavailable; that exercises the degraded paths,
nothing more.

## The probe (`mfprobe`)

`mfprobe` is a command-line tool built from `Sources/Probe`. It uses the same device monitor
(MFDevices) and touch adapter (MFInput) as the app, without any UI, to answer "what does this
Mac and this mouse actually provide?".

```sh
Scripts/run_probe.sh --self-check    # non-interactive checks; used by CI
Scripts/run_probe.sh --help          # all options
```

`--self-check` needs no hardware and no permissions: it reports what it finds (devices,
whether the private framework and its symbols load, adapter availability) and exits. Run it
first on any new Mac or macOS version, and attach its output to bug reports. Other modes
that stream live data are listed by `--help`; when run from a terminal, permissions are
attributed to the terminal app.

Probe output from real hardware is the evidence behind
[FEASIBILITY.md](FEASIBILITY.md) and [COMPATIBILITY.md](COMPATIBILITY.md).

## Measuring idle cost

```sh
Scripts/build_app.sh
Scripts/measure_idle.sh --duration 120 --output idle.txt   # launches the app, samples, quits it
Scripts/measure_idle.sh --pid <pid>                        # attach to a running instance
```

The script samples CPU % and resident memory with `ps`, and on macOS also per-interval CPU
and idle wake-ups with `top -l`, then prints averages and maxima. It reports only what it
measured; there are no built-in reference numbers. For a meaningful baseline, grant
permissions first, connect the mouse, wait for the app to settle, and do not touch the mouse
or keyboard during sampling. Record results, with hardware and macOS version, in
[PROGRESS.md](PROGRESS.md).

## Manual hardware checklist

Use a signed app bundle (not `swift run`), note the Mac model, macOS version, mouse model and
connection type, and record each result in [PROGRESS.md](PROGRESS.md) as pass, fail or not
tested. Do not mark anything as working that you did not observe.

Setup
- [ ] `Scripts/run_probe.sh --self-check` output saved.
- [ ] App launches; Dock icon, main window and menu-bar item appear.
- [ ] Permissions screen shows the true state of each permission before and after granting.
- [ ] After granting Accessibility, input restarts without relaunching (or the app says a
      relaunch is needed).

Device
- [ ] The mouse appears on the Devices screen with the right model and connection type.
- [ ] Battery level is shown, or shown as unavailable; never a made-up value.
- [ ] Turning the mouse off and on, and Bluetooth off and on, is reflected; input resumes.
- [ ] Sleep and wake: input resumes without relaunching.

Raw touch input
- [ ] Dashboard and Devices screens state whether raw touch input is available and name the
      adapter; if unavailable, the reason is shown and only fallback triggers are offered.
- [ ] Touch Lab shows live contacts that track one, two and three fingers.
- [ ] Reported frame rate and latency in the Touch Lab are plausible and stable.
- [ ] Touch Lab clearly labels synthetic input when test input is playing.

Gestures (for each gesture in [GESTURES.md](GESTURES.md))
- [ ] Recognised when performed deliberately (10 attempts; note the count).
- [ ] Not triggered by ordinary pointing, clicking and scrolling (5 minutes of normal use).
- [ ] Calibration changes the behaviour it claims to change.
- [ ] Gestures that overlap system gestures behave as documented in
      [LIMITATIONS.md](LIMITATIONS.md).

Fallback triggers and scrolling
- [ ] Each fallback chord fires its action and the originating click is not delivered twice.
- [ ] Normal clicks, drags and scrolling are unaffected when no binding matches.
- [ ] Smart Scroll settings change scrolling as described; turning them off restores default
      behaviour.
- [ ] Pausing gestures from the menu bar stops all triggers; resuming restores them.

Actions
- [ ] One action from each category (system, window, app, keyboard, mouse, text, script,
      workflow, radial menu, control) does what its label says.
- [ ] An unapproved script does not run and the app asks for approval; an edited script
      needs approval again.
- [ ] AppleScript actions trigger the Automation prompt for the target app; denying it
      produces a clear error, not a silent failure.
- [ ] Radial menu opens at the pointer, selects by direction, dismisses with Escape.
- [ ] A running workflow can be cancelled.

Profiles
- [ ] Switching to an app with its own profile switches the active profile; switching away
      restores the global one.
- [ ] Manual profile override works and can be cleared.
- [ ] Export, then import on a clean configuration: bindings are restored, scripts arrive
      untrusted, no secrets are in the exported file.
- [ ] Conflicting bindings are reported.

AI (only if you use it)
- [ ] With AI off, no network connection is made (check with a network monitor).
- [ ] The connection test reports a wrong key or endpoint clearly.
- [ ] The API key is in the Keychain and not in the configuration file or exports.

Robustness
- [ ] Quit and relaunch: configuration is preserved.
- [ ] A corrupted configuration file is reported and does not crash the app.
- [ ] Revoking Accessibility while running is detected and reported.
- [ ] `Scripts/measure_idle.sh` result recorded.
- [ ] A diagnostics export contains no touch coordinates unless requested.
