# MagicForge — shared brief for implementation agents

MagicForge is a native macOS 14+ menu-bar app (Swift 5.9+, SwiftUI + AppKit, zero third-party
dependencies) that turns touch input from an Apple Magic Mouse into configurable gestures.
Several agents are implementing different modules AT THE SAME TIME in this one directory
(`/home/user/test/MagicForge`). Read this file, then `Package.swift`, then every file in
`Sources/Core/` and `Sources/Engine/AppModel.swift` before writing code: they are the contract.

## Ground rules
- Edit ONLY the paths your task assigns to you. Never edit `Package.swift`, `Sources/Core/*.swift`
  (top level), `Sources/Engine/AppModel.swift` or another agent's files. If the contract is
  missing something you need, work within it and report the gap in your final message.
- Do NOT run git commands that change state (no commit, stash, checkout, reset). The lead commits.
- No third-party packages. No placeholder / TODO implementations, no decorative controls that do
  nothing, no invented system APIs. If something cannot be done reliably, implement the best
  legitimate fallback, surface it as unavailable with a reason, and note it in your final message.
- Never claim something works unless you ran it. Say exactly what you verified and how.
- Swift style: small focused files (aim < 400 lines), descriptive names, explicit error handling,
  no force unwraps unless provably safe, `Log("category")` from MFUtilities for logging (never
  log touch coordinates, clipboard text, typed text or script bodies).
- Language mode is Swift 5 (tools 5.9). Code must compile with Xcode 15.x (Swift 5.9/5.10) AND
  Swift 6.0 toolchains: avoid features newer than Swift 5.9.
- Deployment target is macOS 14.0. Use Observation (`@Observable`), not ObservableObject.

## Build environment (important)
- This machine is LINUX (no macOS SDK, no Xcode). Swift 6.0.3 is at `/opt/swift/usr/bin/swift`.
- Portable modules (MFUtilities, MFCore, MFGestures, MFProfiles, MFAutomation, MFIntegrations,
  MFEngine) MUST compile and pass tests here. Use Foundation only; guard Apple-only frameworks
  with `#if canImport(...)`. On Linux `URLSession` needs `#if canImport(FoundationNetworking)
  import FoundationNetworking #endif`.
- Because other agents are editing concurrently, build ONLY your module with a private scratch dir:
  `MF_ONLY=<YourModule> /opt/swift/usr/bin/swift test --scratch-path .build-<yourmodule>`
  (see the comment at the top of Package.swift). A plain `swift build` may fail on someone else's
  half-written file; that is not your problem.
- macOS-only modules (MFDevices, MFInput, MFActions, MFUI, MFApp, mfprobe) CANNOT be compiled
  here. They will first be compiled later on a macOS CI runner (Xcode 16.0, 16.4 and 26.x; no Xcode 15 or macOS 14 runner exists). Every
  compile error costs a CI round trip, so: use only APIs you are certain exist with the exact
  signatures, add explicit types where inference is fragile, keep SwiftUI view bodies small
  (split into subviews to avoid type-checker timeouts), mark AppKit/SwiftUI types `@MainActor`
  where needed, and re-read each file once for typos, missing imports and access control
  (anything used from another module must be `public`, including initializers).
  You can syntax-check a macOS-only file with `/opt/swift/usr/bin/swiftc -parse <file>`
  (catches syntax errors only) — do this for every file you write.

## Module map (target → directory → owner)
- MFUtilities → Sources/Utilities — lead (Log, MonotonicClock, Locked).
- MFCore → Sources/Core — lead (contract). `Sources/Core/Catalog/` → automation agent.
- MFGestures → Sources/Gestures, Tests/GestureTests — gesture agent.
  Pinned API: `public final class GestureEngine: GestureRecognizing` with
  `public init(config: RecognizerConfig = .init(), calibration: DeviceCalibration = .init())`;
  `public final class SequenceMatcher` (matches `GestureTrigger.sequence`);
  `public enum SyntheticTouch` with `static func frames(for kind: GestureKind, startTime: TimeInterval,
  surface: SurfaceGeometry = .magicMouse, frameInterval: TimeInterval = 0.011) -> [TouchFrame]` and
  `static func demoReel(startTime: TimeInterval) -> [TouchFrame]`.
