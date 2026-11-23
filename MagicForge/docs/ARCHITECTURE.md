# Architecture

MagicForge is one Swift package (`Package.swift`) split into small modules with a strict
dependency direction: platform-specific code at the edges, portable logic in the middle, and
a set of protocols (the *contract*) between them.

## Module map

| Module | Directory | Platform | Responsibility |
|---|---|---|---|
| MFUtilities | `Sources/Utilities` | portable | `Log`, monotonic clock, lock wrapper |
| MFCore | `Sources/Core` | portable | The contract: model types (`TouchFrame`, `GestureKind`, `Action`, `Configuration`, …), service protocols (`Services.swift`), `TouchFeed`, the gesture and action catalogue (`Catalog/`) |
| MFGestures | `Sources/Gestures` | portable | `GestureEngine` (recognition), `SequenceMatcher`, `SyntheticTouch` |
| MFProfiles | `Sources/Profiles` | portable | `JSONConfigurationStore`, defaults, `ConfigurationValidator`, `ProfileResolver`, `ConflictDetector`, `ProfileTransfer` (import/export), `ScriptTrust` |
| MFAutomation | `Sources/Automation` | portable | `WorkflowRunner`, `WorkflowValidator`, `ScrollTransformer` |
| MFIntegrations | `Sources/Integrations` | portable (Keychain: Apple only) | `OpenAICompatibleClient`, `KeychainSecretStore`, `InMemorySecretStore` |
| MFEngine | `Sources/Engine` | portable | `AppModel`: observable state for the UI and the coordinator of the whole pipeline |
| MFDevices | `Sources/Devices` | macOS | `HIDDeviceMonitor`: Magic Mouse connect/disconnect and device info (IOKit HID) |
| MFInput | `Sources/Input` | macOS | `MultitouchSupportAdapter` (raw touch frames, private framework), `EventTapPointerSource` (CGEventTap) |
| MFActions | `Sources/Actions` | macOS | `SystemActionPerformer`, `SystemPermissions`, frontmost-app, pasteboard and notification services |
| MFUI | `Sources/UI` | macOS | SwiftUI screens, design system, radial menu and AI presenters |
| MFApp | `Sources/App` | macOS | App shell: builds the `Services`, owns the `AppModel`, windows and menu-bar extra |
| MagicForgeApp | `Sources/AppMain` | macOS | `main.swift`: `MagicForgeApp.main()`. Also the only source of the Xcode app target |
| mfprobe | `Sources/Probe` | macOS | Command-line diagnostics using MFDevices + MFInput + MFGestures |

"Portable" modules use Foundation only and build and test on Linux as well as macOS. On Linux
the macOS-only modules are simply not part of the package.

```
                                 ┌───────────────────────────┐
                                 │  MagicForgeApp (main)     │
                                 │  MFApp  (composition root)│
                                 └─────┬───────────────┬─────┘
                 builds Services       │               │   shows
        ┌──────────────┬───────────────┤               ▼
        ▼              ▼               ▼          ┌─────────┐
   ┌──────────┐  ┌──────────┐   ┌───────────┐     │  MFUI   │  SwiftUI, reads AppModel,
   │MFDevices │  │ MFInput  │   │ MFActions │     └────┬────┘  writes via model.update
   │ IOKit HID│  │ private  │   │ CGEvent,  │          │
   │          │  │ MT + tap │   │ AX, NSWs  │          │
   └────┬─────┘  └────┬─────┘   └─────┬─────┘          │
        │ implement protocols from MFCore              │
        └──────────────┴───────┬───────┘               │
                               ▼                       ▼
                        ┌─────────────────────────────────┐
                        │        MFEngine (AppModel)      │
                        └──┬─────────┬──────────┬───────┬─┘
                           ▼         ▼          ▼       ▼
                     MFGestures  MFProfiles  MFAutomation  MFIntegrations
                           └─────────┴────┬─────┴───────┘
                                          ▼
                                   MFCore ─► MFUtilities
```

Rules that keep this shape:

