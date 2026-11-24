# Architecture

WidgetForge is one Xcode project with two targets (the app and a WidgetKit extension) and one Swift
package (`WidgetForgeKit`) that exists to unit-test the core without launching the app.

```
Sources/
  Core/          models (WidgetNode, WidgetDefinition, WidgetInstance), WidgetStore, LayoutEngine,
                 TemplateRenderer (placeholders), TemplateLibrary, WidgetPackage, SharedSnapshot
  Persistence/   DocumentStore protocol, SQLiteDocumentStore, InMemoryDocumentStore
  DataSources/   DataSourceEngine (actor), DataSourceConfig, SystemMetricsCollector, CSV parser
  Security/      PermissionChecker, SchemaValidator, SecretScrubber, SecretStore (Keychain)
  Scripting/     ScriptRuntime (JavaScriptCore), AIWidgetGenerator
  Automation/    AutomationEngine (actor), triggers, actions
  Profiles/      ProfileManager, rule evaluation
  Diagnostics/   DiagnosticsCenter, TimingStats, FuzzyMatcher
  Widgets/       SwiftUI renderer shared by app and extension (NodeView, charts, stateful nodes)
  ─────────────  everything above compiles into the app, the extension and the test package
  App/           WidgetForgeApp, AppModel (composition root), WidgetRuntime, system services
  Desktop/       OverlayManager, WidgetPanel, edit overlay (drag / resize / guides)
  Builder/       BuilderModel (undo, selection, canvas operations), BuilderView
  UI/            main window sections, Command Center
WidgetExtension/ WidgetKit widget, App Intents, timeline provider
Tests/           XCTest suites for WidgetForgeKit
Config/          Info.plist fragments and entitlements
Scripts/         project generator, build, DMG, notarisation, icon
```

The requested module names map to these folders: *WidgetCore* → `Core` + `Persistence`,
*WidgetKitBridge* → `WidgetExtension` + `Core/SharedSnapshot.swift`, *DesktopOverlayEngine* → `Desktop`,
*ScriptEngine* → `Scripting`, *DataSourceEngine* → `DataSources`, *VisualWidgetBuilder* → `Builder`,
*AutomationEngine* → `Automation`, *WidgetMarketplace* → `Core/WidgetPackage.swift` + the Marketplace
section, *Persistence* and *Diagnostics* as named.

## Two rendering backends, one renderer

```
                    WidgetDefinition (JSON tree + data sources + permissions)
                                         │
                 ┌───────────────────────┴────────────────────────┐
        Live Desktop Overlay                               Native WidgetKit
   WidgetRuntime (per visible widget)                 WidgetForgeProvider (timeline)
   · subscribes to DataSourceEngine                   · reads snapshot.json from the App Group
   · runs ScriptRuntime if trusted                    · samples metrics once per reload
   · handles actions with permission checks           · App Intents write pending.json
                 │                                                │
                 └──────────────► NodeView(node, RenderEnvironment) ◄──────────┘
```

`RenderEnvironment` carries the data context and a handful of closures. The host decides what is
possible by which closures it supplies: the overlay provides `perform`, `setState`, `webView`; the
extension provides only `intentButton`, so everything else is inert there by construction.

## Data flow in the overlay

1. `WidgetStore` (SQLite-backed) is the source of truth. Every mutation calls `onChange`.
2. `AppModel.storeChanged()` republishes arrays for SwiftUI, reconciles `WidgetRuntime`s (one per
   visible widget; hidden widgets have none) and calls `OverlayManager.sync()`.
3. A runtime subscribes each data source with the engine. Results arrive on the main actor, are merged
   into the widget's context and published at most once per run-loop turn.
4. `WidgetHostView` observes its runtime and re-renders `NodeView`s. Clocks use `TimelineView`, so they
   tick without any app-level timer.
5. User interaction calls `RenderEnvironment.perform`/`setState` → runtime → permission check → store.

## Concurrency

- `AppModel`, `WidgetRuntime`, `OverlayManager`, `BuilderModel`, `MetricsHub` are `@MainActor`.
- `DataSourceEngine` and `AutomationEngine` are actors; their clocks and sleepers are injected so tests
  run instantly and deterministically.
- `SystemMetricsCollector` is lock-protected and sampled on a utility queue by `MetricsHub`, which runs
  only while it has consumers.
- Each `ScriptRuntime` owns a `JSVirtualMachine` and a private serial queue.

## Persistence

One SQLite file (`~/Library/Containers/com.widgetforge.app/Data/Library/Application Support/WidgetForge/widgetforge.sqlite`,
WAL mode) with a single `documents(collection, id, body, updated)` table holding JSON documents:
widgets, trash, layouts, profiles, automations, library, settings, file bookmarks and the response cache.
Undecodable rows are skipped and logged, never fatal. Secrets are not in this file; they are Keychain items.

## Why the Xcode project is generated

`Scripts/generate_xcodeproj.py` writes a small, deterministic `project.pbxproj` that uses Xcode 16
file-system-synchronised groups: every file in a listed folder is compiled, so adding a source file never
touches the project. CI regenerates it and fails if the committed copy differs.
