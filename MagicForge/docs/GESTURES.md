# Gesture recognition (MFGestures)

Module `MFGestures` (`Sources/Gestures`) contains:

| Type | File | Purpose |
| --- | --- | --- |
| `GestureEngine` | `GestureEngine*.swift` | Deterministic recognizer (`GestureRecognizing`) |
| `SequenceMatcher` | `SequenceMatcher.swift` | Matches `GestureTrigger.sequence` over recognized events |
| `SyntheticTouch` | `SyntheticTouch*.swift` | Deterministic synthetic frame generator (tests, Touch Lab demo) |

The engine has no timers, threads or clock reads. Time comes only from `TouchFrame.timestamp`
and `advance(to:)`. `process()` is O(contacts) and allocates only when it emits an event.
Measured on the Linux build machine (debug build): about 6 µs per `process()` call at
3.4 contacts per frame (`PerformanceAndCorpusTests.testProcessTimePerFrame`).

## Why Magic Mouse is different

The whole shell is the touch surface and the hand grips it, so fingers rest on it, land and
lift all the time. The recognizer therefore reasons about **episodes of newly landed fingers**
and ignores everything else: resting fingers, palms, and contacts that survived a frame gap.

## Contact roles

Every tracked contact has one role:

- **candidate**: may join / is a member of the current episode.
- **resting**: ignored until it lifts. A contact becomes resting when
  - it stays within 3 mm of its anchor for `restingFingerDuration` (1.2 s); or
  - it is *flat* (size ≥ 1.8 × `calibration.typicalTapSize`, only when sizes are reported) and
    stays put for 0.25 s; or
  - another finger lands late while it is sitting still (see "Late fingers").
  Resting is permanent for that contact: a resting finger that later slides is still ignored.
- **palm**: size > `palmSizeThreshold` × (typicalTapSize / 0.6, clamped 0.5…2). Only evaluated
  when the reported size is non-zero. Sticky. A member that grows into a palm cancels its episode.
- **quarantined**: was on the surface across a frame gap; ignored until it lifts.

`liveState.activeFingerCount` counts episode members; `restingFingerCount` counts resting contacts.

## Episode state machine

```
idle ──finger lands──▶ tracking ──all still for holdMinDuration──▶ held
                          │  │                                      │
                          │  └─ swipe / pinch / rotate fires ──▶ fired ◀─ hold-then-swipe fires
                          │
                          └─ ambiguous / too slow / finger count changed / palm ──▶ cancelled
any state ── all members lifted or resting ──▶ idle   (tracking + tap criteria ⇒ tap)
```

`liveState.phase` strings: `idle`, `awaitingSecondTap`, `landing`, `tracking`, `held`,
`recognized`, `cancelled`.

- **Finger count**: fingers landing within `multiFingerLandingWindow` (90 ms) of the first
  finger form one episode; the count is the number that landed in the window. Nothing but a
  tap is decided before the window closes, except that a lift closes it early (so a flick
  shorter than 90 ms is still judged, at lift). More than three fingers cancel the episode.
- **Late fingers** (landing after the window): if the fingers already down are quiet (never
  moved more than `holdMaxMovementMM`, or have not left their anchor for 0.25 s) they are
  demoted to resting and the newcomer starts a fresh episode. That is how a tap is recognized
  next to fingers that have not yet been classified as resting. Otherwise the finger count
  changed mid-motion and the episode is cancelled (or stays `fired`).
- **A finger lifting early** from a multi-finger episode disables hold / swipe / pinch /
  rotate for that episode; only the tap check at the end remains.
- **Frame gap**: more than 100 ms between frames while contacts are tracked (or `advance(to:)`
  called more than 100 ms after the last frame while fingers are down) cancels the episode and
  quarantines the contacts. Nothing is emitted for the interrupted touch. A tap that had already
  completed and was waiting for a possible double tap is still released as a single tap.
  A timestamp going backwards or a different `deviceID` resets all state.
- Both end-of-contact styles are handled: a last sample with phase `.ended` / `.cancelled`, or
  the contact missing from the next frame. `.cancelled` cancels the episode.

## Gestures and thresholds

All distances are millimetres (`calibration.surface` converts normalized coordinates).
`y` grows toward the front of the mouse: "up" = toward the screen.

