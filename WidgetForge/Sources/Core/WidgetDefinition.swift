import Foundation

struct WidgetSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double
    init(width: Double, height: Double) { self.width = width; self.height = height }
    init(_ width: Double, _ height: Double) { self.width = width; self.height = height }
}

enum WidgetAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// Visual chrome of the widget container.
struct WidgetStyle: Codable, Hashable, Sendable {
    /// "material" (translucent system material), "clear", or a hex colour such as "#1C1C1EE6".
    var background: String = "material"
    var cornerRadius: Double = 20
    var padding: Double = 14
    var borderColor: String? = nil
    var borderWidth: Double = 0
    var shadowRadius: Double = 10
    /// Accent colour for progress bars, charts and gauges (hex or a system colour name).
    var tint: String = "accent"

    init(background: String = "material", cornerRadius: Double = 20, padding: Double = 14, borderColor: String? = nil,
         borderWidth: Double = 0, shadowRadius: Double = 10, tint: String = "accent") {
        self.background = background; self.cornerRadius = cornerRadius; self.padding = padding
        self.borderColor = borderColor; self.borderWidth = borderWidth; self.shadowRadius = shadowRadius; self.tint = tint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? "material"
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 20
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 14
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor)
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
        shadowRadius = try c.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 10
        tint = try c.decodeIfPresent(String.self, forKey: .tint) ?? "accent"
    }
}

/// The capabilities a widget asks for. Nothing here is granted implicitly: the user approves a manifest
/// when a widget is installed, can revoke any part of it later, and every bridge call re-checks it.
struct PermissionManifest: Codable, Hashable, Sendable {
    /// Hosts the widget may contact, e.g. "api.github.com" or "*.example.com".
    var network: [String] = []
    var systemMetrics = false
    /// Identifiers of user-selected files (security-scoped bookmarks held by the app, never raw paths).
    var files: [String] = []
    var clipboard = false
    var calendar = false
    var notifications = false
    var openURLs = false
    var shortcuts = false
    var launchApps = false
    var mediaControl = false
    var scripting = false
    /// Hosts that may be shown in a Web Content component.
    var webContent: [String] = []

    static let none = PermissionManifest()

    init(network: [String] = [], systemMetrics: Bool = false, files: [String] = [], clipboard: Bool = false,
         calendar: Bool = false, notifications: Bool = false, openURLs: Bool = false, shortcuts: Bool = false,
         launchApps: Bool = false, mediaControl: Bool = false, scripting: Bool = false, webContent: [String] = []) {
        self.network = network; self.systemMetrics = systemMetrics; self.files = files; self.clipboard = clipboard
        self.calendar = calendar; self.notifications = notifications; self.openURLs = openURLs; self.shortcuts = shortcuts
        self.launchApps = launchApps; self.mediaControl = mediaControl; self.scripting = scripting; self.webContent = webContent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        network = try c.decodeIfPresent([String].self, forKey: .network) ?? []
        systemMetrics = try c.decodeIfPresent(Bool.self, forKey: .systemMetrics) ?? false
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        clipboard = try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? false
        calendar = try c.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? false
        openURLs = try c.decodeIfPresent(Bool.self, forKey: .openURLs) ?? false
        shortcuts = try c.decodeIfPresent(Bool.self, forKey: .shortcuts) ?? false
        launchApps = try c.decodeIfPresent(Bool.self, forKey: .launchApps) ?? false
        mediaControl = try c.decodeIfPresent(Bool.self, forKey: .mediaControl) ?? false
        scripting = try c.decodeIfPresent(Bool.self, forKey: .scripting) ?? false
        webContent = try c.decodeIfPresent([String].self, forKey: .webContent) ?? []
    }

    var isEmpty: Bool { self == .none }

    /// Human-readable lines for the approval sheet.
    var descriptions: [String] {
        var out: [String] = []
        if !network.isEmpty { out.append("Connect to: " + network.sorted().joined(separator: ", ")) }
        if !webContent.isEmpty { out.append("Display web pages from: " + webContent.sorted().joined(separator: ", ")) }
        if systemMetrics { out.append("Read system metrics (CPU, memory, disk, network, battery)") }
        if !files.isEmpty { out.append("Read \(files.count) file(s) you select") }
        if clipboard { out.append("Read and write the clipboard when you click its controls") }
        if calendar { out.append("Read your calendar events") }
        if notifications { out.append("Show notifications") }
        if openURLs { out.append("Open links in your browser") }
        if shortcuts { out.append("Run macOS Shortcuts you name") }
        if launchApps { out.append("Launch applications") }
        if mediaControl { out.append("Control Music playback") }
        if scripting { out.append("Run its bundled JavaScript inside the restricted WidgetForge runtime") }
        return out
    }

    /// Only what both manifests allow.
    func intersection(_ other: PermissionManifest) -> PermissionManifest {
        PermissionManifest(
            network: network.filter { other.network.contains($0) },
            systemMetrics: systemMetrics && other.systemMetrics,
            files: files.filter { other.files.contains($0) },
            clipboard: clipboard && other.clipboard,
            calendar: calendar && other.calendar,
            notifications: notifications && other.notifications,
            openURLs: openURLs && other.openURLs,
            shortcuts: shortcuts && other.shortcuts,
            launchApps: launchApps && other.launchApps,
            mediaControl: mediaControl && other.mediaControl,
            scripting: scripting && other.scripting,
            webContent: webContent.filter { other.webContent.contains($0) })
    }

