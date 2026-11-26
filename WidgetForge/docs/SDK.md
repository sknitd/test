# WidgetForge SDK

There are two ways to make a widget, and they share one layout language.

1. **Declarative** (recommended): a JSON document describing components, data sources and permissions.
   Nothing in it is executable. This is what the Builder produces, what templates are, and what the AI
   builder is restricted to.
2. **Scripted**: a declarative document plus a JavaScript file that computes state and returns a layout.
   Scripts run in a restricted runtime and only with the user's explicit trust (see `SECURITY.md`).

## Widget definition

```json
{
  "name": "Mini Monitor",
  "size": { "width": 260, "height": 140 },
  "root": { "type": "column", "children": [ … ] },
  "dataSources": [ { "id": "cpu", "kind": "systemMetric", "metric": "cpu", "interval": 2 } ],
  "permissions": { "systemMetrics": true },
  "settings": { "title": "My Mac" },
  "initialState": { "count": 0 },
  "style": { "background": "material", "cornerRadius": 20, "padding": 14, "tint": "accent" }
}
```

Wrap it as `{"format": "widgetforge.widget", "version": 1, "definition": { … }}` to share it as a
`.wfwidget` file (a bare definition also imports).

## Components

A component is `{ "type": …, …props, "children": [ … ] }`. Props may sit beside `type` or inside `"props"`.

| Type | Main props |
| --- | --- |
| `column`, `row`, `stack` | `spacing`, `alignment`, `children` |
| `canvas` | absolute layout; each child has `frame {x,y,width,height}` and `constraints {pinLeft,pinTop,pinRight,pinBottom}` |
| `spacer`, `divider` | `length` (spacer) |
| `text` | `value`, `fontSize`, `fontWeight`, `fontDesign`, `color`, `alignment`, `lineLimit` |
| `richText` | `value` (inline Markdown) |
| `button` | `title`, `symbol`, `style` (`bordered`/`prominent`/`plain`), `action` |
| `image` | `symbol` or `url` (https, host must be in the network allowlist), `contentMode` |
| `icon` | `symbol`, `size`, `color` |
| `clock`, `date` | `format` (Unicode date pattern), `timezone` (IANA id) |
| `countdown` | `target` (ISO date), `label` |
| `progress` | `value` (0…`max`, default max 1), `label`, `valueLabel`, `tint` |
| `gauge` | `value`, `min`, `max`, `label`, `valueLabel`, `gaugeStyle` (`ring`/`linear`), `tint` |
| `slider`, `toggle`, `input` | `bind` (state key), `label`/`placeholder`, `min`/`max`/`step`, `multiline`, `onChange` |
| `chart` | `chartKind` (`line`/`bar`/`area`/`pie`/`donut`/`sparkline`), `values`, `xPath`, `yPath`, `color`, `showAxes`, `yMin`, `yMax`, `threshold`, `title`, `height` |
| `table` | `items`, `columns` `[{title, path}]`, `limit` |
| `list` | `items`, `titlePath`, `subtitlePath`, `trailingPath`, `urlPath`, `symbol`, `limit`, `emptyText` |
| `calendar` | month grid; `showEvents` declares calendar use |
| `weather` | `temperature`, `code` (WMO), `high`, `low`, `location`, `unit` |
| `apiViewer` | `value` (any JSON), `source` (id whose status to show) |
| `metric` | `metric`: `cpu`/`memory`/`storage`/`network`/`battery`/`system` |
| `web` | `url` (host must be in `permissions.webContent`); overlay only |
| `script` | shows what the widget's script `render()` returns; overlay only |
| `todo`, `pomodoro`, `habits`, `clipboard`, `media` | stateful components; `bind` names their state key |

Every component also accepts `padding`, `background`, `cornerRadius`, `borderColor`, `borderWidth`,
`shadowRadius`, `opacity`, `animation` (`fade`/`pulse`/`bounce`) and
`visibleWhen: {path, op, value}` (`op` is one of `< <= > >= == != contains exists`).

