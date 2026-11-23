import XCTest
@testable import WidgetForgeKit

/// Scripted HTTP transport. No test in this suite touches the real network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    private var handler: (HTTPRequest, Int) throws -> HTTPResponse

    /// `handler` receives the request and its 1-based sequence number.
    init(_ handler: @escaping (HTTPRequest, Int) throws -> HTTPResponse) { self.handler = handler }

    static func json(_ text: String, status: Int = 200) -> MockTransport {
        MockTransport { _, _ in HTTPResponse(status: status, body: Data(text.utf8)) }
    }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        _requests.append(request)
        let n = _requests.count
        let h = handler
        lock.unlock()
        return try h(request, n)
    }
}

/// Records requested sleeps instead of waiting, so retry/backoff tests run instantly.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _delays: [Double] = []
    var delays: [Double] { lock.lock(); defer { lock.unlock() }; return _delays }
    func sleep(_ seconds: Double) async throws {
        lock.lock(); _delays.append(seconds); lock.unlock()
        try Task.checkCancellation()
        await Task.yield()
    }
}

struct MockFiles: FileAccessProvider {
    var files: [String: Data]
    func read(fileID: String) throws -> Data {
        guard let data = files[fileID] else { throw DataSourceError.fileNotAuthorized }
        return data
    }
}

final class ResultCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _results: [DataSourceResult] = []
    var results: [DataSourceResult] { lock.lock(); defer { lock.unlock() }; return _results }
    func add(_ r: DataSourceResult) { lock.lock(); _results.append(r); lock.unlock() }
}

func makeEngine(_ transport: HTTPTransport, secrets: SecretStore = InMemorySecretStore(), files: FileAccessProvider = NoFileAccess(),
                metrics: SystemMetricsProvider? = nil, store: DocumentStore? = nil, sleeper: SleepRecorder = SleepRecorder(),
                streams: StreamTransport? = nil, tick: Double? = nil) -> DataSourceEngine {
    // `tick` replaces every requested delay with a short real sleep, for tests that exercise polling loops.
    let sleep: @Sendable (Double) async throws -> Void
    if let tick { sleep = { _ in try await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000)) } }
    else { sleep = { try await sleeper.sleep($0) } }
    return DataSourceEngine(transport: transport, streams: streams, secrets: secrets, files: files, metrics: metrics, store: store,
                            hostSpacing: 0, sleeper: sleep)
}

let exampleNet = FetchContext(permissions: PermissionManifest(network: ["api.example.com"]), widgetID: "w1")

func rest(_ url: String = "https://api.example.com/data", interval: Double = 60, cacheTTL: Double = 0,
          retry: RetryPolicy = RetryPolicy(), headers: [String: String] = [:], transform: String? = nil) -> DataSourceConfig {
    DataSourceConfig(id: "api", kind: .rest, url: url, headers: headers, interval: interval, transform: transform, cacheTTL: cacheTTL, retry: retry)
}

func simpleDefinition(_ name: String = "Test", size: WidgetSize = WidgetSize(200, 100)) -> WidgetDefinition {
    WidgetDefinition(name: name, size: size, root: .column([.text("Hello")]))
}

func display(_ id: String, x: Double = 0, width: Double = 1440, height: Double = 900, main: Bool = false) -> DisplayInfo {
    DisplayInfo(id: id, name: id, frame: Rect(x: x, y: 0, width: width, height: height), scale: 2, isMain: main)
}

/// Poll until a condition holds (for assertions about asynchronous work), failing after `timeout`.
func eventually(timeout: Double = 3, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}
