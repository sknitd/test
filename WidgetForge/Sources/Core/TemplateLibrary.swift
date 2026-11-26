import Foundation

/// The widgets that ship with WidgetForge. Every template is plain declarative data built from the same
/// components users get in the builder; none of them contains sample or placeholder "live" values.
/// Templates that need an external service say so in `setupInstructions` and show a setup hint until configured.
enum TemplateLibrary {
    static let all: [WidgetDefinition] = [
        digitalClock, worldClock, calendar, pomodoro, cpuMonitor, ramMonitor, networkMonitor, batteryDashboard,
        diskMonitor, weather, stocks, crypto, githubActivity, apiStatus, serverHealth, notes, todo, clipboard,
        countdown, customREST, customScript, mediaControls, shortcutLauncher, habitTracker, multiMetric,
    ]

    static func template(named name: String) -> WidgetDefinition? { all.first { $0.name == name } }

    static var categories: [String] {
        var seen: [String] = []
        for t in all where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    private static let metrics = PermissionManifest(systemMetrics: true)

    // MARK: Time

    static let digitalClock = WidgetDefinition(
        name: "Digital Clock", summary: "Large local time with the date.", category: "Time", symbol: "clock",
        size: WidgetSize(220, 110),
        root: .column(spacing: 2, alignment: "center", [
            .spacer,
            WidgetNode(.clock, props: ["format": "{{settings.format}}", "fontSize": 46, "fontWeight": "semibold", "fontDesign": "rounded"]),
            WidgetNode(.date, props: ["format": "EEEE, MMMM d", "fontSize": 13, "color": "secondary"]),
            .spacer,
        ]),
        settings: ["format": "HH:mm"])

    private static func zoneRow(_ index: Int) -> WidgetNode {
        .row([
            .column(spacing: 0, [
                .text("{{settings.city\(index)}}", size: 13, weight: "medium", lineLimit: 1),
                WidgetNode(.date, props: ["format": "EEE, MMM d", "timezone": .string("{{settings.zone\(index)}}"), "fontSize": 10, "color": "secondary"]),
            ]),
            .spacer,
            WidgetNode(.clock, props: ["format": "HH:mm", "timezone": .string("{{settings.zone\(index)}}"), "fontSize": 19, "fontWeight": "semibold", "fontDesign": "rounded"]),
        ])
    }

    static let worldClock = WidgetDefinition(
        name: "World Clock", summary: "Three time zones side by side.", category: "Time", symbol: "globe",
        size: WidgetSize(264, 190),
        root: .column(spacing: 8, [.title("World Clock", symbol: "globe"), zoneRow(1), .divider, zoneRow(2), .divider, zoneRow(3)]),
        settings: ["city1": "San Francisco", "zone1": "America/Los_Angeles", "city2": "London", "zone2": "Europe/London",
                   "city3": "Tokyo", "zone3": "Asia/Tokyo"],
        setupInstructions: "Edit the city names and IANA time-zone identifiers (e.g. Europe/Paris) in the widget's settings.")

    static let calendar = WidgetDefinition(
        name: "Calendar", summary: "Month grid with today highlighted and, optionally, your next events.", category: "Time",
        symbol: "calendar", size: WidgetSize(260, 300),
        root: .column(spacing: 8, [
            WidgetNode(.calendar, props: ["showEvents": true]),
            .divider,
            WidgetNode(.list, props: ["items": "{{events}}", "titlePath": "title", "subtitlePath": "start | date:EEE HH:mm", "limit": 3,
                                      "emptyText": "No upcoming events"]),
            .statusNote(source: "events"),
        ]),
        dataSources: [DataSourceConfig(id: "events", name: "Upcoming events", kind: .calendar, interval: 300)],
        permissions: PermissionManifest(calendar: true),
        setupInstructions: "The month grid works immediately. To list upcoming events, allow calendar access when macOS asks.")

    static let countdown = WidgetDefinition(
        name: "Countdown", summary: "Days, hours and minutes until a date you choose.", category: "Time", symbol: "hourglass",
        size: WidgetSize(240, 110),
        root: .column(spacing: 4, alignment: "center", [
            .spacer,
            WidgetNode(.countdown, props: ["target": "{{settings.target}}", "label": "{{settings.title}}"]),
            .spacer,
        ]),
        settings: ["title": "New Year", "target": "2027-01-01T00:00"],
        setupInstructions: "Set the title and target date (YYYY-MM-DDTHH:mm) in the widget's settings.")

    static let pomodoro = WidgetDefinition(
        name: "Pomodoro Timer", summary: "Focus and break intervals with a session counter.", category: "Productivity", symbol: "timer",
        size: WidgetSize(220, 170),
        root: .column(spacing: 6, alignment: "center", [
            .title("Pomodoro", symbol: "timer"),
            WidgetNode(.pomodoro, props: ["bind": "pomodoro", "workMinutes": "{{settings.workMinutes}}", "breakMinutes": "{{settings.breakMinutes}}"]),
        ]),
        permissions: PermissionManifest(notifications: true),
        settings: ["workMinutes": 25, "breakMinutes": 5])

    // MARK: System

    static let cpuMonitor = WidgetDefinition(
        name: "CPU Monitor", summary: "Total and per-core utilisation with a one-minute history.", category: "System", symbol: "cpu",
        size: WidgetSize(280, 210),
        root: .column(spacing: 8, [
            .row([.title("CPU", symbol: "cpu"), .text("{{cpu.usage | percent}}", size: 22, weight: "semibold", design: "rounded")]),
            .chart("area", values: "{{cpu.history}}", height: 64, extra: ["yMin": 0, "yMax": 1, "threshold": 0.9]),
            .chart("bar", values: "{{cpu.cores}}", color: "blue", height: 40, extra: ["yMin": 0, "yMax": 1, "title": "Cores"]),
            .row([.labeled("User", "{{cpu.user | percent}}"), .labeled("System", "{{cpu.system | percent}}")]),
        ]),
        dataSources: [.metric("cpu")], permissions: metrics)

    static let ramMonitor = WidgetDefinition(
        name: "RAM Monitor", summary: "Memory used, available and pressure.", category: "System", symbol: "memorychip",
        size: WidgetSize(260, 190),
        root: .column(spacing: 8, [
            .row([.title("Memory", symbol: "memorychip"), .text("{{memory.usage | percent}}", size: 22, weight: "semibold", design: "rounded")]),
            .progress("{{memory.usage}}", tint: "purple"),
            .chart("sparkline", values: "{{memory.history}}", color: "purple", height: 36, extra: ["yMin": 0, "yMax": 1]),
            .labeled("Used", "{{memory.usedBytes | bytes}}"),
            .labeled("Available", "{{memory.availableBytes | bytes}}"),
            .labeled("Pressure", "{{memory.pressure}}"),
        ]),
        dataSources: [.metric("memory")], permissions: metrics)

    static let networkMonitor = WidgetDefinition(
        name: "Network Monitor", summary: "Upload and download speed, interface and address.", category: "System", symbol: "network",
        size: WidgetSize(280, 200),
        root: .column(spacing: 8, [
            .title("Network", symbol: "network"),
            .row([
                .column(spacing: 2, [.row(spacing: 4, [.icon("arrow.down", size: 11, color: "green"), .text("Download", size: 11, color: "secondary")]),
                                     .text("{{network.downBytesPerSec | rate}}", size: 17, weight: "semibold", design: "rounded")]),
                .spacer,
                .column(spacing: 2, [.row(spacing: 4, [.icon("arrow.up", size: 11, color: "orange"), .text("Upload", size: 11, color: "secondary")]),
                                     .text("{{network.upBytesPerSec | rate}}", size: 17, weight: "semibold", design: "rounded")]),
            ]),
            .chart("area", values: "{{network.downHistory}}", color: "green", height: 44),
            .labeled("Interface", "{{network.primaryInterface | default:–}}"),
            .labeled("Address", "{{network.address | default:Not connected}}"),
        ]),
        dataSources: [.metric("network")], permissions: metrics)

    static let batteryDashboard = WidgetDefinition(
        name: "Battery Dashboard", summary: "Charge level, power source, time remaining and history.", category: "System",
        symbol: "battery.75percent", size: WidgetSize(260, 190),
        root: .column(spacing: 8, [
            .row([.title("Battery", symbol: "battery.75percent"), .text("{{battery.level | percent}}", size: 22, weight: "semibold", design: "rounded")]),
            WidgetNode(.progress, props: ["value": "{{battery.level}}", "tint": "green",
                                          "visibleWhen": ["path": "battery.present", "op": "==", "value": true]]),
            .labeled("Power source", "{{battery.source}}"),
            .labeled("Charging", "{{battery.charging | yesno}}"),
            .labeled("Time remaining", "{{battery.minutesRemaining | mul:60 | duration}}"),
            .chart("sparkline", values: "{{battery.history}}", color: "green", height: 30,
                   extra: ["yMin": 0, "yMax": 1, "visibleWhen": ["path": "battery.present", "op": "==", "value": true]]),
            WidgetNode(.text, props: ["value": "This Mac has no internal battery.", "fontSize": 11, "color": "secondary",
                                      "visibleWhen": ["path": "battery.present", "op": "==", "value": false]]),
        ]),
        dataSources: [.metric("battery", interval: 30)], permissions: metrics)

    static let diskMonitor = WidgetDefinition(
        name: "Disk Monitor", summary: "Space used and free on the startup volume, plus read/write activity.", category: "System",
        symbol: "internaldrive", size: WidgetSize(260, 180),
        root: .column(spacing: 8, [
            .row([.title("{{storage.volume | default:Storage}}", symbol: "internaldrive"), .text("{{storage.usage | percent}}", size: 22, weight: "semibold", design: "rounded")]),
            .progress("{{storage.usage}}", tint: "orange"),
            .labeled("Used", "{{storage.usedBytes | bytes}}"),
            .labeled("Free", "{{storage.freeBytes | bytes}}"),
            .labeled("Read", "{{storage.readBytesPerSec | rate}}"),
            .labeled("Write", "{{storage.writeBytesPerSec | rate}}"),
        ]),
        dataSources: [.metric("storage", interval: 5)], permissions: metrics)

    static let multiMetric = WidgetDefinition(
        name: "Multi-Metric Dashboard", summary: "CPU, memory, disk, battery, network and uptime at a glance.", category: "System",
        symbol: "gauge.with.dots.needle.bottom.50percent", size: WidgetSize(360, 250),
        root: .column(spacing: 10, [
            .title("{{system.hostname}}", symbol: "desktopcomputer"),
            .row(spacing: 12, [
                .gauge("{{cpu.usage}}", label: "CPU", valueLabel: "{{cpu.usage | percent}}", tint: "blue"),
                .gauge("{{memory.usage}}", label: "RAM", valueLabel: "{{memory.usage | percent}}", tint: "purple"),
                .gauge("{{storage.usage}}", label: "Disk", valueLabel: "{{storage.usage | percent}}", tint: "orange"),
                .gauge("{{battery.level}}", label: "Battery", valueLabel: "{{battery.level | percent}}", tint: "green"),
            ]),
            .chart("line", values: "{{cpu.history}}", color: "blue", height: 44, extra: ["yMin": 0, "yMax": 1]),
            .row([.labeled("↓", "{{network.downBytesPerSec | rate}}"), .labeled("↑", "{{network.upBytesPerSec | rate}}")]),
            .row([.labeled("Uptime", "{{system.uptimeSeconds | duration}}"), .labeled("OS", "{{system.osVersion}}")]),
            .labeled("Processor", "{{system.processor}} ({{system.architecture}})"),
        ]),
        dataSources: [.metric("cpu"), .metric("memory"), .metric("storage", interval: 10), .metric("battery", interval: 30),
                      .metric("network"), .metric("system", interval: 30)],
        permissions: metrics)

    // MARK: Online data

    static let weather = WidgetDefinition(
        name: "Weather", summary: "Current conditions and today's range from Open-Meteo (no account needed).", category: "Online",
        symbol: "cloud.sun", size: WidgetSize(240, 150),
        root: .column(spacing: 6, [
            WidgetNode(.weather, props: ["temperature": "{{weather.current.temperature_2m}}", "code": "{{weather.current.weather_code}}",
                                         "high": "{{weather.daily.temperature_2m_max[0]}}", "low": "{{weather.daily.temperature_2m_min[0]}}",
                                         "location": "{{settings.location}}", "unit": "{{weather.current_units.temperature_2m}}"]),
            .labeled("Wind", "{{weather.current.wind_speed_10m | round:0 | default:–}} {{weather.current_units.wind_speed_10m}}"),
            .labeled("Humidity", "{{weather.current.relative_humidity_2m | default:–}}{{weather.current_units.relative_humidity_2m}}"),
            .statusNote(source: "weather"),
        ]),
        dataSources: [DataSourceConfig(
            id: "weather", name: "Open-Meteo forecast", kind: .rest,
            url: "https://api.open-meteo.com/v1/forecast?latitude={{settings.latitude}}&longitude={{settings.longitude}}&current=temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m&daily=temperature_2m_max,temperature_2m_min&timezone=auto",
            interval: 900, cacheTTL: 600, requiredPaths: ["current.temperature_2m"])],
        permissions: PermissionManifest(network: ["api.open-meteo.com"]),
        settings: ["location": "", "latitude": "", "longitude": ""],
        setupInstructions: "Enter a location name plus its latitude and longitude (for example 37.77 and -122.42) in the widget's settings. Data comes from api.open-meteo.com; no API key is required.")

    private static func quoteRow(_ index: Int) -> WidgetNode {
        .row([
            .text("{{settings.symbol\(index)}}", size: 13, weight: "semibold"),
            .spacer,
            .text("{{quote\(index).c | currency}}", size: 13, weight: "medium", design: "rounded", lineLimit: 1),
            .text("{{quote\(index).dp | signed:2}}%", size: 11, color: "secondary", design: "rounded", lineLimit: 1),
        ])
    }

    private static func quoteSource(_ index: Int) -> DataSourceConfig {
        DataSourceConfig(id: "quote\(index)", name: "Quote \(index)", kind: .rest,
                         url: "https://finnhub.io/api/v1/quote?symbol={{settings.symbol\(index)}}&token={{secret:FINNHUB_API_KEY}}",
                         interval: 120, cacheTTL: 60, requiredPaths: ["c"])
    }

    static let stocks = WidgetDefinition(
        name: "Stock Watchlist", summary: "Latest price and daily change for three symbols (Finnhub).", category: "Online",
        symbol: "chart.line.uptrend.xyaxis", size: WidgetSize(260, 150),
        root: .column(spacing: 8, [.title("Stocks", symbol: "chart.line.uptrend.xyaxis"), quoteRow(1), quoteRow(2), quoteRow(3), .statusNote(source: "quote1")]),
        dataSources: [quoteSource(1), quoteSource(2), quoteSource(3)],
        permissions: PermissionManifest(network: ["finnhub.io"]),
        settings: ["symbol1": "AAPL", "symbol2": "MSFT", "symbol3": "NVDA"],
        setupInstructions: "Requires a free Finnhub API key. Create one at finnhub.io, then add it in Settings → Secrets with the name FINNHUB_API_KEY and the host finnhub.io. Until then the widget shows a setup notice instead of prices.")

    private static func coinRow(_ id: String, _ label: String) -> WidgetNode {
        .row([
            .text(label, size: 13, weight: "semibold"),
            .spacer,
            .text("{{crypto.\(id).usd | currency}}", size: 13, weight: "medium", design: "rounded", lineLimit: 1),
            .text("{{crypto.\(id).usd_24h_change | signed:1}}%", size: 11, color: "secondary", design: "rounded", lineLimit: 1),
        ])
    }

    static let crypto = WidgetDefinition(
        name: "Cryptocurrency Watchlist", summary: "Bitcoin, Ethereum and Solana prices from CoinGecko's public API.", category: "Online",
        symbol: "bitcoinsign.circle", size: WidgetSize(260, 150),
        root: .column(spacing: 8, [.title("Crypto", symbol: "bitcoinsign.circle"), coinRow("bitcoin", "BTC"), coinRow("ethereum", "ETH"),
                                   coinRow("solana", "SOL"), .statusNote(source: "crypto")]),
        dataSources: [DataSourceConfig(id: "crypto", name: "CoinGecko prices", kind: .rest,
                                       url: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd&include_24hr_change=true",
                                       interval: 180, cacheTTL: 120, requiredPaths: ["bitcoin.usd"])],
        permissions: PermissionManifest(network: ["api.coingecko.com"]),
        setupInstructions: "Works without an account. CoinGecko's public API is rate limited, so prices refresh every three minutes.")

    static let githubActivity = WidgetDefinition(
        name: "GitHub Activity", summary: "Recent public events for a GitHub user.", category: "Online", symbol: "chevron.left.forwardslash.chevron.right",
        size: WidgetSize(300, 220),
        root: .column(spacing: 8, [
            .title("{{settings.username | default:GitHub}}", symbol: "person.crop.circle"),
            WidgetNode(.list, props: ["items": "{{github}}", "titlePath": "repo.name", "subtitlePath": "type", "trailingPath": "created_at | relative",
                                      "limit": 5, "emptyText": "No recent public activity"]),
            .statusNote(source: "github"),
        ]),
        dataSources: [DataSourceConfig(id: "github", name: "GitHub events", kind: .rest,
                                       url: "https://api.github.com/users/{{settings.username}}/events/public?per_page=10",
                                       headers: ["Accept": "application/vnd.github+json"], interval: 300, cacheTTL: 240)],
        permissions: PermissionManifest(network: ["api.github.com"]),
        settings: ["username": ""],
        setupInstructions: "Enter a GitHub username in the widget's settings. Unauthenticated requests are limited to 60 per hour by GitHub; the widget refreshes every five minutes.")

    private static func endpointRow(_ index: Int) -> WidgetNode {
        .row([
            WidgetNode(.icon, props: ["symbol": "circle.fill", "size": 9, "color": "green",
                                      "visibleWhen": ["path": .string("sources.endpoint\(index).state"), "op": "==", "value": "ok"]]),
            WidgetNode(.icon, props: ["symbol": "circle.fill", "size": 9, "color": "red",
                                      "visibleWhen": ["path": .string("sources.endpoint\(index).state"), "op": "==", "value": "failed"]]),
            WidgetNode(.icon, props: ["symbol": "circle.fill", "size": 9, "color": "orange",
                                      "visibleWhen": ["path": .string("sources.endpoint\(index).state"), "op": "==", "value": "stale"]]),
            .text("{{settings.name\(index)}}", size: 12, weight: "medium", lineLimit: 1),
            .spacer,
            .text("{{sources.endpoint\(index).label}}", size: 11, color: "secondary"),
        ])
    }

    static let apiStatus = WidgetDefinition(
        name: "API Status Monitor", summary: "Checks up to three HTTP endpoints and shows whether each responds.", category: "Online",
        symbol: "checkmark.icloud", size: WidgetSize(280, 150),
        root: .column(spacing: 8, [.title("API Status", symbol: "checkmark.icloud"), endpointRow(1), endpointRow(2), endpointRow(3)]),
        dataSources: (1...3).map { DataSourceConfig(id: "endpoint\($0)", name: "Endpoint \($0)", kind: .rest, url: "{{settings.url\($0)}}",
                                                    interval: 60, retry: .none, timeout: 10) },
        settings: ["name1": "Endpoint 1", "url1": "", "name2": "Endpoint 2", "url2": "", "name3": "Endpoint 3", "url3": ""],
        setupInstructions: "Enter up to three https:// URLs and display names in the widget's settings. Each host you enter is added to this widget's network allowlist. An endpoint counts as up when it answers with a 2xx status.")

    static let serverHealth = WidgetDefinition(
        name: "Server Health Dashboard", summary: "Displays cpu, memory and disk figures from your own JSON health endpoint.", category: "Online",
        symbol: "server.rack", size: WidgetSize(280, 200),
        root: .column(spacing: 8, [
            .row([.title("{{settings.name}}", symbol: "server.rack"), .text("{{health.status | default:–}}", size: 12, weight: "semibold", color: "green")]),
            .progress("{{health.cpu}}", label: "CPU", valueLabel: "{{health.cpu | percent}}", tint: "blue"),
            .progress("{{health.memory}}", label: "Memory", valueLabel: "{{health.memory | percent}}", tint: "purple"),
            .progress("{{health.disk}}", label: "Disk", valueLabel: "{{health.disk | percent}}", tint: "orange"),
            .statusNote(source: "health"),
        ]),
        dataSources: [DataSourceConfig(id: "health", name: "Health endpoint", kind: .rest, url: "{{settings.url}}", interval: 30)],
        settings: ["name": "Server", "url": ""],
        setupInstructions: "Point the widget at an endpoint you run that returns JSON like {\"status\": \"ok\", \"cpu\": 0.42, \"memory\": 0.61, \"disk\": 0.30} (fractions from 0 to 1). If it needs a token, add a header with a {{secret:NAME}} placeholder in Data Sources.")

    static let customREST = WidgetDefinition(
        name: "Custom REST API", summary: "Shows the JSON returned by any endpoint. A starting point for your own API widgets.", category: "Developer",
        symbol: "curlybraces", size: WidgetSize(320, 220),
        root: .column(spacing: 8, [
            .row([.title("{{settings.title}}", symbol: "curlybraces"), .button("", symbol: "arrow.clockwise", action: .refresh, style: "plain")]),
            WidgetNode(.apiViewer, props: ["value": "{{api}}", "source": "api"]),
        ]),
        dataSources: [DataSourceConfig(id: "api", name: "Endpoint", kind: .rest, url: "{{settings.url}}", interval: 120)],
        settings: ["title": "REST API", "url": ""],
        setupInstructions: "Enter the endpoint URL in the widget's settings, then open the widget in the Builder to bind individual fields with {{api.path.to.value}}.")

    static let customScript = WidgetDefinition(
        name: "Custom JavaScript", summary: "A scripted system monitor showing the WidgetForge SDK in action.", category: "Developer",
        symbol: "chevron.left.forwardslash.chevron.right", size: WidgetSize(320, 220),
        root: WidgetNode(.script),
        permissions: PermissionManifest(systemMetrics: true, scripting: true),
        script: """
        WidgetForge.defineWidget({
          id: "system-monitor",
          name: "System Monitor",
          size: { width: 320, height: 220 },
          interval: 2,

          async update(context, state) {
            const cpu = await context.system.cpu();
            const memory = await context.system.memory();
            const history = (state.history || []).concat([cpu]).slice(-40);
            return { cpu, memory, history };
          },

          render(state) {
            const pct = (v) => v == null ? "–" : Math.round(v * 100) + "%";
            return {
              type: "column", spacing: 8,
              children: [
                { type: "text", value: "System Monitor", fontSize: 12, fontWeight: "semibold", color: "secondary" },
                { type: "progress", value: state.cpu || 0, label: "CPU", valueLabel: pct(state.cpu) },
                { type: "progress", value: state.memory || 0, label: "Memory", valueLabel: pct(state.memory), tint: "purple" },
                { type: "chart", chartKind: "area", values: state.history || [], height: 60, yMin: 0, yMax: 1 }
              ]
            };
          }
        });
        """,
        setupInstructions: "Edit the script in the Builder's Script tab. Scripts run in a restricted JavaScript runtime and can only use the permissions shown for this widget. See docs/SDK.md.")

    // MARK: Productivity

    static let notes = WidgetDefinition(
        name: "Notes", summary: "A sticky note that saves as you type.", category: "Productivity", symbol: "note.text",
        size: WidgetSize(260, 200),
        root: .column(spacing: 6, [
            .title("Notes", symbol: "note.text"),
            WidgetNode(.input, props: ["bind": "text", "placeholder": "Write something…", "multiline": true, "fontSize": 13]),
        ]),
        initialState: ["text": ""])

    static let todo = WidgetDefinition(
        name: "To-do List", summary: "Add, tick off and remove tasks.", category: "Productivity", symbol: "checklist",
        size: WidgetSize(260, 240),
        root: .column(spacing: 6, [.title("To-do", symbol: "checklist"), WidgetNode(.todo, props: ["bind": "items", "placeholder": "New task"])]),
        initialState: ["items": []])

    static let clipboard = WidgetDefinition(
        name: "Clipboard Utility", summary: "Save the current clipboard into a short list and copy items back with a click.", category: "Productivity",
        symbol: "doc.on.clipboard", size: WidgetSize(260, 220),
        root: .column(spacing: 6, [.title("Clipboard", symbol: "doc.on.clipboard"), WidgetNode(.clipboard, props: ["bind": "clips", "limit": 6])]),
        permissions: PermissionManifest(clipboard: true),
        initialState: ["clips": []],
        setupInstructions: "The clipboard is read only when you press “Save Clipboard”; it is never monitored in the background.")

    static let habitTracker = WidgetDefinition(
        name: "Habit Tracker", summary: "Tick off daily habits and keep a seven-day streak view.", category: "Productivity", symbol: "flame",
        size: WidgetSize(300, 190),
        root: .column(spacing: 6, [.title("Habits", symbol: "flame"),
                                   WidgetNode(.habits, props: ["bind": "habits", "habits": "{{settings.habits}}"])]),
        settings: ["habits": ["Read", "Exercise", "Meditate"]],
        initialState: ["habits": [:]],
        setupInstructions: "Edit the list of habits in the widget's settings.")

    static let mediaControls = WidgetDefinition(
        name: "Media Controls", summary: "Previous, play/pause and next for the Music app.", category: "Productivity", symbol: "playpause",
        size: WidgetSize(220, 90),
        root: .column(spacing: 6, alignment: "center", [.title("Music", symbol: "music.note"), WidgetNode(.media)]),
        permissions: PermissionManifest(mediaControl: true),
        setupInstructions: "Controls Apple Music through Apple Events. macOS asks for permission the first time you press a button. Other players are not supported: macOS has no public API for system-wide media control.")

    private static func shortcutButton(_ index: Int) -> WidgetNode {
        .button("{{settings.shortcut\(index)}}", symbol: "bolt.fill", action: .runShortcut("{{settings.shortcut\(index)}}"))
            .with("visibleWhen", ["path": .string("settings.shortcut\(index)"), "op": "!=", "value": ""])
    }

    static let shortcutLauncher = WidgetDefinition(
        name: "Shortcut Launcher", summary: "Buttons that run your macOS Shortcuts by name.", category: "Productivity", symbol: "bolt.square",
        size: WidgetSize(240, 170),
        root: .column(spacing: 8, [
            .title("Shortcuts", symbol: "bolt.square"),
            shortcutButton(1), shortcutButton(2), shortcutButton(3),
            WidgetNode(.text, props: ["value": "Add shortcut names in this widget's settings.", "fontSize": 11, "color": "secondary",
                                      "visibleWhen": ["path": "settings.shortcut1", "op": "==", "value": ""]]),
        ]),
        permissions: PermissionManifest(shortcuts: true),
        settings: ["shortcut1": "", "shortcut2": "", "shortcut3": ""],
        setupInstructions: "Type the exact names of up to three shortcuts from the Shortcuts app into the widget's settings.")
}