Colours are names (`primary`, `secondary`, `accent`, `red`, `orange`, `yellow`, `green`, `mint`, `teal`,
`cyan`, `blue`, `indigo`, `purple`, `pink`, `brown`, `gray`, `white`, `black`) or hex (`#RGB`, `#RRGGBB`,
`#RRGGBBAA`).

## Placeholders

Any string prop may contain `{{path | filter:arg | …}}`. Paths read from:

- a data source by id: `{{cpu.usage}}`, `{{api.items[0].title}}`, `{{api.items.count}}`
- `state.*` (persistent widget state), `settings.*`
- `sources.<id>.state|label|detail|healthy` (data source status)

A prop that is exactly one placeholder keeps its JSON type, which is how charts and lists receive arrays.

Filters: `percent[:digits]`, `round[:digits]`, `fixed[:digits]`, `mul:n`, `div:n`, `add:n`, `bytes`, `rate`,
`duration`, `currency[:symbol]`, `signed[:digits]`, `upper`, `lower`, `default:text`, `count`, `first`,
`last`, `limit:n`, `pluck:key`, `join[:sep]`, `yesno`, `truncate:n`, `date[:pattern]`, `relative`, `until`.

There are no loops, function calls or assignments: placeholders format data, they are not a language.

## Data sources

| `kind` | Fields | Minimum interval |
| --- | --- | --- |
| `systemMetric` | `metric` | 1 s |
| `rest` | `url`, `method`, `headers`, `body`, `transform`, `cacheTTL`, `retry`, `requiredPaths` | 15 s |
| `localHTTP` | as `rest`, host must be a local address | 2 s |
| `webSocket` | `url` (`wss://`), `headers`, `transform` | push |
| `jsonFile`, `csvFile` | `fileID` (a file the user chose) | 2 s |
| `calendar` | upcoming events `[{title, start, end, calendar, allDay}]` | 60 s |
| `time` | `{epoch, iso, year, month, day, hour, minute, second, weekday}` | 1 s |
| `userData` | `value` (literal JSON) | – |

`url`, header values and `body` may use `{{settings.key}}` (path and query only, never the host) and
`{{secret:NAME}}`. Secrets live in the Keychain, are bound to hosts, and are never visible to the widget.

System metric shapes (fractions are 0…1):

- `cpu`: `usage`, `user`, `system`, `cores[]`, `coreCount`, `history[]`
- `memory`: `usage`, `usedBytes`, `availableBytes`, `totalBytes`, `appBytes`, `wiredBytes`, `compressedBytes`, `pressure`, `history[]`
- `storage`: `usage`, `usedBytes`, `freeBytes`, `totalBytes`, `volume`, `readBytesPerSec`, `writeBytesPerSec`
- `network`: `downBytesPerSec`, `upBytesPerSec`, `connected`, `primaryInterface`, `address`, `interfaces[]`, `downHistory[]`, `upHistory[]`
- `battery`: `present`, `level`, `charging`, `charged`, `source`, `onBattery`, `minutesRemaining`, `minutesToFull`, `history[]`
- `system`: `uptimeSeconds`, `hostname`, `osVersion`, `architecture`, `model`, `processor`, `cores`, `memoryBytes`, `thermalState`, `lowPowerMode`

Rate values are `null` until two samples exist; `battery.level` is `null` on Macs without a battery.

## Actions

`{"type": "setState", "key", "value"}`, `toggleState`, `incrementState` (`by`), `refresh`,
`openURL` (`url`), `runShortcut` (`name`), `launchApp` (`bundleID`), `copy` (`text`),
`media` (`command`: `playpause`/`next`/`previous`), `trigger` (`name`; fires a "widget interaction"
automation), `script` (`name`; calls a script action).

## Controlling WidgetForge from outside

**URL scheme.** Open these from Terminal (`open "widgetforge://toggle"`), scripts or launchers:

