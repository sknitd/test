import Foundation

enum DataSourceKind: String, Codable, CaseIterable, Sendable {
    case rest, webSocket, jsonFile, csvFile, systemMetric, time, calendar, userData, localHTTP

    var title: String {
        switch self {
        case .rest: return "REST JSON API"
        case .webSocket: return "WebSocket Stream"
        case .jsonFile: return "Local JSON File"
        case .csvFile: return "CSV File"
        case .systemMetric: return "System Metric"
        case .time: return "Time & Date"
        case .calendar: return "Calendar Events"
        case .userData: return "User-defined Data"
        case .localHTTP: return "Local HTTP Service"
        }
    }

    /// The shortest refresh interval the engine will honour, in seconds. Guards against runaway polling.
    var minimumInterval: Double {
        switch self {
        case .rest: return 15
        case .localHTTP: return 2
        case .jsonFile, .csvFile: return 2
        case .systemMetric: return 1
        case .time: return 1
        case .calendar: return 60
        case .userData, .webSocket: return 0
        }
    }

    var usesNetwork: Bool { self == .rest || self == .webSocket || self == .localHTTP }
}

struct RetryPolicy: Codable, Hashable, Sendable {
    var maxAttempts = 3
    var baseDelay = 1.0
    var multiplier = 2.0
    var maxDelay = 60.0

    /// Delay before retry number `attempt` (1-based: the delay after the first failure is `baseDelay`).
    func delay(afterAttempt attempt: Int) -> Double {
        min(maxDelay, baseDelay * pow(multiplier, Double(max(0, attempt - 1))))
    }

    static let none = RetryPolicy(maxAttempts: 1)
}

extension RetryPolicy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        maxAttempts = max(1, min(8, try c.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 3))
        baseDelay = max(0, try c.decodeIfPresent(Double.self, forKey: .baseDelay) ?? 1)
        multiplier = max(1, try c.decodeIfPresent(Double.self, forKey: .multiplier) ?? 2)
        maxDelay = max(0, try c.decodeIfPresent(Double.self, forKey: .maxDelay) ?? 60)
    }
}

struct DataSourceConfig: Codable, Hashable, Identifiable, Sendable {
    /// Also the name the widget uses to read the data: `{{id.some.path}}`.
    var id: String
    var name: String
    var kind: DataSourceKind
    var url: String
    var method: String
    /// Header values may contain `{{secret:NAME}}` and `{{settings.key}}` placeholders.
    var headers: [String: String]
    var body: String?
    /// Seconds between refreshes. 0 = fetch once. Clamped to `kind.minimumInterval`.
    var interval: Double
    /// Optional JSON path applied to the response before it reaches the widget (e.g. `data.items`).
    var transform: String?
    /// Seconds a cached response may be reused instead of hitting the network again.
    var cacheTTL: Double
    var retry: RetryPolicy
    var timeout: Double
    /// For `.systemMetric`: cpu | memory | storage | network | battery | system.
    var metric: String?
    /// For file sources: id of a user-selected file bookmark.
    var fileID: String?
    /// For `.userData`: the literal value.
    var value: JSONValue?
    /// Paths that must exist in the (transformed) response for it to be accepted.
    var requiredPaths: [String]

    init(id: String, name: String? = nil, kind: DataSourceKind, url: String = "", method: String = "GET",
         headers: [String: String] = [:], body: String? = nil, interval: Double = 60, transform: String? = nil,
         cacheTTL: Double = 0, retry: RetryPolicy = RetryPolicy(), timeout: Double = 15, metric: String? = nil,
         fileID: String? = nil, value: JSONValue? = nil, requiredPaths: [String] = []) {
        self.id = id; self.name = name ?? id; self.kind = kind; self.url = url; self.method = method
        self.headers = headers; self.body = body; self.interval = interval; self.transform = transform
        self.cacheTTL = cacheTTL; self.retry = retry; self.timeout = timeout; self.metric = metric
        self.fileID = fileID; self.value = value; self.requiredPaths = requiredPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        kind = try c.decode(DataSourceKind.self, forKey: .kind)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try c.decodeIfPresent(String.self, forKey: .body)
        interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? 60
        transform = try c.decodeIfPresent(String.self, forKey: .transform)
        cacheTTL = try c.decodeIfPresent(Double.self, forKey: .cacheTTL) ?? 0
        retry = try c.decodeIfPresent(RetryPolicy.self, forKey: .retry) ?? RetryPolicy()
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 15
        metric = try c.decodeIfPresent(String.self, forKey: .metric)
        fileID = try c.decodeIfPresent(String.self, forKey: .fileID)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value)
        requiredPaths = try c.decodeIfPresent([String].self, forKey: .requiredPaths) ?? []
    }

    /// The refresh interval actually used.
    var effectiveInterval: Double { interval <= 0 ? 0 : max(interval, kind.minimumInterval) }

    /// Names of every `{{secret:NAME}}` placeholder in the URL, headers and body.
    var secretNames: [String] {
        var names: [String] = []
        for text in [url, body ?? ""] + Array(headers.values) {
            var rest = Substring(text)
            while let open = rest.range(of: "{{secret:") {
                let after = rest[open.upperBound...]
                guard let close = after.range(of: "}}") else { break }
                names.append(after[..<close.lowerBound].trimmingCharacters(in: .whitespaces))
                rest = after[close.upperBound...]
            }
        }
        return Array(Set(names)).sorted()
    }
}

