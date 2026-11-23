# Engine (MFEngine)

`AppModel` is the observable state the UI binds to and the coordinator of the whole pipeline.
It is portable (Foundation + Observation + Dispatch only) and is tested on Linux against mock
services: `MF_ONLY=MFEngine swift test --scratch-path .build-engine`.

## Files

| File | Contents |
|---|---|
| `AppModel.swift` | Observable state, internal state, `init`, accessors, activity log |
| `AppModel+Lifecycle.swift` | `start` / `stop` / `restartInput`, adapter and event-tap management, devices, permissions |
| `AppModel+Configuration.swift` | Loading, `update`, debounced saving, profile resolution, profiles, import / export, script trust, gesture availability and conflicts |
| `AppModel+Gestures.swift` | Main-actor handling of recognized gestures, metrics, synthetic input |
| `AppModel+Actions.swift` | `run`, action routing, radial menus, control actions |
| `AppModel+Workflows.swift` | Workflow runs and `EngineWorkflowEnvironment` |
| `AppModel+AI.swift` | API key, prompt runs, connection test |
| `AppModel+Diagnostics.swift` | Diagnostics JSON |
| `GesturePipeline.swift` | Input-thread side: recognizer, sequence matcher, binding lookup, scroll, chords, deadline timer |
| `MainHop.swift` | Hop to the main actor from foreign threads |

## Threading model

| Context | What runs there |
|---|---|
| Main actor | Every `AppModel` property and method, profile resolution, starting / stopping services, action routing |
| Pipeline queue (serial, `com.magicforge.engine.pipeline`) | `GestureEngine`, `SequenceMatcher`, the `ResolvedProfile` snapshot, the deadline timer, synthetic playback |
| Adapter thread | Calls `GesturePipeline.ingest`, which enters the pipeline queue with `sync`, so the frame is fully processed before `onFrame` returns |
| Event-tap thread | `PointerEventHandlers`. Scroll and chord decisions read one lock-protected snapshot and return at once; they never wait for the pipeline queue or the main actor |
| Swift concurrency | Leaf actions (inside the performer), the `WorkflowRunner` actor, AI requests |

Rules that follow from this:

- Observable state changes only on the main actor. The pipeline hands results over with
  `DispatchQueue.main.async` (FIFO, so gestures arrive in recognition order).
- The input threads never read the configuration. `applyActiveProfile()` pushes value
  snapshots: `PipelineSettings` (resolved profile, recognizer config with per-binding tuning,
  calibration of the connected device, enabled kinds) to the pipeline, and chords / scroll
  interception / hot keys to the event tap. `update` returns after the snapshot is applied.
- The main actor may `sync` onto the pipeline queue; the pipeline never waits for the main
  actor, so there is no lock order to get wrong.
- Long-lived closures capture `self` weakly (adapter `onFrame`, pointer handlers, device and
  frontmost-app observers, pipeline callbacks, timer handler, save task). A test checks that a
  stopped model is deallocated.
- Nothing polls. There is exactly one `DispatchSourceTimer`; it is re-armed after every frame
  and every firing from `min(recognizer.nextDeadline, matcher.nextDeadline)` and parked at
  `.distantFuture` when there is no deadline. After a firing the re-arm delay is at least 5 ms,
  so a deadline the recognizer keeps reporting as due cannot spin the queue.

## Data flow

1. **Frame.** Adapter → `ingest` → `GestureEngine.process` (timed with `MonotonicClock`) →
   `TouchFeed.push(_:live:processingTime:isSynthetic:)` → statistics → events.
2. **Sequences.** Every `GestureEvent` goes through `SequenceMatcher.feed`. `.single` resolves
   to the binding for that kind, `.sequence` to the binding for the sequence trigger. A single
   gesture that starts a registered sequence is therefore delayed by at most the sequence window
   (released by the same deadline timer).
3. **Binding.** The lookup uses the pipeline's `ResolvedProfile` snapshot, so the binding is
   the one in effect when the gesture was recognized. The result (`PipelineOutput`: event,
   binding or nil, profile name, synthetic flag, recognition time) hops to the main actor.
4. **Main actor.** `handleGesture` counts the gesture, calls `onGesture`, appends a
   `GestureRecord` (newest first, 50 at most, nothing when `keepRecentGestures` is off) and,
   unless gestures are paused or `suppressActions` is set, runs the action.