| Link | Effect |
| --- | --- |
| `widgetforge://show` · `hide` · `toggle` | show, hide or toggle all widgets |
| `widgetforge://edit?on=1` | Edit mode on (`on=0` off) |
| `widgetforge://pause` · `resume` | pause or resume all updates |
| `widgetforge://profile?name=Work` | switch profile (no name = All Widgets) |
| `widgetforge://theme?name=Midnight` | apply a theme to every widget |
| `widgetforge://tidy?edge=left` | tidy up (`left`, `right`, `top`, `bottom`) |
| `widgetforge://open?section=diagnostics` | open a main-window section |
| `widgetforge://command-center` | open the Command Center |
| `widgetforge://run?name=High%20CPU` | run an automation (**asks first**) |
| `widgetforge://add?template=CPU%20Monitor` | add a built-in template (**asks first**) |

Any app or web page can open a URL, so the scheme cannot import files, change permissions or read
anything, and the two commands that add or run something require confirmation.

**Shortcuts.** The app provides *Show or Hide Widgets*, *Switch Widget Profile*, *Apply Widget Theme*,
*Tidy Up Widgets* and *Run WidgetForge Automation* actions.

## Automation triggers

`timer`, `appLaunch`, `appActivate`, `networkChange`, `batteryBelow`, `widgetInteraction`,
`dataCondition` (a widget's data makes a condition true), `metricSustained` (a system-metric condition such
as `cpu.usage > 0.9` holds for N seconds without interruption; fires once per episode) and `manual`.
Conditions use the same `{path, op, value}` form as `visibleWhen`; for `metricSustained` the path starts
with a metric name (`cpu.usage`, `memory.usage`, `storage.usage`, `battery.level`, `network.downBytesPerSec`).

## Permissions

```json
{ "network": ["api.example.com", "*.example.org"], "webContent": [], "systemMetrics": false, "files": [],
  "clipboard": false, "calendar": false, "notifications": false, "openURLs": false, "shortcuts": false,
  "launchApps": false, "mediaControl": false, "scripting": false }
```

A widget gets only what it declares **and** the user grants. Wildcards never match local addresses.

## JavaScript widgets

```js
WidgetForge.defineWidget({
  id: "system-monitor",
  name: "System Monitor",
  size: { width: 320, height: 220 },
  interval: 2,                      // seconds between update() calls (minimum 1)

  async update(context, state) {    // state is whatever the previous update() returned
    const cpu = await context.system.cpu();
    const memory = await context.system.memory();
    return { cpu, memory };
  },

  render(state) {                   // must return a component tree (validated like any import)
    return { type: "column", children: [
      { type: "text", value: "System Monitor" },
      { type: "progress", value: state.cpu },
      { type: "progress", value: state.memory }
    ] };
  },

  actions: {                        // called by {"type": "script", "name": "reset"} actions
    reset(context, state, payload) { return { ...state, cpu: 0 }; }
  }
});
```

`context`:

| Member | Returns | Requires |
| --- | --- | --- |
| `system.cpu()`, `system.memory()` | fraction 0…1 | `systemMetrics` |
| `system.cpuDetail()`, `memoryDetail()`, `storage()`, `network()`, `battery()`, `info()` | metric objects above | `systemMetrics` |
| `fetch(url, {method, headers, body, cacheSeconds})` | parsed JSON (or text) | host in `network` |
| `data(id)` | latest value of a declared data source | – |
| `settings` | the widget's settings object | – |
| `storage.get(key)`, `storage.set(key, value)` | persistent JSON, 64 KB per value | – |
| `log()`, `warn()`, `error()` (also `console.*`) | – | – |

All `system.*` functions and `fetch` return Promises. There is no `setTimeout`, DOM, `XMLHttpRequest`,
`require`, filesystem or process access; the global object contains only the ECMAScript standard library,
`WidgetForge` and `console`.

Limits (defaults): 1 s of synchronous execution per call, 15 s per `update()` including awaited requests,
8 fetches per run, 256 KB of returned state or layout, 400 components, 50 log lines per run. A script that
exceeds a limit or throws is stopped and its widget shows the error; it is not restarted in a loop.