- MFProfiles → Sources/Profiles, Tests/ProfileTests — profile agent.
  Pinned API: `public final class JSONConfigurationStore: ConfigurationStoring` with
  `public init(directory: URL)` and `public static var defaultDirectory: URL`;
  `DefaultConfiguration.make() -> Configuration`; `ProfileResolver`; `ConflictDetector`;
  `ProfileTransfer` (export / import preview); `ScriptTrust`; `ConfigurationValidator`.
- MFAutomation → Sources/Automation, Tests/AutomationTests — automation agent.
  Pinned API: `WorkflowRunner`, `WorkflowValidator`, `ScrollTransformer`.
- MFIntegrations → Sources/Integrations, Tests/IntegrationTests — automation agent.
  Pinned API: `public final class OpenAICompatibleClient: AICompleting` (`public init()`),
  `public final class KeychainSecretStore: SecretStoring` (`public init(service: String)`, Apple only),
  `public final class InMemorySecretStore: SecretStoring`.
- MFEngine → Sources/Engine, Tests/EngineTests — engine agent (runs after the others).
- MFDevices → Sources/Devices — input agent. Pinned: `public final class HIDDeviceMonitor: DeviceMonitoring` (`public init()`).
- MFInput → Sources/Input — input agent. Pinned: `public final class MultitouchSupportAdapter: TouchInputAdapter`
  (`public init()`), `public final class EventTapPointerSource: PointerEventSource` (`public init()`).
- mfprobe → Sources/Probe — input agent.
- MFActions → Sources/Actions — actions agent. Pinned: `public final class SystemActionPerformer: ActionPerforming`
  (`public init(permissions: PermissionsProviding)`), `public final class SystemPermissions: PermissionsProviding`
  (`public init()`), `public final class WorkspaceAppProvider: FrontmostAppProviding` (`public init()`),
  `public final class PasteboardTextAccess: TextAccessProviding` (`public init()`),
  `public final class UserNotificationNotifier: UserNotifying` (`public init()`).
- MFUI → Sources/UI — three UI agents, split by subdirectory (see below).
- MFApp → Sources/App, Sources/AppMain — shell UI agent.

## Catalog API (Sources/Core/Catalog, written by the automation agent; UI may rely on it)
- `GestureKind`: `displayName: String`, `symbolName: String` (SF Symbol), `summary: String` (one line how-to).
- `GestureKind.Category`: `displayName`, `symbolName`. `GestureKind.Direction` via `GestureKind.direction: Direction?`.
- `GestureTrigger`: `displayName`.
- `Action`: `displayName`, `symbolName`, `category: ActionCategory`.
- `enum ActionCategory: String, CaseIterable, Identifiable` = system, window, app, keyboard, mouse, text,
  script, workflow, radialMenu, ai, control — each with `displayName`, `symbolName`.
- `struct ActionTemplate: Identifiable { id: String; name: String; symbolName: String; category: ActionCategory; action: Action }`
  and `ActionCatalog.templates: [ActionTemplate]`, `ActionCatalog.templates(in: ActionCategory)`.
- `SystemAction.displayName/symbolName`, `WindowAction.displayName/symbolName`, `ControlAction.displayName`.
- `KeyCombo.displayString` (e.g. "⌃⌥⇧⌘K", derived from keyCode + modifiers), `KeyCodeNames.name(for: UInt16) -> String`,
  `KeyCodes` constants for common keys (`KeyCodes.space`, `.returnKey`, `.tab`, `.escape`, `.leftArrow`, `.rightArrow`,
  `.upArrow`, `.downArrow`, `.delete`, letters `.a`…`.z`, digits `.zero`…`.nine`, `.f1`…`.f12`, `.leftBracket`, `.rightBracket`, `.grave`).
