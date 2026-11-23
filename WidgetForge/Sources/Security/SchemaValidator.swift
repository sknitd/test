import Foundation

struct ValidationReport: Equatable, Sendable {
    var errors: [String] = []
    var warnings: [String] = []
    var isValid: Bool { errors.isEmpty }
}

/// Structural validation of widget definitions that come from outside the app (imports, AI output,
/// script `render()` results). Validation runs on raw JSON *before* anything is decoded or displayed.
enum SchemaValidator {
    struct Limits: Sendable {
        var maxNodes = 400
        var maxDepth = 12
        var maxStringLength = 20_000
        var maxScriptLength = 200_000
        var maxDataSources = 24
        var maxBytes = 1_000_000
        var minSize = 60.0
        var maxSize = 2400.0
    }

    static let allowedSchemes: Set<String> = ["http", "https", "ws", "wss"]

    static func validate(definition json: JSONValue, limits: Limits = Limits()) -> ValidationReport {
        var report = ValidationReport()
        guard let object = json.objectValue else {
            report.errors.append("The widget definition must be a JSON object")
            return report
        }
        if json.compactJSONString.utf8.count > limits.maxBytes { report.errors.append("The definition is larger than \(limits.maxBytes / 1000) KB") }
        guard let name = object["name"]?.stringValue, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            report.errors.append("The widget needs a \"name\"")
            return report
        }
        if name.count > 80 { report.errors.append("The widget name is longer than 80 characters") }

        if let size = object["size"] {
            let w = size["width"]?.doubleValue, h = size["height"]?.doubleValue
            if let w, let h {
                if w < limits.minSize || h < limits.minSize || w > limits.maxSize || h > limits.maxSize {
                    report.errors.append("Widget size \(Int(w))×\(Int(h)) is outside \(Int(limits.minSize))–\(Int(limits.maxSize)) points")
                }
            } else {
                report.errors.append("\"size\" needs numeric width and height")
            }
        }

        if let root = object["root"] {
            var count = 0
            validate(node: root, path: "root", depth: 1, count: &count, limits: limits, report: &report)
            if count > limits.maxNodes { report.errors.append("The layout has \(count) components; the limit is \(limits.maxNodes)") }
        } else {
            report.errors.append("The widget needs a \"root\" component")
        }

        if let sources = object["dataSources"] {
            guard let list = sources.arrayValue else {
                report.errors.append("\"dataSources\" must be an array")
                return report
            }
            if list.count > limits.maxDataSources { report.errors.append("More than \(limits.maxDataSources) data sources") }
            var seen = Set<String>()
            for (i, source) in list.enumerated() { validate(source: source, index: i, seen: &seen, report: &report) }
        }