enum DataSourceError: Error, LocalizedError, Equatable {
    case notAllowed(String)
    case missingSecret(String)
    case missingSetting(String)
    case invalidURL(String)
    case http(Int)
    case timeout
    case offline(String)
    case invalidResponse(String)
    case validationFailed(String)
    case fileNotAuthorized
    case unsupported(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notAllowed(let what): return "Not permitted: \(what)"
        case .missingSecret(let name): return "Add the \"\(name)\" secret in Settings → Secrets"
        case .missingSetting(let name): return "Set \"\(name)\" in the widget's settings"
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .http(let status): return "Server responded with HTTP \(status)"
        case .timeout: return "The request timed out"
        case .offline(let reason): return "Offline: \(reason)"
        case .invalidResponse(let reason): return "Unreadable response: \(reason)"
        case .validationFailed(let path): return "Response is missing \"\(path)\""
        case .fileNotAuthorized: return "Choose a file for this data source"
        case .unsupported(let what): return "\(what) is not available"
        case .rateLimited: return "Rate limited"
        }
    }

    /// Whether another attempt could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .http(let status): return status == 408 || status == 429 || status >= 500
        case .timeout, .offline, .rateLimited: return true
        default: return false
        }
    }

    /// Problems the user fixes by configuring something, as opposed to transient failures.
    var needsSetup: Bool {
        switch self {
        case .missingSecret, .missingSetting, .fileNotAuthorized, .notAllowed: return true
        default: return false
        }
    }
}

enum DataSourceStatus: Equatable, Sendable {
    case idle
    case loading
    case ok
    /// Showing an older value because the latest refresh failed.
    case stale(String)
    case failed(String)
    case needsSetup(String)
    case suspended

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Loading"
        case .ok: return "Live"
        case .stale: return "Cached"
        case .failed: return "Error"
        case .needsSetup: return "Setup required"
        case .suspended: return "Paused"
        }
    }

    var detail: String? {
        switch self {
        case .stale(let m), .failed(let m), .needsSetup(let m): return m
        default: return nil
        }
    }

    var isHealthy: Bool { self == .ok || self == .loading || self == .idle }

    /// Stable machine-readable name, exposed to widgets as `{{sources.<id>.state}}`.
    var key: String {
        switch self {
        case .idle: return "idle"
        case .loading: return "loading"
        case .ok: return "ok"
        case .stale: return "stale"
        case .failed: return "failed"
        case .needsSetup: return "needsSetup"
        case .suspended: return "suspended"
        }
    }

    var json: JSONValue {
        ["state": .string(key), "label": .string(label), "detail": .string(detail ?? ""), "healthy": .bool(isHealthy)]
    }
}

struct DataSourceResult: Equatable, Sendable {
    var value: JSONValue?
    var status: DataSourceStatus
    var fetchedAt: Date?
    var fromCache = false
    var attempts = 1
    var duration: Double = 0
}

// MARK: Transports

struct HTTPRequest: Hashable, Sendable {
    var url: URL
    var method = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: Double = 15
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body: Data
}

protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Gives the engine access to user-selected files without ever handing widgets a path.
protocol FileAccessProvider: Sendable {
    func read(fileID: String) throws -> Data
}

protocol SystemMetricsProvider: AnyObject {
    /// cpu | memory | storage | network | battery | system. Returns nil for unknown metrics.
    func snapshot(metric: String) -> JSONValue?
}

protocol CalendarProvider: Sendable {
    /// Upcoming events as `[{title, start, end, calendar, allDay}]`, soonest first.
    func upcomingEvents(limit: Int) async throws -> JSONValue
}

struct NoFileAccess: FileAccessProvider {
    func read(fileID: String) throws -> Data { throw DataSourceError.fileNotAuthorized }
}

enum CSVParser {
    /// RFC 4180-style parsing (quoted fields, doubled quotes, embedded newlines). The first row is the header;
    /// the result is an array of objects, with numeric-looking fields converted to numbers.
    static func parse(_ text: String, delimiter: Character = ",") -> JSONValue {
        let rows = parseRows(text, delimiter: delimiter)
        guard let header = rows.first else { return .array([]) }
        let keys = header.enumerated().map { $0.element.isEmpty ? "column\($0.offset + 1)" : $0.element.trimmingCharacters(in: .whitespaces) }
        let records = rows.dropFirst().filter { !($0.count == 1 && $0[0].isEmpty) }.map { row -> JSONValue in
            var object: [String: JSONValue] = [:]
            for (i, key) in keys.enumerated() {
                let field = i < row.count ? row[i] : ""
                let trimmed = field.trimmingCharacters(in: .whitespaces)
                if let number = Double(trimmed), !trimmed.isEmpty, number.isFinite { object[key] = .number(number) }
                else { object[key] = .string(field) }
            }
            return .object(object)
        }
        return .array(Array(records))
    }

    static func parseRows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").makeIterator()
        var pending = iterator.next()
        while let ch = pending {
            pending = iterator.next()
            if inQuotes {
                if ch == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
