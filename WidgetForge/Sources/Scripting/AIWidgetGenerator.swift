import Foundation

struct AIConfiguration: Codable, Equatable, Sendable {
    var enabled = false
    /// Base URL of an OpenAI-compatible API, e.g. https://api.openai.com/v1 or http://localhost:11434/v1
    var endpoint = "https://api.openai.com/v1"
    var model = "gpt-4o-mini"
    /// Name of the Keychain secret holding the API key (empty for local servers without auth).
    var secretName = "AI_API_KEY"
}

enum AIError: Error, LocalizedError, Equatable {
    case disabled
    case invalidEndpoint
    case missingKey
    case http(Int, String)
    case noJSON
    case invalidWidget([String])

    var errorDescription: String? {
        switch self {
        case .disabled: return "The AI builder is turned off in Settings"
        case .invalidEndpoint: return "The AI endpoint URL is not valid"
        case .missingKey: return "Add your API key in Settings → AI Builder"
        case .http(let status, let body): return "The AI service returned HTTP \(status). \(body)"
        case .noJSON: return "The model did not return a widget definition"
        case .invalidWidget(let errors): return "The generated widget failed validation:\n" + errors.joined(separator: "\n")
        }
    }
}

struct GeneratedWidget: Sendable {
    var definition: WidgetDefinition
    var report: ValidationReport
    var requestedPermissions: PermissionManifest
}

/// Turns a natural-language request into a *declarative* widget definition using any OpenAI-compatible
/// chat-completions endpoint.
///
/// The model's output is treated exactly like an imported file: validated, never executed. Scripts are
/// stripped outright, and the user reviews the preview and the requested permissions before anything is saved.
struct AIWidgetGenerator: Sendable {
    var configuration: AIConfiguration
    var transport: HTTPTransport

    static let systemPrompt = """
    You design desktop widgets for WidgetForge. Reply with ONE JSON object and nothing else.

    Shape:
    {"name": string, "summary": string, "symbol": SF Symbol name, "size": {"width": 160-640, "height": 100-520},
     "root": Node, "dataSources": [DataSource], "permissions": Permissions}

    Node: {"type": T, ...props, "children": [Node]} where T is one of:
      column, row, stack, spacer, divider, text, richText, button, image, icon, clock, date, progress, gauge,
      slider, toggle, input, chart, table, list, calendar, metric, apiViewer, todo, pomodoro, habits, countdown.
    Common props: value (string, may contain {{placeholders}}), fontSize, fontWeight (regular|medium|semibold|bold),
      color (hex or primary|secondary|accent|red|orange|yellow|green|blue|purple|pink), spacing, padding, alignment.
    progress/gauge: value 0..1 (e.g. "{{cpu.usage}}"), label. chart: chartKind (line|bar|area|pie|sparkline),
      values (e.g. "{{cpu.history}}"). metric: metric (cpu|memory|storage|network|battery|system).
    list/table: items (e.g. "{{api.items}}"), titlePath, subtitlePath / columns.

    DataSource: {"id": name, "kind": "systemMetric", "metric": "cpu"|"memory"|"storage"|"network"|"battery"|"system", "interval": seconds}
             or {"id": name, "kind": "rest", "url": "https://…", "interval": seconds >= 15, "transform": optional JSON path}.
    Placeholders read data sources by id: {{cpu.usage | percent}}, {{memory.usedBytes | bytes}},
      {{network.downBytesPerSec | rate}}, {{battery.level | percent}}, {{system.uptimeSeconds | duration}}.

    Permissions: {"systemMetrics": bool, "network": [hostnames used by rest sources]}.
    Rules: never include scripts, shell commands, API keys or file paths. Request only the permissions the widget needs.
    """

    /// Local prompt templates offered in the UI.
    static let promptTemplates: [(title: String, prompt: String)] = [
        ("System overview", "Create a compact widget showing CPU, RAM, battery and network speed."),
        ("Focus timer", "A minimal focus widget with a large clock, today's date and a pomodoro timer."),
        ("Disk space", "A small widget with a gauge for disk usage and the free space in GB."),
        ("JSON API card", "A widget that shows the title and description from https://api.github.com/repos/apple/swift with a refresh every 10 minutes."),
    ]

    func generate(prompt: String, secrets: SecretStore) async throws -> GeneratedWidget {
        guard configuration.enabled else { throw AIError.disabled }
        let base = configuration.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions"), let host = url.host, ["http", "https"].contains(url.scheme ?? "") else {
            throw AIError.invalidEndpoint
        }
        var headers = ["Content-Type": "application/json"]
        if !configuration.secretName.isEmpty, let key = secrets.secret(named: configuration.secretName)?.value, !key.isEmpty {
            headers["Authorization"] = "Bearer \(key)"
        } else if !PermissionChecker.isLocal(host) {
            throw AIError.missingKey
        }
        let body: JSONValue = [
            "model": .string(configuration.model),
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": .string(AIWidgetGenerator.systemPrompt)],
                ["role": "user", "content": .string(String(prompt.prefix(4000)))],
            ],
        ]
        let request = HTTPRequest(url: url, method: "POST", headers: headers, body: Data(body.compactJSONString.utf8), timeout: 60)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            let text = String(data: response.body.prefix(300), encoding: .utf8) ?? ""
            throw AIError.http(response.status, text)
        }
        guard let reply = try? JSONValue.parse(response.body),
              let content = reply.path("choices[0].message.content")?.stringValue else { throw AIError.noJSON }
        return try AIWidgetGenerator.parse(content)
    }

    /// Extract, sanitise and validate the definition contained in a model reply.
    static func parse(_ content: String) throws -> GeneratedWidget {
        guard let jsonText = extractJSONObject(from: content), var json = try? JSONValue.parse(jsonText), var object = json.objectValue else {
            throw AIError.noJSON
        }
        // AI output is declarative only: scripts and script components are removed, not merely disabled.
        object["script"] = nil
        object["id"] = nil
        if var permissions = object["permissions"]?.objectValue {
            permissions["scripting"] = false
            permissions["files"] = []
            object["permissions"] = .object(permissions)
        }
        json = .object(object)
        let report = SchemaValidator.validate(definition: json)
        guard report.isValid else { throw AIError.invalidWidget(report.errors) }
        var definition: WidgetDefinition
        do { definition = try json.decode(WidgetDefinition.self) }
        catch { throw AIError.invalidWidget([error.localizedDescription]) }
        guard !definition.root.flattened.contains(where: { $0.type == .script || $0.type == .web }) else {
            throw AIError.invalidWidget(["Generated widgets may not contain script or web components"])
        }
        definition.category = "AI"
        definition = SecretScrubber.scrub(definition)
        // Ask for exactly what the content needs, no more, whatever the model claimed.
        definition.permissions = PermissionChecker.required(for: definition)
        return GeneratedWidget(definition: definition, report: report, requestedPermissions: definition.permissions)
    }

    /// Finds the first balanced top-level `{…}` in free-form text (models often wrap JSON in prose or fences).
    static func extractJSONObject(from text: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for index in text.indices {
            let ch = text[index]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": if depth > 0 { inString = true }
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let start { return String(text[start...index]) }
            default: break
            }
        }
        return nil
    }
}