- MFEngine and everything below it never import AppKit, IOKit, CoreGraphics or the private
  framework. They see the outside world only through the protocols in
  `Sources/Core/Services.swift`.
- The macOS modules MFDevices, MFInput and MFActions depend only on MFCore and MFUtilities.
  They do not know about each other, the engine or the UI.
- MFUI depends on the engine and the portable modules, not on MFInput or MFActions. Screens
  cannot reach a device or post an event directly.
- MFApp is the only place where concrete implementations are named and wired into a
  `Services` value.

## Data flow

```
 Magic Mouse
     │
     ├── touch surface ──► MultitouchSupport.framework (private) ──► MultitouchSupportAdapter
     │                                                                   │ TouchFrame
     │                                                                   ▼
     │                                                         GestureEngine (MFGestures)
     │                                                                   │ GestureEvent
     │                                                                   │
     └── buttons / scroll ──► CGEventTap ──► EventTapPointerSource       │
                                   │  chord / hot key / scroll sample    │
                                   ▼                                     ▼
                           ┌────────────────────────────────────────────────┐
                           │ AppModel (MFEngine)                            │
                           │  1. frontmost app ─► ProfileResolver           │
                           │  2. active profile + inherited global bindings │
                           │  3. trigger ─► GestureBinding ─► Action        │
                           │  4. availability, pause, suppressActions       │
                           │  5. ScriptTrust check for script actions       │
                           └───────────────┬────────────────────────────────┘
                                           │ Action
                 ┌─────────────────────────┼──────────────────────────────┐
                 ▼                         ▼                              ▼
        ActionPerforming          WorkflowRunner                 presenters
        (SystemActionPerformer:   (steps, delays,                (radial menu,
         keys, windows, apps,      conditions; each leaf          AI interaction)
         media, text, scripts)     goes back through 4 and 5)
```

1. **Input.** `HIDDeviceMonitor` reports connected Magic Mice. The engine picks the first
   available `TouchInputAdapter` from `Services.adapters` and starts it. The adapter converts
   the framework's contact records into `TouchFrame` values (normalised contacts with phase
   and timestamp) and calls `onFrame`. Separately, `EventTapPointerSource` observes buttons,
   scroll events and hot keys through a `CGEventTap`.
2. **Recognition.** `GestureEngine` consumes frames and emits `GestureEvent`s according to
   the `RecognizerConfig` and per-device `DeviceCalibration`. The event tap detects fallback
   chords itself and reports them as `GestureKind`s of the fallback category.
   `SequenceMatcher` matches multi-gesture sequences.
3. **Profile resolution.** `ProfileResolver` chooses the active profile from the frontmost
   app's bundle identifier or the manual override, falling back to the global profile. The
   effective bindings are the active profile's plus the inherited global ones.
4. **Action.** The matching binding's `Action` runs through `AppModel.run`: leaf actions go
   to the `ActionPerforming` service; workflows go to `WorkflowRunner`; radial-menu and AI
   actions go to their presenters. Failures are returned as `ActionError`, recorded in the
   activity log, and never thrown across the pipeline.
5. **Scrolling.** For Smart Scroll the tap passes each scroll event to the engine as a
   `ScrollSample`; `ScrollTransformer` decides to pass it, drop it or rewrite its deltas in
   place. No extra events are posted.

The same pipeline is used for synthetic input: `AppModel.playSynthetic` feeds generated
frames into step 2, flagged as synthetic all the way to the UI.

## State and configuration

- `AppModel` is the single source of truth. It is `@MainActor` and `@Observable`; the UI
  reads its properties and never keeps its own copy of the configuration.
- Every configuration change goes through `AppModel.update { config in … }`, which mutates,
  validates and repairs (`ConfigurationValidator`), re-applies the result to the running
  pipeline and schedules a debounced save through `ConfigurationStoring`.
- Configuration is one JSON document in `~/Library/Application Support/MagicForge/`. Secrets
  are not part of it; the AI key lives in the Keychain behind `SecretStoring`.
- Live touch data does not go through observable state. `TouchFeed` is a lock-protected
  buffer that the Touch Lab polls once per display frame, so high-rate touch input does not
  invalidate SwiftUI views.