5. **Chords.** `onChord` answers from the tap snapshot: true only when the chord is part of an
   enabled binding of the effective profile and actions are live (not paused, not suppressed).
   The chord then takes the same path as a recognized gesture (matcher → binding → main actor).
6. **Buttons.** `onButton` → `GestureEngine.notePhysicalClick` on the pipeline queue.
7. **Scroll.** `onScroll` → one `ScrollTransformer` with the resolved profile's scroll settings,
   both inside the tap snapshot. The transformer is reset when the settings change and when the
   tap (re)starts. Scroll interception is only requested from the event source while the
   effective settings are enabled. Pausing gestures does not pause Smart Scroll.
8. **Hot keys.** Registered from `configuration.radialMenus`; `onHotKey` opens that menu.

`GestureRecord.actionName` is set only when an action was actually started (or skipped because
it was still running); a gesture that is unbound, paused or suppressed has `actionName == nil`.

While `suppressActions` is true the recognizer listens for every raw-contact gesture and the
event tap for every chord, bound or not, so Gesture Studio and calibration can observe any
gesture. Timing then follows the "everything enabled" conflict rules (for example a single tap
waits for the double-tap window).

## Input sources

- `start()` tries `Services.adapters` in order. An adapter is skipped when it uses private API
  and `allowPrivateMultitouch` is off (the status reason says it was turned off in Settings),
  or when `checkAvailability()` is not `.available`. A start failure (`noDevice`,
  `unavailable`, `startFailed`) becomes `adapterStatus.state == .unavailable(reason:)`.
- The attempt is repeated when the device monitor reports a connected device, on
  `restartInput()`, and when `allowPrivateMultitouch` changes. While an adapter is running,
  device changes are forwarded with `devicesDidChange()`.
- The event tap is started independently. When it cannot start (normally: no Accessibility),
  the activity log says so and `refreshPermissions()` retries once the permission is granted.
- `adapterStatus.capabilities` = the running adapter's raw-contact capabilities plus
  `pointerEvents` from the running tap. The profile is re-resolved against it, so bindings the
  input cannot deliver are not enabled in the recognizer or the tap.
- `availability(of: GestureKind)` gives the concrete reason: engine stopped, adapter reason,
  finger count above `maxContacts`, no event source in this build, Accessibility missing.
- `permissionRationale` is derived from the configuration: Accessibility only when chords,
  Smart Scroll, hot keys, event-posting actions or selected-text AI prompts are configured;
  Automation only when an AppleScript action exists; Input Monitoring always nil, because the
  input path uses the multitouch adapter and an active tap, never listen-only observation.

## Action routing

`run(_:source:)` never throws. `runTopLevel` routes the action and then counts and logs the
outcome exactly once; nested actions (workflow steps, radial menu items) are not counted again.

| Action | Route |
|---|---|
| `.none` | Success, not counted |
| leaf (`system`, `window`, `app`, `keyboard`, `mouse`, `text`, `script`) | Script trust check, then `Services.performer.perform` |
| `.workflow(id)` | Up-front trust check of everything reachable, then the single `WorkflowRunner`; tracked in `runningWorkflows` (progress from `onProgress`) |
| `.radialMenu(id)` | `Services.radialMenu.present(menu, recent:)`, then the chosen item's action; dismissing is a success; no presenter → `.unsupported` |
| `.ai(templateID)` | `runAITemplate`; `AIError` is mapped to `ActionError` (declined / cancelled → `.cancelled`) |
| `.control` | Pause toggle, open dashboard, next profile (cycles the override through enabled profiles), clear override, cancel workflows |

- Failures are appended to `activityLog` (newest first, 200 at most), counted in
  `metrics.actionFailures` and written to the `GestureRecord.failure` of the gesture that
  caused them. `.cancelled` is logged as information and is not a failure.
- A gesture whose binding is still executing is dropped (recorded as skipped), so a repeated
  gesture cannot stack executions of a slow action.
- Routing depth is limited to 6 (menu → item → menu …).
- Workflow outcomes: `completed` and `completedWithErrors` (continue-on-error) → success, the
  latter with a warning in the activity log; `failed` / `rejected` → the step's error;
  `cancelled` → `.cancelled`; `timedOut` → `.timedOut`. `stop()` cancels all runs.
- `EngineWorkflowEnvironment` answers workflow questions on the main actor from `Services`
  (live frontmost app, running apps, clipboard only for `clipboardContains`, notifications
  subject to `notificationsEnabled`) and sends `.radialMenu` / `.ai` / `.control` steps back
  through the model's router.

