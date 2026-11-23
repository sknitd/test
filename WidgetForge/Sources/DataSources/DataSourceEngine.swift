import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything the engine needs to know about *who* is asking for data.
struct FetchContext: Sendable {
    var permissions: PermissionManifest
    var settings: [String: JSONValue] = [:]
    var widgetID: String = ""
}

struct DataEngineStats: Equatable, Sendable {
    var requests = 0
    var failures = 0
    var cacheHits = 0
    var retries = 0
    var bytesReceived = 0
}

protocol StreamTransport: Sendable {
    /// Text or binary frames from a WebSocket. The stream ends (or throws) when the connection drops.
    func messages(url: URL, headers: [String: String]) -> AsyncThrowingStream<Data, Error>
}

/// Fetches, caches, validates and schedules data for widgets.
///
/// Guarantees:
/// - no request leaves unless its host is in the widget's allowlist, and no secret is attached to a host
///   the secret is not bound to;
/// - refresh intervals are clamped per source kind, identical in-flight requests are shared, and requests
///   to one host are spaced out;
/// - failures retry with exponential backoff and fall back to the last good value;
/// - nothing runs while the engine is suspended (Mac asleep, widgets hidden, updates paused).
actor DataSourceEngine {
    struct CacheEntry: Codable, Sendable {
        var value: JSONValue
        var fetchedAt: Date
    }

    private let transport: HTTPTransport
    private let streams: StreamTransport?
    private let secrets: SecretStore
    private let files: FileAccessProvider
    private weak var metrics: SystemMetricsProvider?
    private let calendar: CalendarProvider?
    private let store: DocumentStore?
    private let sleeper: @Sendable (Double) async throws -> Void
    private let now: @Sendable () -> Date
    private let log: @Sendable (String, String) -> Void     // (level, message)

    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<Result<JSONValue, DataSourceError>, Never>] = [:]
    private var lastRequest: [String: Date] = [:]
    private var subscriptions: [String: [Task<Void, Never>]] = [:]
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isSuspended = false
    private(set) var stats = DataEngineStats()
    private(set) var statuses: [String: DataSourceStatus] = [:]   // "widgetID/sourceID"

    /// Minimum spacing between two requests to the same host.
    var hostSpacing: Double = 1.0
    static let maxResponseBytes = 2_000_000

    init(transport: HTTPTransport, streams: StreamTransport? = nil, secrets: SecretStore, files: FileAccessProvider = NoFileAccess(),
         metrics: SystemMetricsProvider? = nil, calendar: CalendarProvider? = nil, store: DocumentStore? = nil,
         hostSpacing: Double = 1.0,
         sleeper: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) },
         now: @escaping @Sendable () -> Date = { Date() },
         log: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.transport = transport; self.streams = streams; self.secrets = secrets; self.files = files
        self.metrics = metrics; self.calendar = calendar; self.store = store; self.hostSpacing = hostSpacing
        self.sleeper = sleeper; self.now = now; self.log = log
    }

    // MARK: One-shot fetch

    /// Fetch a source once. Never throws: failures are reported in the result's status, together with the
    /// last good value when one exists.
    func fetch(_ config: DataSourceConfig, context: FetchContext) async -> DataSourceResult {
        let started = now()
        let key = cacheKey(config, context)
        var attempts = 1
        do {
            let (raw, fromCache, tries) = try await load(config, context: context, key: key)
            attempts = tries
            var value = raw
            if let transform = config.transform, !transform.isEmpty {
                guard let transformed = raw.path(transform) else { throw DataSourceError.validationFailed(transform) }
                value = transformed
            }
            for path in config.requiredPaths where value.path(path) == nil || value.path(path)?.isNull == true {
                throw DataSourceError.validationFailed(path)
            }
            if !fromCache, config.kind.usesNetwork || config.kind == .jsonFile || config.kind == .csvFile {
                remember(raw, key: key)
            }
            let result = DataSourceResult(value: value, status: .ok, fetchedAt: fromCache ? cache[key]?.fetchedAt : now(),
                                          fromCache: fromCache, attempts: attempts, duration: now().timeIntervalSince(started))
            statuses[statusKey(config, context)] = .ok
            return result
        } catch {
            let failure = (error as? DataSourceError) ?? .invalidResponse(error.localizedDescription)
            let message = failure.errorDescription ?? "Unknown error"
            var result = DataSourceResult(value: nil, status: .failed(message), fetchedAt: nil, fromCache: false,
                                          attempts: attempts, duration: now().timeIntervalSince(started))
            if failure.needsSetup {
                // Never show cached data to a widget whose access was revoked or is not configured.
                result.status = .needsSetup(message)
            } else if let cached = cachedEntry(key) {
                var value: JSONValue? = cached.value
                if let transform = config.transform, !transform.isEmpty { value = cached.value.path(transform) }
                if let value {
                    result.value = value
                    result.status = .stale(message)
                    result.fetchedAt = cached.fetchedAt
                    result.fromCache = true
                }
            }
            if case .failed = result.status { stats.failures += 1 } else if case .stale = result.status { stats.failures += 1 }
            statuses[statusKey(config, context)] = result.status
            log(failure.needsSetup ? "info" : "warning", "\(config.name): \(message)")
            return result
        }
    }

    private func load(_ config: DataSourceConfig, context: FetchContext, key: String) async throws -> (JSONValue, Bool, Int) {
        switch config.kind {
        case .userData:
            return (config.value ?? .null, false, 1)
        case .time:
            return (DataSourceEngine.timeValue(now()), false, 1)
        case .systemMetric:
            guard context.permissions.systemMetrics else { throw DataSourceError.notAllowed("system metrics") }
            guard let value = metrics?.snapshot(metric: config.metric ?? "") else {
                throw DataSourceError.unsupported("System metric \"\(config.metric ?? "")\"")
            }
            return (value, false, 1)
        case .calendar:
            guard context.permissions.calendar else { throw DataSourceError.notAllowed("calendar access") }
            guard let calendar else { throw DataSourceError.unsupported("Calendar access") }
            do { return (try await calendar.upcomingEvents(limit: 20), false, 1) }
            catch let error as DataSourceError { throw error }
            catch { throw DataSourceError.notAllowed(error.localizedDescription) }
        case .jsonFile, .csvFile:
            guard let fileID = config.fileID, !fileID.isEmpty, context.permissions.files.contains(fileID) else {
                throw DataSourceError.fileNotAuthorized
            }
            let data: Data
            do { data = try files.read(fileID: fileID) }
            catch let error as DataSourceError { throw error }
            catch { throw DataSourceError.offline(error.localizedDescription) }
            guard data.count <= DataSourceEngine.maxResponseBytes else { throw DataSourceError.invalidResponse("file is larger than 2 MB") }
            if config.kind == .csvFile {
                guard let text = String(data: data, encoding: .utf8) else { throw DataSourceError.invalidResponse("not UTF-8 text") }
                return (CSVParser.parse(text), false, 1)
            }
            do { return (try JSONValue.parse(data), false, 1) }
            catch { throw DataSourceError.invalidResponse("not valid JSON") }
        case .webSocket:
            if let cached = cachedEntry(key) { return (cached.value, true, 1) }
            throw DataSourceError.offline("waiting for the first message")
        case .rest, .localHTTP:
            return try await loadHTTP(config, context: context, key: key)
        }
    }

    private func loadHTTP(_ config: DataSourceConfig, context: FetchContext, key: String) async throws -> (JSONValue, Bool, Int) {
        let request = try buildRequest(config, context: context)
        if config.cacheTTL > 0, let entry = cache[key], now().timeIntervalSince(entry.fetchedAt) < config.cacheTTL {
            stats.cacheHits += 1
            return (entry.value, true, 1)
        }
        // Share one request between widgets that ask for the same thing at the same time.
        if let running = inFlight[key] {
            stats.cacheHits += 1
            return (try await running.value.get(), false, 1)
        }
        let attemptsBox = Box(1)
        let task = Task<Result<JSONValue, DataSourceError>, Never> { [weak self] in
            guard let self else { return .failure(.offline("engine released")) }
            do { return .success(try await self.performWithRetry(request, policy: config.retry, attempts: attemptsBox)) }
            catch let error as DataSourceError { return .failure(error) }
            catch { return .failure(.invalidResponse(error.localizedDescription)) }
        }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        return (try outcome.get(), false, attemptsBox.value)
    }

    private func performWithRetry(_ request: HTTPRequest, policy: RetryPolicy, attempts: Box<Int>) async throws -> JSONValue {
        var attempt = 1
        while true {
            attempts.value = attempt
            try Task.checkCancellation()
            await spaceRequests(to: request.url.host ?? "")
            stats.requests += 1
            var retryAfter: Double?
            do {
                let response = try await transport.send(request)
                stats.bytesReceived += response.body.count
                guard (200..<300).contains(response.status) else {
                    retryAfter = response.headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Double($0.value) }
                    throw DataSourceError.http(response.status)
                }
                guard response.body.count <= DataSourceEngine.maxResponseBytes else { throw DataSourceError.invalidResponse("response is larger than 2 MB") }
                if response.body.isEmpty { return .null }
                if let json = try? JSONValue.parse(response.body) { return json }
                guard let text = String(data: response.body, encoding: .utf8) else { throw DataSourceError.invalidResponse("not JSON or text") }
                return .string(text)
            } catch {
                let mapped = DataSourceEngine.map(error)
                guard mapped.isRetryable, attempt < policy.maxAttempts else { throw mapped }
                stats.retries += 1
                let delay = min(policy.maxDelay, max(policy.delay(afterAttempt: attempt), retryAfter ?? 0))
                log("info", "Retrying \(request.url.host ?? "") in \(JSONValue.format(delay))s (attempt \(attempt + 1)/\(policy.maxAttempts)): \(mapped.errorDescription ?? "")")
                try await sleeper(delay)
                attempt += 1
            }
        }
    }

    /// Builds the outgoing request, enforcing the allowlist and secret bindings. Internal for testing.
    func buildRequest(_ config: DataSourceConfig, context: FetchContext) throws -> HTTPRequest {
        let urlText = try DataSourceEngine.fillSettings(config.url, context.settings)
        // The host is checked on the template *before* secrets are substituted, so a secret can never choose it.
        guard let probe = URL(string: DataSourceEngine.stripSecrets(urlText)), let host = probe.host else {
            throw DataSourceError.invalidURL(config.url)
        }
        guard ["http", "https"].contains(probe.scheme?.lowercased() ?? "") else { throw DataSourceError.invalidURL(config.url) }
        if config.kind == .localHTTP, !PermissionChecker.isLocal(host) {
            throw DataSourceError.notAllowed("\(host) is not a local address")
        }
        guard PermissionChecker.hostAllowed(host, allowlist: context.permissions.network) else {
            throw DataSourceError.notAllowed("network access to \(host)")
        }
        let finalURLText = try fillSecrets(urlText, host: host, encode: true)
        guard let url = URL(string: finalURLText), url.host?.lowercased() == host.lowercased() else {
            throw DataSourceError.invalidURL(config.url)
        }
        var headers: [String: String] = ["Accept": "application/json", "User-Agent": "WidgetForge/1.0"]
        for (name, value) in config.headers {
            headers[name] = try fillSecrets(try DataSourceEngine.fillSettings(value, context.settings), host: host, encode: false)
        }
        var body: Data?
        if let text = config.body, !text.isEmpty {
            body = Data(try fillSecrets(try DataSourceEngine.fillSettings(text, context.settings), host: host, encode: false).utf8)
            if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        }
        let method = config.method.uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(method) else { throw DataSourceError.unsupported("HTTP method \(method)") }
        return HTTPRequest(url: url, method: method, headers: headers, body: body, timeout: min(max(config.timeout, 1), 60))
    }

    private func fillSecrets(_ text: String, host: String, encode: Bool) throws -> String {
        guard text.contains("{{secret:") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{secret:") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { throw DataSourceError.invalidURL("unterminated secret placeholder") }
            let name = after[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            guard let secret = secrets.secret(named: name), !secret.value.isEmpty else { throw DataSourceError.missingSecret(name) }
            guard PermissionChecker.hostAllowed(host, allowlist: secret.hosts) else {
                throw DataSourceError.notAllowed("the secret \"\(name)\" is not approved for \(host)")
            }
            out += encode ? (secret.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") : secret.value
            rest = after[close.upperBound...]
        }
        return out + rest
    }

    static func stripSecrets(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{secret:") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { break }
            out += "SECRET"
            rest = after[close.upperBound...]
        }
        return out + rest
    }

    /// Replace `{{settings.key}}` placeholders; a missing or empty setting is a setup problem, not an error page.
    static func fillSettings(_ text: String, _ settings: [String: JSONValue]) throws -> String {
        guard text.contains("{{settings.") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{settings.") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { throw DataSourceError.invalidURL(text) }
            let name = after[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = (JSONValue.object(settings).path(name) ?? .null).displayString
            guard !value.isEmpty else { throw DataSourceError.missingSetting(name) }
            out += value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?&=#"))) ?? value
            rest = after[close.upperBound...]
        }
        return out + rest
    }

    static func map(_ error: Error) -> DataSourceError {
        if let e = error as? DataSourceError { return e }
        if let e = error as? URLError {
            switch e.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                return .offline(e.localizedDescription)
            default: return .invalidResponse(e.localizedDescription)
            }
        }
        if error is CancellationError { return .invalidResponse("cancelled") }
        return .invalidResponse(error.localizedDescription)
    }

    static func timeValue(_ date: Date) -> JSONValue {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        return [
            "epoch": .number(date.timeIntervalSince1970),
            "iso": .string(ISO8601DateFormatter().string(from: date)),
            "year": .number(Double(parts.year ?? 0)), "month": .number(Double(parts.month ?? 0)),
            "day": .number(Double(parts.day ?? 0)), "hour": .number(Double(parts.hour ?? 0)),
            "minute": .number(Double(parts.minute ?? 0)), "second": .number(Double(parts.second ?? 0)),
            "weekday": .number(Double(parts.weekday ?? 0)),
        ]
    }

    private func spaceRequests(to host: String) async {
        guard hostSpacing > 0, !host.isEmpty else { return }
        let current = now()
        if let last = lastRequest[host] {
            let wait = hostSpacing - current.timeIntervalSince(last)
            if wait > 0 {
                lastRequest[host] = current.addingTimeInterval(wait)
                try? await sleeper(wait)
                return
            }
        }
        lastRequest[host] = current
    }

    // MARK: Cache

    private func cacheKey(_ config: DataSourceConfig, _ context: FetchContext) -> String {
        let url = (try? DataSourceEngine.fillSettings(config.url, context.settings)) ?? config.url
        switch config.kind {
        case .rest, .localHTTP, .webSocket: return "\(config.kind.rawValue)|\(config.method)|\(url)|\(config.body ?? "")"
        case .jsonFile, .csvFile: return "\(config.kind.rawValue)|\(config.fileID ?? "")"
        default: return "\(config.kind.rawValue)|\(config.id)"
        }
    }

    private func statusKey(_ config: DataSourceConfig, _ context: FetchContext) -> String { "\(context.widgetID)/\(config.id)" }

    private func remember(_ value: JSONValue, key: String) {
        let entry = CacheEntry(value: value, fetchedAt: now())
        cache[key] = entry
        try? store?.save(entry, in: Collections.dataCache, id: DataSourceEngine.storageID(key))
    }

    private func cachedEntry(_ key: String) -> CacheEntry? {
        if let entry = cache[key] { return entry }
        guard let stored = try? store?.load(CacheEntry.self, from: Collections.dataCache, id: DataSourceEngine.storageID(key)) else { return nil }
        cache[key] = stored
        return stored
    }

    /// Stable, filename-safe id for a cache key (FNV-1a; not security sensitive).
    static func storageID(_ key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    func clearCache() {
        cache.removeAll()
        try? store?.deleteAll(Collections.dataCache)
    }

    func cachedValue(for config: DataSourceConfig, context: FetchContext) -> CacheEntry? { cachedEntry(cacheKey(config, context)) }

    // MARK: Subscriptions

    /// Keep a source fresh for `owner` (a widget id) until `unsubscribe(owner:)`. `onUpdate` receives every
    /// result, including failures and cached fallbacks.
    func subscribe(owner: String, config: DataSourceConfig, context: FetchContext,
                   onUpdate: @escaping @Sendable (DataSourceResult) -> Void) {
        let task = Task { [weak self] in
            guard let self else { return }
            if config.kind == .webSocket {
                await self.runStream(config, context: context, onUpdate: onUpdate)
            } else {
                await self.runPolling(config, context: context, onUpdate: onUpdate)
            }
        }
        subscriptions[owner, default: []].append(task)
    }

    func unsubscribe(owner: String) {
        subscriptions.removeValue(forKey: owner)?.forEach { $0.cancel() }
        statuses = statuses.filter { !$0.key.hasPrefix(owner + "/") }
    }

    var activeSubscriptionCount: Int { subscriptions.values.reduce(0) { $0 + $1.count } }

    private func runPolling(_ config: DataSourceConfig, context: FetchContext, onUpdate: @Sendable (DataSourceResult) -> Void) async {
        var consecutiveFailures = 0
        while !Task.isCancelled {
            await waitWhileSuspended()
            if Task.isCancelled { return }
            let result = await fetch(config, context: context)
            if Task.isCancelled { return }
            onUpdate(result)
            let interval = config.effectiveInterval
            guard interval > 0 else { return }
            if case .needsSetup = result.status { return }      // nothing will change until the user acts
            if case .ok = result.status { consecutiveFailures = 0 } else { consecutiveFailures += 1 }
            // A failing source is polled progressively less often (up to 8× its interval).
            let factor = pow(2.0, Double(min(consecutiveFailures, 3)))
            do { try await sleeper(interval * factor) } catch { return }
        }
    }

    private func runStream(_ config: DataSourceConfig, context: FetchContext, onUpdate: @Sendable (DataSourceResult) -> Void) async {
        let key = cacheKey(config, context)
        var attempt = 0
        while !Task.isCancelled {
            await waitWhileSuspended()
            if Task.isCancelled { return }
            do {
                guard let streams else { throw DataSourceError.unsupported("WebSocket streaming") }
                let urlText = try DataSourceEngine.fillSettings(config.url, context.settings)
                guard let probe = URL(string: DataSourceEngine.stripSecrets(urlText)), let host = probe.host,
                      ["ws", "wss"].contains(probe.scheme?.lowercased() ?? "") else { throw DataSourceError.invalidURL(config.url) }
                guard PermissionChecker.hostAllowed(host, allowlist: context.permissions.network) else {
                    throw DataSourceError.notAllowed("network access to \(host)")
                }
                guard let url = URL(string: try fillSecrets(urlText, host: host, encode: true)) else { throw DataSourceError.invalidURL(config.url) }
                var headers: [String: String] = [:]
                for (name, value) in config.headers { headers[name] = try fillSecrets(value, host: host, encode: false) }
                stats.requests += 1
                var lastEmit = Date.distantPast
                for try await message in streams.messages(url: url, headers: headers) {
                    if Task.isCancelled { return }
                    attempt = 0
                    stats.bytesReceived += message.count
                    guard message.count <= DataSourceEngine.maxResponseBytes else { continue }
                    let raw = (try? JSONValue.parse(message)) ?? .string(String(data: message, encoding: .utf8) ?? "")
                    cache[key] = CacheEntry(value: raw, fetchedAt: now())
                    // Coalesce bursts: the widget sees at most four updates a second, always the latest value.
                    guard now().timeIntervalSince(lastEmit) >= 0.25, !isSuspended else { continue }
                    lastEmit = now()
                    var value: JSONValue? = raw
                    if let transform = config.transform, !transform.isEmpty { value = raw.path(transform) }
                    guard let value else { continue }
                    statuses[statusKey(config, context)] = .ok
                    onUpdate(DataSourceResult(value: value, status: .ok, fetchedAt: now()))
                }
                throw DataSourceError.offline("connection closed")
            } catch {
                if Task.isCancelled { return }
                let failure = DataSourceEngine.map(error)
                let message = failure.errorDescription ?? "Stream error"
                if failure.needsSetup {
                    statuses[statusKey(config, context)] = .needsSetup(message)
                    onUpdate(DataSourceResult(value: nil, status: .needsSetup(message), fetchedAt: nil))
                    return
                }
                stats.failures += 1
                let cached = cache[key]
                let status: DataSourceStatus = cached == nil ? .failed(message) : .stale(message)
                statuses[statusKey(config, context)] = status
                var fallback: JSONValue? = cached?.value
                if let transform = config.transform, !transform.isEmpty { fallback = cached?.value.path(transform) }
                onUpdate(DataSourceResult(value: fallback, status: status, fetchedAt: cached?.fetchedAt, fromCache: cached != nil))
                attempt += 1
                do { try await sleeper(config.retry.delay(afterAttempt: attempt)) } catch { return }
            }
        }
    }

    // MARK: Suspension

    /// Stop all polling until `resume()`. In-flight requests finish; no new ones start.
    func suspend() {
        isSuspended = true
    }

    func resume() {
        isSuspended = false
        let waiters = resumeWaiters
        resumeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitWhileSuspended() async {
        while isSuspended, !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                resumeWaiters.append(continuation)
            }
        }
    }

    func status(widgetID: String, sourceID: String) -> DataSourceStatus { statuses["\(widgetID)/\(sourceID)"] ?? .idle }
}

/// A mutable reference used to report progress out of a detached task.
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: URLSession transports

/// Production HTTP transport. Ephemeral (no cookies, no credential storage, no disk cache) and it refuses
/// redirects to a different host, because a redirect would otherwise sidestep the widget's allowlist.
final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var r = URLRequest(url: request.url, timeoutInterval: request.timeout)
        r.httpMethod = request.method
        r.httpBody = request.body
        for (name, value) in request.headers { r.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw DataSourceError.invalidResponse("not an HTTP response") }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let sameHost = request.url?.host?.lowercased() == task.originalRequest?.url?.host?.lowercased()
        let noDowngrade = !(task.originalRequest?.url?.scheme == "https" && request.url?.scheme != "https")
        completionHandler(sameHost && noDowngrade ? request : nil)
    }
}

#if canImport(Darwin)
final class URLSessionStreamTransport: StreamTransport, @unchecked Sendable {
    private let session = URLSession(configuration: .ephemeral)

    func messages(url: URL, headers: [String: String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            var request = URLRequest(url: url)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let task = session.webSocketTask(with: request)
            task.maximumMessageSize = DataSourceEngine.maxResponseBytes
            task.resume()
            let reader = Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .data(let data): continuation.yield(data)
                        case .string(let text): continuation.yield(Data(text.utf8))
                        @unknown default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
#endif