    func union(_ other: PermissionManifest) -> PermissionManifest {
        PermissionManifest(
            network: Array(Set(network + other.network)).sorted(),
            systemMetrics: systemMetrics || other.systemMetrics,
            files: Array(Set(files + other.files)).sorted(),
            clipboard: clipboard || other.clipboard,
            calendar: calendar || other.calendar,
            notifications: notifications || other.notifications,
            openURLs: openURLs || other.openURLs,
            shortcuts: shortcuts || other.shortcuts,
            launchApps: launchApps || other.launchApps,
            mediaControl: mediaControl || other.mediaControl,
            scripting: scripting || other.scripting,
            webContent: Array(Set(webContent + other.webContent)).sorted())
    }
}

/// A complete, shareable description of a widget: layout, data, permissions and (optionally) a script.
struct WidgetDefinition: Codable, Hashable, Identifiable, Sendable {
    static let currentFormatVersion = 1

    var id: String
    var name: String
    var summary: String
    var category: String
    var symbol: String
    var size: WidgetSize
    var root: WidgetNode
    var dataSources: [DataSourceConfig]
    var permissions: PermissionManifest
    var style: WidgetStyle
    /// User-editable configuration, referenced as `{{settings.key}}`.
    var settings: [String: JSONValue]
    var initialState: [String: JSONValue]
    /// Optional JavaScript source using the WidgetForge SDK. Never runs unless the instance is trusted.
    var script: String?
    /// Shown when the widget needs configuration (API keys, usernames, endpoints) before it can show data.
    var setupInstructions: String?
    var formatVersion: Int

    init(id: String = UUID().uuidString, name: String, summary: String = "", category: String = "Custom",
         symbol: String = "square.grid.2x2", size: WidgetSize, root: WidgetNode, dataSources: [DataSourceConfig] = [],
         permissions: PermissionManifest = .none, style: WidgetStyle = WidgetStyle(), settings: [String: JSONValue] = [:],
         initialState: [String: JSONValue] = [:], script: String? = nil, setupInstructions: String? = nil) {
        self.id = id; self.name = name; self.summary = summary; self.category = category; self.symbol = symbol
        self.size = size; self.root = root; self.dataSources = dataSources; self.permissions = permissions
        self.style = style; self.settings = settings; self.initialState = initialState; self.script = script
        self.setupInstructions = setupInstructions; self.formatVersion = WidgetDefinition.currentFormatVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Custom"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        size = try c.decodeIfPresent(WidgetSize.self, forKey: .size) ?? WidgetSize(320, 200)
        root = try c.decode(WidgetNode.self, forKey: .root)
        dataSources = try c.decodeIfPresent([DataSourceConfig].self, forKey: .dataSources) ?? []
        permissions = try c.decodeIfPresent(PermissionManifest.self, forKey: .permissions) ?? .none
        style = try c.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? WidgetStyle()
        settings = try c.decodeIfPresent([String: JSONValue].self, forKey: .settings) ?? [:]
        initialState = try c.decodeIfPresent([String: JSONValue].self, forKey: .initialState) ?? [:]
        script = try c.decodeIfPresent(String.self, forKey: .script)
        setupInstructions = try c.decodeIfPresent(String.self, forKey: .setupInstructions)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
    }

    var hasScript: Bool { !(script ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Where a widget sits. Coordinates are relative to the top-left of its display's visible frame so a
/// layout survives resolution changes and display rearrangement.
struct Placement: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var displayID: String?

    var rect: Rect { Rect(x: x, y: y, width: width, height: height) }
}

/// Which window layer an overlay widget lives on.
enum WidgetLayer: String, Codable, CaseIterable, Sendable {
    /// Just above the desktop icons, below every application window. The default.
    case desktop
    /// Floats above normal windows ("pinned").
    case floating
}

enum WidgetOrigin: String, Codable, Sendable {
    case template, builder, imported, ai, script
}

/// A widget the user has placed on their desktop.
struct WidgetInstance: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var definition: WidgetDefinition
    var placement: Placement
    var locked = false
    var pinned = false
    var hidden = false
    var clickThrough = false
    var opacity = 1.0
    var appearance = WidgetAppearance.system
    var groupID: String?
    /// Persistent user state (note text, to-do items, timer state…), referenced as `{{state.key}}`.
    var state: [String: JSONValue]
    /// What the user has actually approved. Effective permissions are `definition.permissions ∩ granted`.
    var granted: PermissionManifest
    /// Scripts in imported or AI-generated widgets stay disabled until the user explicitly trusts them.
    var scriptTrusted = false
    var origin = WidgetOrigin.template
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, definition: WidgetDefinition, placement: Placement,
         granted: PermissionManifest = .none, origin: WidgetOrigin = .template, scriptTrusted: Bool = false, now: Date = Date()) {
        self.id = id; self.definition = definition; self.placement = placement
        self.state = definition.initialState; self.granted = granted; self.origin = origin
        self.scriptTrusted = scriptTrusted; self.createdAt = now; self.updatedAt = now
    }

    var name: String { definition.name }
    var layer: WidgetLayer { pinned ? .floating : .desktop }
    var effectivePermissions: PermissionManifest { definition.permissions.intersection(granted) }
    var scriptEnabled: Bool { definition.hasScript && scriptTrusted && effectivePermissions.scripting }
}

struct SavedLayout: Codable, Hashable, Identifiable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var placement: Placement
        var hidden: Bool
    }
    var id: String = UUID().uuidString
    var name: String
    var entries: [String: Entry]   // widget id -> placement
    var savedAt: Date = Date()
}
