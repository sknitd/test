# Profiles, persistence and import / export (MFProfiles)

Everything here is portable Foundation code in `Sources/Profiles` (module `MFProfiles`), tested on
Linux by `Tests/ProfileTests`:

    MF_ONLY=MFProfiles swift test --scratch-path .build-profiles

## Where things are stored

`JSONConfigurationStore.defaultDirectory`:

| Platform | Directory |
| --- | --- |
| macOS | `~/Library/Application Support/MagicForge` |
| elsewhere | `$XDG_CONFIG_HOME/MagicForge`, default `~/.config/MagicForge` |

| File | Purpose |
| --- | --- |
| `configuration.json` | The whole `Configuration`: pretty-printed, keys sorted, owner-only (0600). |
| `configuration.backup.json` | The previous *readable* `configuration.json`. One rolling copy, refreshed on every save. An unreadable file never replaces it. |
| `configuration.corrupt-<yyyyMMdd-HHmmss>[-n].json` | A file `load()` could not read, moved aside untouched (UTC timestamp). |

Writes are atomic (temporary file in the same folder, then rename) and the store is safe to use
from several threads. The AI API key is never in these files; it lives in the Keychain.

### Loading rules

- No file: `load()` returns `nil` (the app then starts from `DefaultConfiguration.make()`).
- `schemaVersion` greater than `Configuration.currentSchemaVersion`: throws
  `ConfigurationError.unsupportedSchema(version)`. The file is left exactly as it is.
- Not JSON, not an object, or a value of the wrong type: the file is moved aside as
  `configuration.corrupt-…json` and `ConfigurationError.unreadable` is thrown. `loadBackup()`
  returns the previous good version when there is one.
- Missing fields are fine (see below). The loaded value has always been through
  `ConfigurationValidator.repair`.

### Lenient decoding

The model types in `MFCore` use synthesized `Codable`, which rejects any missing key. Files are
therefore decoded in three steps (`ConfigurationJSON`, `LenientFiller`):

1. parse into a plain JSON object;
2. lay it over the JSON of a default value, struct by struct — configuration, settings, AI
   settings, recognizer (and each tuning entry), calibrations (and their surface), each profile,
   binding, scroll settings, workflow, radial menu, theme, hot key, menu item (recursively) and AI
   prompt. Absent or `null` fields take the default; a missing `id` gets a fresh UUID;
3. decode the completed object with `JSONDecoder`.

Limits: enum payloads (`trigger`, `action`, workflow `steps`) are not completed and must be
whole; a binding without a `trigger` is skipped; unknown keys are ignored and are dropped on the
next save.

## JSON format

`configuration.json` is `Configuration` as Swift encodes it. Enums with payloads appear as
`{"caseName": {…}}` with unlabelled payloads named `_0`, `_1`:

```json
{
  "schemaVersion": 1,
  "globalProfileID": "…",
  "profiles": [{
    "id": "…", "name": "Finder", "symbolName": "folder",
    "bundleIdentifiers": ["com.apple.finder"], "isEnabled": true, "inheritsGlobal": true,
    "bindings": [{
      "id": "…", "isEnabled": true, "sensitivity": 0.5, "priority": 0, "note": "Quick Look",
      "trigger": {"single": {"_0": "threeFingerTap"}},
      "action": {"keyboard": {"_0": {"keyCode": 49, "command": false, "option": false,
                                     "control": false, "shift": false, "function": false, "label": "Space"}}}
    }]
  }],
  "workflows": [], "radialMenus": [],
  "ai": {"isEnabled": false, "templates": []},
  "settings": {}, "recognizer": {}, "calibrations": {}, "approvedScriptHashes": []
}
```