## Threading model

| Context | What runs there | Rule |
|---|---|---|
| Adapter thread (owned by the touch adapter) | Frame conversion, `onFrame`, recognition, `TouchFeed` updates | No UI, no blocking, no allocation-heavy work; frames arrive in timestamp order |
| Event-tap thread | `PointerEventHandlers` callbacks (button, scroll, chord, hot key) | Synchronous and fast: the system disables taps that respond too slowly; the scroll decision is computed inline |
| Main actor | `AppModel` state, profile resolution, UI, starting and stopping services, device callbacks | The only place observable state changes |
| Swift concurrency tasks | Action execution, workflows (delays, cancellation), script processes, AI requests | Cancellable; results return to the main actor |

Recognised gestures hop from the adapter thread to the main actor before bindings are
resolved, so configuration is only ever read on the main actor. State shared with the input
threads (recogniser configuration, enabled chords, scroll settings) is pushed to them as
value snapshots when configuration changes, not read through shared mutable references.
Types that cross threads are `Sendable` values or lock-protected classes (`Locked`,
`TouchFeed`).

## Trust model

MagicForge can type keys, move windows and run scripts, so the design treats its own
configuration as a potential attack surface.

- **Scripts are approved by content.** AppleScript, shell and Shortcut actions run only when
  the hash of the exact action is in `Configuration.approvedScriptHashes` (`ScriptTrust`).
  Editing a script changes its hash and removes its approval.
- **Imports are untrusted.** `ProfileTransfer` produces an `ImportPreview` first; applying
  it never approves the scripts it contains unless the user explicitly chooses to. Exported
  files do not contain secrets.
- **Validation at the boundary.** Loaded and imported configuration passes through
  `ConfigurationValidator`, which repairs or rejects malformed values (numeric limits,
  dangling references, workflow nesting) before the engine sees it.
- **Permissions are observed, not assumed.** `PermissionsProviding` reports the state
  without prompting; actions whose permission is missing are reported as unavailable with a
  reason instead of failing silently.
- **AI is opt-in and user-triggered.** Nothing is sent unless AI is enabled and the user
  runs an AI action; the request contains only the chosen text and prompt. The key never
  leaves the Keychain except in the request to the configured endpoint.
- **Logging discipline.** `Log` never receives touch coordinates, clipboard contents, typed
  text or script bodies.
- **Process hardening.** Hardened runtime on; one entitlement (Apple events); no sandbox
  (see [LIMITATIONS.md](LIMITATIONS.md)); no helper tools, no privileged components, no
  network listeners.

## Why the private API is isolated

Per-finger positions on a Magic Mouse are available only through Apple's private
`MultitouchSupport.framework`. Public APIs deliver the mouse's output (pointer movement,
buttons, scroll events), not the contacts. That dependency is the project's main risk, so it
is confined:

- It lives in one module, MFInput, behind the `TouchInputAdapter` protocol
  (`usesPrivateAPI == true`). Nothing else references the framework.
- The framework is not linked. It is opened with `dlopen` and each function is resolved with
  `dlsym` at runtime, so the app launches even if the framework or a symbol is missing, and
  `checkAvailability()` can report exactly what failed.
- The engine takes a list of adapters and uses the first available one. If none is
  available, `AdapterStatus.state` is `.unavailable(reason:)`, gestures that need raw
  contacts report `GestureAvailability.unavailable`, and only fallback triggers (public
  event tap) are offered.
- Because the contract is a protocol, the recogniser, engine and UI are developed and tested
  against synthetic frames and mocks, on Linux as well; a different adapter could be added
  without touching them.

What has actually been observed on which hardware and macOS version is in
[FEASIBILITY.md](FEASIBILITY.md) and [COMPATIBILITY.md](COMPATIBILITY.md).

## Packaging

The Xcode project contains a single app target that compiles `Sources/AppMain/main.swift`
and links the package's `MFApp` product; the SwiftPM executable `MagicForgeApp` is the same
entry point. Both routes produce the same app. See [BUILD.md](BUILD.md).
