# Automation, Smart Scroll and AI

Portable code: `Sources/Automation` (MFAutomation), `Sources/Integrations` (MFIntegrations) and
the catalog in `Sources/Core/Catalog`. None of it touches the OS directly; everything goes through
injected protocols, so it builds and is tested on Linux.

## Workflows

A `Workflow` is an ordered list of `WorkflowStep`s run by the `WorkflowRunner` actor.

### Step semantics
- `action`: leaf actions (system, window, app, keyboard, mouse, text, script) go to
  `ActionPerforming.perform` with `ActionContext.source = .workflow`. `.radialMenu`, `.ai` and
  `.control` go to `WorkflowEnvironment.runRouted`. `.none` is a no-op that succeeds.
  `.workflow` is never executed.
- `delay`: sleeps through `WorkflowEnvironment.sleep`, cut short at the workflow deadline.
- `waitForApp`: checks the frontmost app, then re-checks every 0.1 s (sleeping in between, no
  busy loop). Fails the step with `ActionError.timedOut` when its own timeout passes.
- `conditional`: evaluates the condition once and runs one branch. The clipboard is read only
  for `clipboardContains` conditions.
- `notify`: `WorkflowEnvironment.notify`.

Steps run strictly in order. A failed step stops the workflow (`status == .failed`) unless
`continueOnError` is set, in which case the remaining steps run and the outcome is
`.completedWithErrors`. Cancellation and the workflow timeout always stop the run, regardless of
`continueOnError`.

`run` never throws. `WorkflowOutcome` holds the status, one `WorkflowStepResult` per started step,
the path of the first failed step, the first error and the duration. A step path is the list of
indices from the top level down; a step inside a conditional is the conditional's path plus its
index within the branch that ran. A conditional is recorded after its branch completes.

### Limits (`WorkflowLimits`)
| Limit | Value |
| --- | --- |
| Single delay | > 0 and ≤ 60 s |
| `waitForApp` timeout | > 0 and ≤ 120 s |
| Total steps (both branches of every conditional counted) | 200 |
| Nested conditionals | 4 levels |
| Workflow timeout | 1 … 600 s |
| Concurrent runs | 4, and one per workflow id |

`WorkflowValidator.issues(for:in:)` reports every violation as a sentence, plus references to
radial menus or AI prompts that no longer exist. `structuralIssues(for:)` is the subset that needs
no configuration; the runner rejects (`status == .rejected`, nothing executed) any workflow for
which it is not empty. Nested workflows are forbidden at any depth, which rules out loops. Extra
run requests are rejected, never queued.

### Timeout and cancellation
The deadline is checked on the environment's clock before every step and inside delays and
waits. A real-time watchdog additionally cancels the run when a single action is still running at
the timeout. Cancellation is cooperative: `cancel(runID:)`, `cancelAll()` and cancelling the task
that called `run` cancel the run's task, which interrupts sleeps and any performer that honours
Swift task cancellation. A performer that ignores cancellation delays the outcome until it
returns; no further step runs afterwards.

### Trust
Before a script action reaches the performer the runner calls `isScriptTrusted`. Untrusted scripts
fail with `ActionError.untrusted` and are never executed, also with `continueOnError`. The engine
supplies the predicate (hash of `ScriptAction.trustPayload` in `Configuration.approvedScriptHashes`).
`WorkflowValidator.scripts(in:)` lists a workflow's scripts for approval prompts.

## Smart Scroll (`ScrollTransformer`)

A deterministic value type. For each event it answers `passThrough` or `rewrite(deltaX:deltaY:)`.
It never drops an event and never asks for extra events, so phases, momentum and ordering stay as
the system produced them.

Pass-through when: Smart Scroll is disabled; `magicMouseOnly` and the event is not from a Magic
Mouse; the settings are an identity transform (multipliers 1, no inversion, acceleration 0, dead
zone 0, and smoothing 0 or a continuous event); the sample has non-finite numbers; or the result
equals the input.

Otherwise, with settings clamped (multipliers 0…20, acceleration and smoothing 0…1, dead zone
0…10; non-finite values fall back to the defaults):

    dt      = time since the previous event, clamped to 1/240 s … 0.1 s (1/60 s for the first event)
    speed   = 0.5 · previousSpeed + 0.5 · |delta| / dt        (first event: |delta| / dt)
    gain    = 1 + acceleration · 3 · speed / (speed + reference)
    factorX = horizontalMultiplier · (invertHorizontal ? −1 : 1) · gain
    factorY = verticalMultiplier   · (invertVertical   ? −1 : 1) · gain
    dx      = 0 when |dx| < horizontalDeadZone · |dy|
    out     = clamp(delta · factor, ±4000 px or ±200 lines)

`reference` is 1500 px/s for continuous deltas and 40 lines/s for line deltas. `gain` rises
monotonically with speed from 1 towards `1 + 3 · acceleration`, so acceleration never slows
scrolling and is always bounded. A pause longer than 0.25 s starts a new gesture.

Momentum events reuse the factors of the last finger-driven event of their gesture, so the glide
keeps the gesture's direction and scale even if settings change during it. Momentum with no
gesture on record uses the plain multipliers without acceleration.

Smoothing applies only to line-based deltas: `y[n] = (1 − β)·x[n] + β·y[n−1]`, `β = 0.8 · smoothing`.
The filter restarts when the input is zero or changes sign, so an isolated wheel notch is
unchanged and the output never points against its input.

## AI privacy model

- AI is off by default. `AIPromptBuilder.request` throws `AIError.disabled` before looking at
  anything else when it is off.
- Nothing is sent except by `OpenAICompatibleClient.complete`: one POST to
  `{baseURL}/chat/completions`, no retries, no background requests, no telemetry.
- The request body holds only the model name, the optional system prompt and the user prompt
  built by `AIPromptBuilder`. That user prompt is the text to show in the consent dialog, so what
  the user confirms is what is sent. Captured text over 12,000 characters is cut and marked.
- Only `https` is accepted, plus plain `http` to `localhost`, `127.0.0.1` and `::1`. URLs with
  embedded credentials or fragments are rejected. The base URL is used as given, with or without
  `/v1`.
- The API key is passed in per call, sent only as `Authorization: Bearer`, and stored only through
  `SecretStoring` (`KeychainSecretStore` on Apple platforms: generic password, readable after first
  unlock, this device only). An empty key omits the header for local servers.
- The default transport uses an ephemeral `URLSession` with no cache, cookies or credential
  storage. Prompts, responses and keys are never logged.
- Errors map to `AIError`: `http(status:message:)` with the server's message (at most 300
  characters), `timedOut` (overall deadline enforced by the client), `badResponse`, `cancelled`.