| Gesture | Rule |
| --- | --- |
| Tap (1–3 fingers) | Episode ends in `tracking`; duration (first landing → last lift) ≤ `tapMaxDuration` and ≥ 15 ms; no member moved more than `tapMaxMovementMM`; no physical click nearby |
| Double tap (1–2) | Second tap with the same finger count starts before `doubleTapWindow` after the first lift and within 12 mm of it |
| Corner / centre tap | One-finger tap whose landing point is in a `cornerZoneFraction` corner / the middle third of both axes |
| Hold (1–3) | No finger lifted, none moved more than `holdMaxMovementMM`, age ≥ `holdMinDuration`. Fires once, by `advance(to:)` at the deadline or by the next frame |
| Swipe (1–3) | Centroid travel ≥ `swipeMinDistanceMM`; at that moment deviation from the nearest axis ≤ `directionToleranceDegrees` and average speed since motion began ≥ `swipeMinVelocityMMPerSecond`; with several fingers each must travel ≥ 40 % of the centroid distance along the stroke. Fires immediately (not on lift), once per episode |
| Edge swipe | A one-finger swipe along the strip, when the contact never left the `edgeZoneFraction` strip. Left / right strips: vertical strokes (either direction); top (front) / bottom (rear): horizontal strokes |
| Pinch / rotate | See "Two-finger disambiguation" |
| Tap-then-swipe | A one-finger tap, then a one-finger swipe whose touch lands within `doubleTapWindow` and which fires within `sequenceWindow` of the tap's lift |
| Hold-then-swipe | After the episode reached `held`, a one-finger swipe measured from the hold position. The finger must start moving within `sequenceWindow` of the hold (or before it would rest) |

"Speed since motion began": the stroke clock restarts every frame the centroid is still within
1 mm of its origin (and, for two fingers, pinch change ≤ 1 mm and rotation ≤ 3°), so waiting
before a stroke does not lower its speed.

When the stroke reaches swipe length and fails direction or speed, the episode is cancelled:
a diagonal stroke that later straightens, or a slow drag that later speeds up, emits nothing.

After `held`, only hold-then-swipe is possible: a plain swipe, pinch or rotate never follows a
hold in the same episode (lift and start again).

### Two-finger disambiguation

Each frame three measures are normalized by their own thresholds:

- translation = centroid travel / `swipeMinDistanceMM`
- pinch = |change of finger separation| / `pinchMinChangeMM`
- rotation = |signed angle between the original and current finger-to-finger vector| / `rotationMinDegrees`
  (measured only when the fingers are ≥ 6 mm apart; positive = counterclockwise seen from above)

Nothing happens until the largest reaches 1.0. The largest then wins only if it is ≥ 1.25 ×
the runner-up; otherwise the episode is cancelled as ambiguous. Translation continues into the
swipe checks above. Pinch / rotate additionally require the threshold to be reached within
0.8 s of motion starting, and the less-moving finger to travel ≥ 20 % of the other's travel
(so "one finger rests, one scrolls" is not a pinch). Exactly one of swipe / pinch / rotate can
fire per episode.

## Conflict resolution (driven by `enabledKinds`)

`enabledKinds` defaults to every raw-contact kind. Disabled kinds are never emitted; they also
change timing:

- **Single vs double tap**: a tap is emitted on the lift frame unless a double tap with the same
  finger count is enabled, or (one finger) any tap-then-swipe is enabled. Then it becomes
  *pending* and `nextDeadline` = lift + `doubleTapWindow`; `advance(to:)` emits it.
  If a new touch lands inside the window the tap waits on that touch and is released as a single
  tap the moment the touch can no longer complete a double tap or tap-then-swipe (it moved, got
  too long, has a different finger count, became a hold, fired something else, was interrupted),
  always *before* any event of the new touch. Three-finger taps are never delayed.
- **Zone taps**: exactly one kind per physical tap, the most specific enabled one:
  corner → centre → plain `oneFingerTap`. A double tap inside a zone is a `oneFingerDoubleTap`.
- **Tap-then-swipe** consumes the tap: only the compound event is emitted. If the swipe direction
  has no enabled tap-then-swipe kind, the tap is released and the stroke is an ordinary swipe.
- **Hold-then-swipe** follows a hold; with `oneFingerHold` enabled both events are emitted
  (hold, then the compound). It works with `oneFingerHold` disabled.
- **Edge vs plain one-finger swipe**: the edge kind wins when the stroke stayed in the strip and
  the edge kind is enabled; otherwise the plain kind is used.
- **Physical clicks** (`notePhysicalClick`): a tap or hold is suppressed when a click falls
  within `physicalClickSuppression` of the touch (before, during or after), and a pending tap
  whose lift is no older than that is retracted. A tap already emitted cannot be recalled, so
  the host should deliver the click note as soon as the button event arrives.
- **Cooldown**: an event is dropped when the same kind was emitted less than `cooldown` ago.
- **Debounce**: contacts shorter than 15 ms (single-frame blips) are never taps.

`nextDeadline` is the earliest of: the pending tap's release time (only if it would emit) and
the hold deadline (only if that hold kind is enabled and still possible).

## Sensitivity mapping

```
effective = clamp(tuning.sensitivity × globalSensitivity / 0.5, 0…1)
factor    = 2^(1 − 2 × effective)          // 0 → 2.0, 0.5 → 1.0, 1 → 0.5
```