## Trust

- A script runs only when `ScriptTrust.isTrusted` says so at the moment of execution. The check
  is in `performLeaf` (direct, radial menu item, AI paste) and in the workflow runner (from a
  lock-protected copy of the approved hashes), and a workflow with any untrusted script
  reachable from it does not start at all.
- `update` cannot add approvals: hashes that were not approved before the mutation are
  removed again. Only `approve(_:)` and `applyImport(_:approveScripts: true)` add them.
  Editing a script changes its hash, so it is untrusted again.
- AI: nothing is captured or sent unless a prompt is triggered. Server, model and key are
  checked before any text is read. With `confirmBeforeSending` the presenter is shown exactly
  the prompt that will be sent; without a presenter the request is refused
  (`.declinedByUser`). An empty key is accepted only for `localhost` / `127.0.0.1` / `::1`.
  `testAIConnection` sends the fixed text "Reply with OK" and reads no user data; it requires
  AI to be enabled.

## Persistence

- `start()` loads synchronously. Nothing stored → defaults, written immediately.
- Load error → `persistenceError` is set. The store's backup is used when it offers one
  (`JSONConfigurationStore.loadBackup`), otherwise the defaults; nothing is written until the
  user changes something. `JSONConfigurationStore` has already moved the damaged file aside.
- File from a newer MagicForge (`unsupportedSchema`) → defaults, and saving is off for the
  session so that file is never downgraded; `persistenceError` explains it.
- `update` is synchronous: mutate → strip new approvals → `ConfigurationValidator.repair` →
  assign if changed → re-resolve and push snapshots → schedule a save 0.5 s later (cancellable
  task, restarted by each change). `saveNow()` and `stop()` flush. Save errors set
  `persistenceError` and are logged; the next successful save clears it.
- Changes made before the first `start()` are never written and are replaced by the stored
  configuration.
- Recent gestures, the activity log, metrics and the radial menu's recent items are memory only.

## Synthetic input

`playSynthetic` feeds the same pipeline with frames flagged synthetic (device 0). Frames are
re-timestamped onto the monotonic clock: with `realtime` they keep their spacing starting now
(scheduled on the pipeline queue, one pending item at a time); otherwise they are fed at once
with timestamps ending now, so pending deadlines are due immediately. Real touch frames are
ignored during playback. `isSyntheticInputActive` stays true until the last frame has been fed
and no recognizer / matcher deadline is pending (2 s at most), so a trailing single tap is
still attributed to the playback. `stopSynthetic` cancels at once.

## What is measured

All numbers are measurements; nothing is estimated.

| Metric | Definition |
|---|---|
| `framesProcessed` | Frames given to the recognizer (real and synthetic) |
| `averageProcessingTime`, `maxProcessingTime` | Wall time of `GestureEngine.process` per frame |
| `averageDeliveryLatency` | Arrival at the pipeline minus the frame's timestamp, real frames only |
| `gesturesRecognized` | Gestures (and completed sequences) that reached the main actor |
| `averageDispatchLatency` | Arrival of the completing frame / deadline / chord at the pipeline until the action is dispatched on the main actor; only gestures that dispatch an action |
| `actionsExecuted`, `actionFailures` | Top-level executions that succeeded / failed |

Frame counters live in the pipeline and are copied into the observable `metrics` on every
gesture and by a coalesced notification (at most about twice per second while frames arrive),
so 100 Hz input does not invalidate SwiftUI state.

## Diagnostics

`diagnosticsReport` is JSON: app and OS versions, engine flags, adapter status and reason,
capabilities, permissions, devices (model, transport, vendor / product id, battery; no name,
serial or identifier), metrics, counts, recent gesture kinds. With `includeTouchFrames` it adds
what the Touch Lab currently shows (`touchFeed.snapshot()`: latest frame and trails). No touch
history is recorded in the background.

## Limitations

- `ActionPerforming` has no hook for releasing a held drag, so the engine itself does not call
  `SystemActionPerformer.releaseHeldInput()`. The app's composition root (`Sources/App`) does it
  instead: when `isPaused` turns true and when the app terminates.
- Starting a workflow, opening a radial menu and cancelling workflows from synchronous API
  (`showRadialMenu`, `cancelAllWorkflows`) take effect on the next main-actor turn.
- macOS behaviour of the real adapter, event tap and performer is not exercised here; the
  engine is verified against mocks only.
