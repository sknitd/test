import Foundation

enum PermissionError: Error, LocalizedError, Equatable {
    case hostNotAllowed(String)
    case capabilityDenied(String)
    case fileNotAuthorized(String)

    var errorDescription: String? {
        switch self {
        case .hostNotAllowed(let host): return "Network access to \(host) is not in this widget's allowlist"
        case .capabilityDenied(let name): return "This widget does not have the \"\(name)\" permission"
        case .fileNotAuthorized(let id): return "File \(id) has not been authorised for this widget"
        }
    }
}

enum PermissionChecker {
    /// Hosts that must never be reached implicitly; they need an exact allowlist entry (no wildcards).
    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h.hasSuffix(".local") || h == "::1" || h.hasPrefix("127.") || h.hasPrefix("10.")
            || h.hasPrefix("192.168.") || h.hasPrefix("169.254.") || h == "0.0.0.0"
            || (h.hasPrefix("172.") && (Int(h.split(separator: ".").dropFirst().first ?? "") ?? 0).isBetween(16, 31))
    }

    /// `allowlist` entries are exact hosts ("api.github.com") or leading-wildcard domains ("*.github.com").
    static func hostAllowed(_ host: String, allowlist: [String]) -> Bool {
        let h = host.lowercased()
        guard !h.isEmpty else { return false }
        for entry in allowlist.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) {
            if entry == h { return true }
            if entry.hasPrefix("*."), !isLocal(h) {
                let suffix = String(entry.dropFirst(1))          // ".github.com"
                if h.hasSuffix(suffix), h.count > suffix.count { return true }
            }
        }
        return false
    }

    static func checkURL(_ url: URL, allowlist: [String]) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "ws", "wss"].contains(scheme) else {
            throw PermissionError.hostNotAllowed(url.absoluteString)
        }
        guard let host = url.host, hostAllowed(host, allowlist: allowlist) else {
            throw PermissionError.hostNotAllowed(url.host ?? url.absoluteString)
        }
    }

    /// The minimum manifest a definition needs for everything in it to work, derived from its content.
    /// Used to pre-fill the manifest in the builder and to flag under-declared imports.
    static func required(for definition: WidgetDefinition) -> PermissionManifest {
        var m = PermissionManifest()
        var hosts = Set<String>()
        var files = Set<String>()
        for source in definition.dataSources {
            switch source.kind {
            case .rest, .webSocket, .localHTTP:
                if let host = hostTemplate(source.url, settings: definition.settings) { hosts.insert(host) }
            case .jsonFile, .csvFile:
                if let id = source.fileID { files.insert(id) }
            case .systemMetric: m.systemMetrics = true
            case .calendar: m.calendar = true
            case .time, .userData: break
            }
        }
        var web = Set<String>()
        for node in definition.root.flattened {
            switch node.type {
            case .metric: m.systemMetrics = true
            case .clipboard: m.clipboard = true
            case .media: m.mediaControl = true
            case .script: m.scripting = true
            case .calendar: if node.bool("showEvents") == true { m.calendar = true }
            case .web:
                if let host = hostTemplate(node.string("url"), settings: definition.settings) { web.insert(host) }
            case .image:
                if let url = node.string("url"), url.hasPrefix("http"), let host = hostTemplate(url, settings: definition.settings) { hosts.insert(host) }
            default: break
            }
            for key in ["action", "onChange"] {
                switch WidgetAction(json: node.props[key]) {
                case .openURL: m.openURLs = true
                case .runShortcut: m.shortcuts = true
                case .launchApp: m.launchApps = true
                case .media: m.mediaControl = true
                case .copy: m.clipboard = true
                case .script: m.scripting = true
                default: break
                }
            }
            if let items = node.props["items"]?.arrayValue {
                for item in items {
                    switch WidgetAction(json: item["action"]) {
                    case .openURL: m.openURLs = true
                    case .runShortcut: m.shortcuts = true
                    case .launchApp: m.launchApps = true
                    default: break
                    }
                }
            }
        }
        if definition.hasScript { m.scripting = true }
        m.network = hosts.sorted()
        m.files = files.sorted()
        m.webContent = web.sorted()
        return m
    }

    /// Capabilities in `required` that `granted` does not cover.
    static func missing(required: PermissionManifest, granted: PermissionManifest) -> PermissionManifest {
        PermissionManifest(
            network: required.network.filter { !hostAllowed($0, allowlist: granted.network) },
            systemMetrics: required.systemMetrics && !granted.systemMetrics,
            files: required.files.filter { !granted.files.contains($0) },
            clipboard: required.clipboard && !granted.clipboard,
            calendar: required.calendar && !granted.calendar,
            notifications: required.notifications && !granted.notifications,
            openURLs: required.openURLs && !granted.openURLs,
            shortcuts: required.shortcuts && !granted.shortcuts,
            launchApps: required.launchApps && !granted.launchApps,
            mediaControl: required.mediaControl && !granted.mediaControl,
            scripting: required.scripting && !granted.scripting,
            webContent: required.webContent.filter { !hostAllowed($0, allowlist: granted.webContent) })
    }

    /// Host of a URL that may still contain `{{settings.x}}` placeholders in its path or query.
    static func hostTemplate(_ url: String?, settings: [String: JSONValue]) -> String? {
        guard let url, !url.isEmpty else { return nil }
        let resolved = TemplateRenderer.render(url.replacingOccurrences(of: "{{secret:", with: "{{secret."),
                                               context: ["settings": .object(settings)])
        return URLComponents(string: resolved.replacingOccurrences(of: " ", with: "%20"))?.host?.lowercased()
    }
}

private extension Int {
    func isBetween(_ a: Int, _ b: Int) -> Bool { self >= a && self <= b }
}