        if let script = object["script"]?.stringValue, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if script.utf8.count > limits.maxScriptLength { report.errors.append("The script is larger than \(limits.maxScriptLength / 1000) KB") }
            report.warnings.append("Contains JavaScript. It stays disabled until you review and trust it.")
        }

        if report.isValid, let definition = try? json.decode(WidgetDefinition.self) {
            let missing = PermissionChecker.missing(required: PermissionChecker.required(for: definition), granted: definition.permissions)
            if !missing.isEmpty {
                report.warnings.append("Uses capabilities it does not declare (" + missing.descriptions.joined(separator: "; ") + "). Those parts will not work unless you add the permissions.")
            }
        } else if report.isValid {
            report.errors.append("The definition could not be decoded")
        }
        return report
    }

    static func validate(node json: JSONValue, path: String, depth: Int, count: inout Int, limits: Limits, report: inout ValidationReport) {
        count += 1
        guard count <= limits.maxNodes + 1 else { return }
        guard let object = json.objectValue else {
            report.errors.append("\(path): a component must be an object")
            return
        }
        if depth > limits.maxDepth {
            report.errors.append("\(path): nesting is deeper than \(limits.maxDepth) levels")
            return
        }
        guard let typeName = object["type"]?.stringValue else {
            report.errors.append("\(path): missing \"type\"")
            return
        }
        guard let type = NodeType(rawValue: typeName) else {
            report.errors.append("\(path): unknown component type \"\(typeName)\"")
            return
        }
        var props = object["props"]?.objectValue ?? [:]
        for (key, value) in object where !["id", "type", "props", "children", "frame", "constraints", "groupID"].contains(key) { props[key] = value }

        for (key, value) in props {
            if let s = value.stringValue, s.utf8.count > limits.maxStringLength {
                report.errors.append("\(path).\(key): text is longer than \(limits.maxStringLength) bytes")
            }
            if key == "url" || key == "src", let s = value.stringValue, !s.isEmpty, !s.contains("{{") || s.contains("://") {
                checkURL(s, at: "\(path).\(key)", report: &report)
            }
            if key == "action" || key == "onChange" {
                if let actionType = value["type"]?.stringValue {
                    if !WidgetAction.typeNames.contains(actionType) { report.errors.append("\(path).\(key): unknown action \"\(actionType)\"") }
                    if actionType == "openURL", let u = value["url"]?.stringValue { checkURL(u, at: "\(path).\(key).url", report: &report, extraSchemes: ["mailto"]) }
                } else if !value.isNull {
                    report.errors.append("\(path).\(key): an action must be an object with a \"type\"")
                }
            }
        }
        if let frame = object["frame"], !frame.isNull {
            let ok = ["x", "y", "width", "height"].allSatisfy { frame[$0]?.doubleValue?.isFinite == true }
            if !ok { report.errors.append("\(path).frame: needs finite x, y, width and height") }
        }
        if let children = object["children"] {
            guard let list = children.arrayValue else {
                report.errors.append("\(path).children must be an array")
                return
            }
            if !list.isEmpty, !type.isContainer { report.warnings.append("\(path): \(typeName) ignores its children") }
            for (i, child) in list.enumerated() {
                validate(node: child, path: "\(path).children[\(i)]", depth: depth + 1, count: &count, limits: limits, report: &report)
            }
        }
    }

    static func validate(source json: JSONValue, index: Int, seen: inout Set<String>, report: inout ValidationReport) {
        let path = "dataSources[\(index)]"
        guard let object = json.objectValue else {
            report.errors.append("\(path): must be an object")
            return
        }
        guard let id = object["id"]?.stringValue, !id.isEmpty else {
            report.errors.append("\(path): missing \"id\"")
            return
        }
        if ["state", "settings"].contains(id) { report.errors.append("\(path): \"\(id)\" is a reserved name") }
        if !seen.insert(id).inserted { report.errors.append("\(path): duplicate id \"\(id)\"") }
        guard let kindName = object["kind"]?.stringValue, let kind = DataSourceKind(rawValue: kindName) else {
            report.errors.append("\(path): unknown kind \"\(object["kind"]?.displayString ?? "")\"")
            return
        }
        if [.rest, .webSocket, .localHTTP].contains(kind) {
            guard let url = object["url"]?.stringValue, !url.isEmpty else {
                report.errors.append("\(path): needs a \"url\"")
                return
            }
            checkURL(url, at: "\(path).url", report: &report)
        }
        if let interval = object["interval"]?.doubleValue, interval < 0 { report.errors.append("\(path): interval cannot be negative") }
        if let headers = object["headers"]?.objectValue {
            for (name, value) in headers where SecretScrubber.isSensitiveName(name) {
                if let v = value.stringValue, !v.contains("{{secret:"), !v.isEmpty {
                    report.errors.append("\(path).headers.\(name): contains an inline credential. Use a {{secret:NAME}} placeholder instead.")
                }
            }
        }
    }

    static func checkURL(_ text: String, at path: String, report: inout ValidationReport, extraSchemes: Set<String> = []) {
        // A URL taken wholly from a user setting is resolved (and allowlist-checked) at request time.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{{settings."), trimmed.hasSuffix("}}"), !trimmed.dropFirst(2).contains("{{") { return }
        // Otherwise placeholders are allowed in the path and query, never in the scheme or host.
        guard let schemeEnd = text.range(of: "://") else {
            if let colon = text.firstIndex(of: ":"), extraSchemes.contains(String(text[..<colon]).lowercased()) { return }
            report.errors.append("\(path): \"\(text.prefix(60))\" is not an absolute URL")
            return
        }
        let scheme = text[..<schemeEnd.lowerBound].lowercased()
        guard allowedSchemes.contains(scheme) || extraSchemes.contains(scheme) else {
            report.errors.append("\(path): the \(scheme): scheme is not allowed")
            return
        }
        let afterScheme = text[schemeEnd.upperBound...]
        let authority = afterScheme.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if authority.isEmpty { report.errors.append("\(path): missing host") }
        if authority.contains("{{") { report.errors.append("\(path): the host cannot be a placeholder") }
        if authority.contains("@") { report.errors.append("\(path): credentials in URLs are not allowed") }
        if scheme == "http" || scheme == "ws" {
            let host = authority.split(separator: ":").first.map(String.init) ?? ""
            if !PermissionChecker.isLocal(host) { report.warnings.append("\(path): uses unencrypted \(scheme)") }
        }
    }
}

/// Removes anything that looks like a credential before a definition leaves the app.
enum SecretScrubber {
    static let sensitiveFragments = ["authorization", "api-key", "apikey", "api_key", "token", "secret", "password", "cookie", "x-auth", "access_key", "private"]
    static let sensitiveQueryNames: Set<String> = ["key", "apikey", "api_key", "token", "access_token", "auth", "secret", "password", "appid", "app_id"]

    static func isSensitiveName(_ name: String) -> Bool {
        let n = name.lowercased()
        return sensitiveFragments.contains { n.contains($0) }
    }

    static func placeholderName(_ name: String) -> String {
        name.uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    static func scrub(_ definition: WidgetDefinition) -> WidgetDefinition {
        var d = definition
        for i in d.dataSources.indices {
            for (name, value) in d.dataSources[i].headers where isSensitiveName(name) && !value.contains("{{secret:") {
                d.dataSources[i].headers[name] = "{{secret:\(placeholderName(name))}}"
            }
            d.dataSources[i].url = scrubURL(d.dataSources[i].url)
            d.dataSources[i].fileID = nil     // bookmarks are meaningless (and private) on another Mac
        }
        for key in d.settings.keys where isSensitiveName(key) { d.settings[key] = "" }
        d.permissions.files = []
        return d
    }

    static func scrubURL(_ url: String) -> String {
        guard let q = url.firstIndex(of: "?") else { return url }
        let base = url[..<q]
        let pairs = url[url.index(after: q)...].split(separator: "&", omittingEmptySubsequences: true).map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, sensitiveQueryNames.contains(parts[0].lowercased()), !parts[1].contains("{{") else { return String(pair) }
            return "\(parts[0])={{secret:\(placeholderName(parts[0]))}}"
        }
        return String(base) + "?" + pairs.joined(separator: "&")
    }
}