- Multiplied by `factor` ("must exceed"): `swipeMinDistanceMM`, `swipeMinVelocityMMPerSecond`,
  `pinchMinChangeMM`, `rotationMinDegrees`.
- Divided by `factor` ("must stay below"): `tapMaxMovementMM`, `holdMaxMovementMM`,
  `directionToleranceDegrees` (clamped to 44°).
- Durations are never scaled by sensitivity. `GestureTuning.duration` replaces `tapMaxDuration`
  for tap kinds and `holdMinDuration` for hold kinds. The hold duration is never less than the
  tap limit + 30 ms.

The tuning used is that of the candidate kind (e.g. the swipe kind for the current direction,
the resolved zone kind for a tap). Hold-then-swipe uses `oneFingerHold`'s tuning for its hold part.

Calibration scaling (ratio to the factory default, clamped): `typicalTapMovementMM` scales the
tap and hold movement limits (0.5…2), `typicalSwipeDistanceMM` scales the swipe distance
(0.5…2), `typicalTapDuration` scales the tap duration limit (0.75…2), `typicalTapSize` scales
the palm and flat-contact size limits (0.5…2).

## Confidence

```
confidence = 0.5 + 0.5 × Σ(weight × comfort)     weights sum to 1, comfort in 0…1
below(v, limit) = clamp(1 − v / limit)           above(v, min) = clamp(v / min − 1)
```

| Gesture | Terms |
| --- | --- |
| Tap | 0.45 below(movement) + 0.30 below(duration) + 0.25 below(landing spread, landing window) |
| Hold | 0.75 below(movement) + 0.25 below(landing spread) |
| Swipe | 0.40 below(direction deviation, tolerance) + 0.30 above(speed) + 0.20 straightness (distance / path, 0.7…1 → 0…1) + 0.10 finger coherence |
| Pinch / rotate | 0.60 (1 − runner-up / winner) + 0.40 below(stroke time, 0.8 s) |
| Double tap | mean(tap 1, tap 2) × (0.8 + 0.2 × mean(below(gap, window), below(distance, 12 mm))) |
| Tap-then-swipe, hold-then-swipe | mean of the two parts |

A gesture that only just clears every threshold scores 0.5; events below
`minimumConfidence` (default 0.6) are dropped.

## SequenceMatcher

Feed every recognized `GestureEvent`; each comes back exactly once, as `.single(event)` (run the
single binding) or inside `.sequence(kinds, completedBy:)`.

- Sequences have 2…4 kinds. Events are held while they are a prefix of some sequence.
- Longest match wins: a completed sequence that is a prefix of a longer one is deferred until
  the next event or the window (`sequenceWindow` after the last held event) decides.
- On a mismatch or timeout the held events are resolved front to back (longest complete
  sequence, else the first event as `.single`).
- `delaysSingle(kind)` tells the host that a single binding for `kind` is delayed by up to the
  window because the kind starts a sequence; `nextDeadline` / `advance(to:)` release held events.

## SyntheticTouch

`frames(for:startTime:surface:frameInterval:)` produces a canonical stream for each raw-contact
kind (empty for fallback kinds); `paths(for:)` exposes the contact paths so building blocks can
be added before `render`. Building blocks: `tapPath`, `linePath`, `holdPath`, `holdThenLinePath`,
`arcPath`, `restingPath`, `palmPath`, `slowDriftPath`, `physicalClickTouch`, `droppingFrames`
(interruption), `scrollPaths(seed:)`, `noisePaths(seed:)`, and the `LCG` generator. Everything
is deterministic.

## Known limitations

- **A small, still fingertip is a hold.** A finger that lands and stays still for
  `holdMinDuration` is indistinguishable from a deliberate hold unless the adapter reports
  contact size (flat contacts never hold). On the synthetic noise corpus: 0 false activations
  in 600 s with sizes, 29 (all holds) with sizes zeroed. If the adapter has no size data the
  hold kinds should be offered with a warning or a longer duration.
- Movement slower than `holdMaxMovementMM / holdMinDuration` (6 mm/s by default) counts as
  holding still.
- A brief, still touch is a tap. A grip finger that touches for under `tapMaxDuration` cannot be
  told from a tap.
- The flat-contact factor (1.8 × typical tap size) and all other internal constants in
  `EngineConstants.swift` are engineering estimates. They have not been validated against real
  Magic Mouse data; only synthetic streams were available on the build machine.
- Fingers that land more than `multiFingerLandingWindow` apart are not one multi-finger gesture.
- With a double tap or tap-then-swipe enabled, single taps (including zone taps) are delayed by
  `doubleTapWindow`.
- A resting finger must lift and land again before it can gesture. Pivot pinches (one finger
  fixed) are rejected. No swipe, pinch or rotate after a hold in the same touch.
- Edge swipes do not report their direction along the edge.
- A tap emitted before its physical click is reported cannot be retracted.