A sequence trigger is `{"sequence": {"_0": ["twoFingerTap", "pinchIn"]}}`; references are
`{"workflow": {"id": "…"}}`, `{"radialMenu": {"id": "…"}}`, `{"ai": {"templateID": "…"}}`; a
payload-free case is `{"none": {}}`. Dates are seconds since 2001-01-01 (Foundation's default).

### Export envelopes

Profile export (`ProfileTransfer.exportProfiles`): the selected profiles plus every workflow,
radial menu and AI prompt they reach, directly or through other workflows and menus.

```json
{ "format": "magicforge-profiles", "version": 1, "app": "MagicForge", "exportedAt": "2026-01-01T12:00:00Z",
  "profiles": [], "workflows": [], "radialMenus": [], "aiTemplates": [] }
```

Full backup (`ProfileTransfer.exportBackup`): everything except script approvals.

```json
{ "format": "magicforge-backup", "version": 1, "app": "MagicForge", "exportedAt": "…", "configuration": { } }
```

`Resources/SampleProfiles/*.json` (Browser, Finder, VSCode, Photos, WindowManagement) are written
by this exporter via `SampleProfiles.all()`. Regenerate them with
`MF_WRITE_SAMPLES=1 MF_ONLY=MFProfiles swift test --scratch-path .build-profiles`; the tests fail
when the files drift from the exporter and import every file found in that folder.

## Import and the trust model

Importing is always `ProfileTransfer.preview(data:current:)` followed by
`ProfileTransfer.apply(preview:to:approveScripts:)`. The preview changes nothing.

Rejected with a `ConfigurationError` (never a crash): empty input, more than 5 MB (checked before
parsing), anything that is not a JSON object, a missing or unknown `format`, a missing or
non-integer `version`, a newer `version` or backup `schemaVersion` (`unsupportedSchema`), values of
the wrong type, unknown gestures or actions, and a profile file without profiles.

Profile files:

- **Nothing is overwritten.** Every identifier (profiles, bindings, workflows, menus, menu items,
  prompts) is regenerated and references inside the file are rewritten to match. `apply` checks
  again and regenerates once more if the preview has become stale (for example when applied twice).
- A name that already exists gets ` (imported)`, then ` (imported 2)`, …
- An AI prompt identical to an existing one is reused instead of duplicated. Importing never
  enables AI or changes its endpoint.
- A radial-menu hot key that is already used by an existing menu is removed from the import.
- The import is validated together with the current configuration; clamped values, references to
  things not in the file, and apps that already have a profile come back as `warnings`.
- Unknown bundle identifiers are fine: the profile simply waits for that app.

Scripts (AppleScript, shell, Shortcuts):

- A script runs only when the SHA-256 of its `ScriptAction.trustPayload` (`"shell:<command>"`,
  `"applescript:<source>"`, `"shortcut:<name>"`) is in `Configuration.approvedScriptHashes`.
  Changing one character makes it untrusted again.
- Approvals never travel in files. Exports leave them out, and an `approvedScriptHashes` field in
  an imported file is ignored.
- `ImportPreview.untrustedScripts` lists every script in the file that is not approved on this
  Mac — including those inside workflow steps, conditional branches and radial submenus.
- `apply(…, approveScripts: false)` imports them unapproved; they fail with `ActionError.untrusted`
  until approved. `approveScripts: true` approves exactly the scripts contained in the import.
- Restoring a full backup replaces the configuration (identifiers are kept). Existing approvals
  survive only for scripts whose text is byte-for-byte identical to one in the backup.

SHA-256 comes from CryptoKit where available and from a pure-Swift implementation elsewhere; both
are pinned to the same test vectors.

## Which profile applies (`ProfileResolver`)

1. The manual override, if it names an enabled profile (or the global profile).
2. Otherwise the first enabled profile, in list order, whose `bundleIdentifiers` contain the
   frontmost app's bundle identifier (compared without regard to case).
3. Otherwise the global profile (`Configuration.globalProfileID`).

Disabled profiles never apply, not even through the override. The global profile cannot be
disabled. If the configuration has lost its global profile, the first enabled profile without
apps stands in, or an empty "Global" profile, so resolution always succeeds.

Effective bindings:

- Only enabled bindings count. Within one profile, several bindings on the same trigger resolve to
  the highest `priority`; ties go to the one listed first.
- With `inheritsGlobal`, global bindings are added for every trigger the profile does not bind
  itself; a profile's own binding shadows the global one for that trigger.
- A *disabled* binding does not shadow. To switch an inherited gesture off for one app, bind it to
  "no action" (`.none`): it shadows the global binding and is then dropped.
- With `InputCapabilities`, bindings whose gestures cannot be delivered move to
  `ResolvedProfile.unavailableBindings` and do not enable anything.
- `enabledKinds` is every gesture kind of the remaining bindings, including each kind inside a
  sequence. `chordKinds` is the subset the event tap has to watch.
- Scroll settings: the profile's own, else the global profile's, else defaults (off).
- Tuning: a binding whose `sensitivity` is not 0.5 or whose `duration` is set yields an override
  for its gesture kinds (a single-gesture binding wins over a sequence that uses the same kind).
  `ResolvedProfile.recognizerConfig(base:)` lays these over `RecognizerConfig.tuning`.

## Conflicts (`ConflictDetector`)

| Kind | Severity | Reported when |
| --- | --- | --- |
| `duplicateTrigger` | error | Two enabled bindings of one profile share a trigger. |
| `delaysOther` | info | A one-finger tap (tap, centre, corner) next to a one-finger double tap or tap-then-swipe; a two-finger tap next to a two-finger double tap; a hold next to hold-then-swipe. |
| `overlapsSystemGesture` | warning | One-finger swipes (native scrolling / swipe between pages), two-finger swipe left / right (swipe between full-screen apps), one-finger double tap (Smart zoom), two-finger double tap (Mission Control). Info when a one-finger tap is bound to a click. |
| `unavailableGesture` | error | The gesture needs raw contacts, more fingers, or pointer events than the capabilities offer. |
| `sequencePrefix` | info / warning | A single gesture starts a sequence (info); a sequence is the beginning of a longer one (warning). |

Inherited global bindings take part in the timing checks; shadowing them is not a conflict.
Conflict identifiers are derived from their content, so they are stable across calls.

## Invariants (`ConfigurationValidator.repair`)

Exactly one global profile (recreated or re-adopted when missing; always enabled, no apps, has
scroll settings); unique identifiers everywhere; app lists trimmed and de-duplicated; binding
sensitivity 0…1, duration 0.05…5 s, priority ±1000; sequences 2–4 gestures; scroll multipliers
0.1…10; workflow, wait and AI timeouts above 0 and at most 600 s; recognizer thresholds and
calibration values inside safe ranges; radial menus at most 3 levels deep and 12 items per ring;
approvals must be 64 lowercase hex digits. References to workflows, menus or prompts that do not
exist are reported and kept. A valid configuration is returned unchanged with no messages.
