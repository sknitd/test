# Security

WidgetForge displays content that may come from other people (imported widget files, AI output, remote
APIs). This document states what protects you, how it is enforced, and where the protection ends.

## Threat model

- **In scope:** a malicious or careless widget file; a hostile API response; a model that returns
  something other than what was asked; a widget trying to reach data or hosts it was not granted.
- **Out of scope:** an attacker who already runs code as your user, and JavaScriptCore engine exploits
  (see "What the script runtime is not").

## Layers

### 1. Declarative by default
A widget is data: a component tree, data-source descriptions and a permission manifest. Rendering it
executes nothing from the file. Placeholders (`{{cpu.usage | percent}}`) can read and format values from
the widget's own context; they cannot call functions, loop or reach outside that context
(`Sources/Core/TemplateString.swift`).

### 2. Validation before anything is decoded or shown
`SchemaValidator` checks raw JSON for unknown component types and actions, depth (12), component count
(400), string and file size limits, URL schemes (`http`, `https`, `ws`, `wss` only; no `file:`,
`javascript:`), credentials in URLs, placeholders in the host part of a URL, and inline credentials in
headers. Imports, AI output and the layout returned by a script's `render()` all pass through it.

### 3. Capability permissions
Each widget has a requested manifest and a granted manifest; effective permissions are the intersection,
re-evaluated on every use, so revoking a switch takes effect on the next request or script call.

| Capability | Enforced in |
| --- | --- |
| Network hosts | `DataSourceEngine.buildRequest` (before any secret is substituted) |
| Redirects | `URLSessionTransport` refuses cross-host and HTTPS→HTTP redirects |
| Secrets | bound to hosts; substituted natively after the allowlist check; never returned to a widget |
| System metrics, calendar, files | `DataSourceEngine.load` |
| Files | only security-scoped bookmarks of files the user picked; widgets hold an opaque id |
| Clipboard | read only when the user presses the widget's button; no background monitoring |
| Open URLs / Shortcuts / apps / media | `WidgetRuntime.perform` |
| Web content | `RestrictedWebView`: top-level navigation confined to the allowlist, non-persistent store |
| Scripting | `WidgetInstance.scriptEnabled` = has script ∧ user trusted it ∧ permission granted |

Templates you add yourself are granted what they declare. Imported and AI-generated widgets always go
through a review sheet showing the request, with script execution **off** unless you switch it on.

When a permission is revoked, cached responses are not shown either (`testRevokedPermissionHidesCachedData`).

### 4. Secrets
API keys are Keychain generic-password items. Definitions refer to them as `{{secret:NAME}}`.
`SecretScrubber` rewrites any literal credential-looking header, query parameter or setting to a
placeholder on export **and** on import, strips file bookmarks, and exports never include widget state
(your notes, to-dos, clipboard items). `testExportNeverContainsSecretsOrState` covers this.

### 5. Script runtime
What it is: one `JSVirtualMachine` per widget on a private queue. A bare JavaScriptCore context has no
network, file, process, timer or DOM API; the only bridge is the `context` object, built by an SDK
prelude that captures the native functions in a closure, deletes them from the global object and freezes
`WidgetForge`. Every bridge function checks the widget's current permissions natively. Values cross the
boundary as JSON text only. Tests assert that `fetch`, `XMLHttpRequest`, `require`, `process` and
`setTimeout` are undefined and that the SDK object cannot be replaced (`testNoAmbientAuthority`).

Limits: synchronous execution is interrupted by JavaScriptCore's execution-time-limit watchdog
(default 1 s); async work has a 15 s deadline; fetch count, returned size, storage size and log volume
are capped. A script that fails or times out is stopped, not retried.

**What the script runtime is not.** It is not an OS sandbox. The script runs inside the app's process,
so a memory-safety bug in JavaScriptCore could, in principle, give a script the app's privileges (which
are themselves limited by the App Sandbox: no arbitrary file access, network client only). For that
reason:

- arbitrary third-party code is **never run automatically**: imported scripts are disabled until trusted;
- AI-generated widgets may not contain scripts at all (they are stripped, and `script`/`web` components
  are rejected);
- the watchdog relies on `JSContextGroupSetExecutionTimeLimit`, a WebKit SPI resolved at runtime with
  `dlsym`. If the symbol is missing, WidgetForge refuses to run scripts rather than risk an
  uninterruptible loop. Because it is SPI, a Mac App Store build should ship with scripting disabled or
  with the out-of-process design below.

### Design required before running untrusted scripts unattended (not implemented)
Move `ScriptRuntime` into an XPC service with its own sandbox profile (no network, no file access, no
Keychain), one process per widget or a small pool. The app keeps the bridge: the service sends
capability requests over XPC, the app enforces permissions exactly as today and returns JSON. Runaway or
crashed scripts are handled by killing the process, removing the dependence on the SPI watchdog, and an
engine exploit is contained by the service's sandbox. Until that exists, "trusted by the user" is the
gate, and this document says so plainly.

### 6. App Sandbox
Both targets are sandboxed. The app's entitlements: outgoing network, user-selected files, calendars,
Apple Events to Music only (`com.apple.Music.playback` scripting target), and the shared App Group.
There is no shell execution anywhere in the code base and no entitlement that would allow it.

### 7. AI builder
Optional and off by default. The prompt goes only to the endpoint you configure; the key is a Keychain
secret bound to that host. The reply is treated as an untrusted import: JSON is extracted, scripts and
`scripting`/`files` permissions are removed, the result is validated, permissions are recomputed from
content (not taken from the model), and nothing is saved until you approve the review sheet.

## Reporting
Please report vulnerabilities privately to the repository owner rather than in a public issue.