- `PermissionKind.displayName`, `MagicMouseModel` already has `displayName`.

## UI conventions (MFUI; macOS only)
- Every screen is a `public struct <Name>View: View` with `public init()` that reads
  `@Environment(AppModel.self) private var model` and `@Environment(NavigationState.self) private var navigation`.
- All configuration changes go through `model.update { config in … }`. Never keep a private copy
  of configuration that can go stale; derive from `model.configuration`.
- Shell (shell UI agent, Sources/UI/Shell):
  - `@MainActor @Observable public final class NavigationState { public var section: SidebarSection; public var editingProfileID: UUID?
    /* nil = global profile */; public var selectedGesture: GestureKind?; public init() }`
  - `public enum SidebarSection: String, CaseIterable, Identifiable` = dashboard, gestures, gestureStudio, touchLab,
    profiles, actions, automation, radialMenu, scrolling, ai, devices, permissions, settings (`title`, `symbolName`).
  - Design system (Sources/UI/Shell/DesignSystem.swift), usable by all UI agents:
    `MFPage(_ title: String, subtitle: String? = nil, @ViewBuilder content:)` (scrolling page with header; also
    `MFPage(_:subtitle:toolbar:content:)` taking a trailing `@ViewBuilder toolbar`),
    `MFCard(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content:)`,
    `MFStatusBadge(_ text: String, style: MFStatusStyle)` with `enum MFStatusStyle { case good, warning, bad, neutral, info }`,
    `MFEmptyState(systemImage: String, title: String, message: String)`,
    `MFKeyValueRow(_ key: String, value: String)`, and `extension Color { init?(hex: String) }`.
- Gesture UI agent (Sources/UI/Gestures, TouchLab, Scrolling, Calibration): `GesturesView`, `GestureStudioView`,
  `TouchLabView`, `ScrollingView`, plus reusable `GesturePreview(kind: GestureKind, isAnimating: Bool)` and
  `MouseSurfaceShape` (the stylized mouse outline).
- Action UI agent (Sources/UI/Actions, Automation, RadialMenu, AI): `ActionsView`, `AutomationBuilderView`,
  `RadialMenuView`, `AIIntegrationsView`, plus reusable `ActionEditor(action: Binding<Action>)`,
  `ActionLabel(action: Action)`, `KeyComboRecorder(combo: Binding<KeyCombo?>)`,
  `@MainActor public final class RadialMenuController: RadialMenuPresenting` (`public init()`),
  `@MainActor public final class AIInteractionController: AIInteractionPresenting` (`public init()`).
- Shell UI agent (Sources/UI/Shell, Dashboard, Profiles, Devices, Permissions, Settings + Sources/App):
  `MainWindowView`, `DashboardView`, `ProfilesView`, `DevicesView`, `PermissionsView`, `SettingsView`, `MenuBarContentView`.
- Visual direction: a real Mac utility. `NavigationSplitView` sidebar, `Form`/`.formStyle(.grouped)` and
  `Table`/`List` where they fit, SF Symbols, system materials and semantic colours (works in light and
  dark), standard control sizes, keyboard navigable, resizable window (min ~900×600). No iPad-style giant
  buttons. Every control must do something real.

## Honesty rules that shape the product
- Raw finger positions are only available through Apple's PRIVATE MultitouchSupport.framework; the
  adapter is isolated in MFInput, loaded with `dlopen`/`dlsym` at runtime, and can be missing.
  When it is unavailable the app says so and only offers fallback (`GestureKind.Category.fallback`) triggers.
- Never fabricate live finger positions. Synthetic input is always labelled synthetic.
- Script / shell / Shortcut actions only run when their hash is in `Configuration.approvedScriptHashes`.
- AI is off by default; nothing is sent anywhere without an explicit user-triggered action and consent.
