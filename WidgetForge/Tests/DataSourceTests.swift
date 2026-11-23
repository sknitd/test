import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import WidgetForgeKit

final class DataSourceTests: XCTestCase {
    func testSuccessWithTransform() async {
        let transport = MockTransport.json("{\"data\":{\"items\":[{\"price\":42}]}}")
        let engine = makeEngine(transport)
        let result = await engine.fetch(rest(transform: "data.items[0]"), context: exampleNet)
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.value, ["price": 42])
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://api.example.com/data")
        let status = await engine.status(widgetID: "w1", sourceID: "api")
        XCTAssertEqual(status, .ok)
    }

    func testClientErrorFailsWithoutRetry() async {
        let transport = MockTransport.json("{}", status: 404)
        let sleeper = SleepRecorder()
        let result = await makeEngine(transport, sleeper: sleeper).fetch(rest(), context: exampleNet)
        XCTAssertEqual(result.status, .failed("Server responded with HTTP 404"))
        XCTAssertNil(result.value)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(sleeper.delays.isEmpty)
    }

    func testRetryWithExponentialBackoffThenSuccess() async {
        let transport = MockTransport { _, n in
            n < 3 ? HTTPResponse(status: 503, body: Data()) : HTTPResponse(status: 200, body: Data("{\"ok\":true}".utf8))
        }
        let sleeper = SleepRecorder()
        let engine = makeEngine(transport, sleeper: sleeper)
        let result = await engine.fetch(rest(retry: RetryPolicy(maxAttempts: 4, baseDelay: 1, multiplier: 2, maxDelay: 60)), context: exampleNet)
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.attempts, 3)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(sleeper.delays, [1, 2])
        let stats = await engine.stats
        XCTAssertEqual(stats.retries, 2)
    }

    func testRetryGivesUpAfterMaxAttempts() async {
        let transport = MockTransport.json("", status: 500)
        let sleeper = SleepRecorder()
        let result = await makeEngine(transport, sleeper: sleeper).fetch(rest(retry: RetryPolicy(maxAttempts: 3, baseDelay: 0.5, multiplier: 3, maxDelay: 1)), context: exampleNet)
        XCTAssertEqual(result.status, .failed("Server responded with HTTP 500"))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(sleeper.delays, [0.5, 1], "second delay is capped by maxDelay")
    }

    func testTimeoutIsRetriedAndReported() async {
        let transport = MockTransport { _, _ in throw URLError(.timedOut) }
        let result = await makeEngine(transport).fetch(rest(retry: RetryPolicy(maxAttempts: 2, baseDelay: 0.1)), context: exampleNet)
        XCTAssertEqual(result.status, .failed("The request timed out"))
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRetryAfterHeaderIsHonoured() async {
        let transport = MockTransport { _, n in
            n == 1 ? HTTPResponse(status: 429, headers: ["Retry-After": "7"], body: Data()) : HTTPResponse(status: 200, body: Data("1".utf8))
        }
        let sleeper = SleepRecorder()
        let result = await makeEngine(transport, sleeper: sleeper).fetch(rest(), context: exampleNet)
        XCTAssertEqual(result.value, 1)
        XCTAssertEqual(sleeper.delays, [7])
    }

    func testCacheTTLAvoidsSecondRequest() async {
        let transport = MockTransport.json("{\"n\":1}")
        let engine = makeEngine(transport)
        let first = await engine.fetch(rest(cacheTTL: 300), context: exampleNet)
        let second = await engine.fetch(rest(cacheTTL: 300), context: exampleNet)
        XCTAssertFalse(first.fromCache)
        XCTAssertTrue(second.fromCache)
        XCTAssertEqual(second.value, ["n": 1])
        XCTAssertEqual(transport.requests.count, 1)
        let stats = await engine.stats
        XCTAssertEqual(stats.cacheHits, 1)
    }

    func testOfflineFallsBackToLastGoodValueEvenAfterRelaunch() async {
        let db = InMemoryDocumentStore()
        let online = makeEngine(MockTransport.json("{\"temp\":21}"), store: db)
        let good = await online.fetch(rest(), context: exampleNet)
        XCTAssertEqual(good.status, .ok)

        // A fresh engine (as after an app restart) that cannot reach the network.
        let offlineTransport = MockTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let offline = makeEngine(offlineTransport, store: db)
        let result = await offline.fetch(rest(retry: .none), context: exampleNet)
        XCTAssertEqual(result.value, ["temp": 21])
        XCTAssertTrue(result.fromCache)
        guard case .stale = result.status else { return XCTFail("expected a stale status, got \(result.status)") }
        XCTAssertNotNil(result.fetchedAt)
    }

    func testOfflineWithoutCacheFails() async {
        let transport = MockTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let result = await makeEngine(transport).fetch(rest(retry: .none), context: exampleNet)
        guard case .failed = result.status else { return XCTFail("expected failure") }
        XCTAssertNil(result.value)
    }

    func testValidationRejectsUnexpectedShape() async {
        var config = rest()
        config.requiredPaths = ["current.temperature"]
        let result = await makeEngine(MockTransport.json("{\"error\":\"bad key\"}")).fetch(config, context: exampleNet)
        XCTAssertEqual(result.status, .failed("Response is missing \"current.temperature\""))
        XCTAssertNil(result.value)
    }

    func testHostOutsideAllowlistIsNeverContacted() async {
        let transport = MockTransport.json("{}")
        let engine = makeEngine(transport)
        let result = await engine.fetch(rest("https://evil.example.org/collect"), context: exampleNet)
        guard case .needsSetup = result.status else { return XCTFail("expected needsSetup") }
        XCTAssertTrue(transport.requests.isEmpty)
        let revoked = await engine.fetch(rest(), context: FetchContext(permissions: .none))
        guard case .needsSetup = revoked.status else { return XCTFail("expected needsSetup") }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRevokedPermissionHidesCachedData() async {
        let engine = makeEngine(MockTransport.json("{\"secret\":1}"))
        _ = await engine.fetch(rest(), context: exampleNet)
        let after = await engine.fetch(rest(), context: FetchContext(permissions: .none))
        XCTAssertNil(after.value, "cached data must not leak after a permission is revoked")
    }

    func testSecretsAreInjectedOnlyForBoundHosts() async throws {
        let secrets = InMemorySecretStore(["TOKEN": Secret(value: "s3cr3t/+", hosts: ["api.example.com"])])
        let transport = MockTransport.json("{}")
        let engine = makeEngine(transport, secrets: secrets)

        let ok = await engine.fetch(rest("https://api.example.com/q?token={{secret:TOKEN}}", headers: ["Authorization": "Bearer {{secret:TOKEN}}"]), context: exampleNet)
        XCTAssertEqual(ok.status, .ok)
        XCTAssertEqual(transport.requests[0].headers["Authorization"], "Bearer s3cr3t/+")
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://api.example.com/q?token=s3cr3t%2F%2B")

        // A widget allowed to talk to another host cannot borrow a secret bound elsewhere.
        let other = FetchContext(permissions: PermissionManifest(network: ["collector.example.net"]))
        let stolen = await engine.fetch(rest("https://collector.example.net/?k={{secret:TOKEN}}"), context: other)
        guard case .needsSetup(let message) = stolen.status else { return XCTFail("expected needsSetup") }
        XCTAssertTrue(message.contains("not approved"))
        XCTAssertEqual(transport.requests.count, 1)

        let missing = await engine.fetch(rest(headers: ["X-Api-Key": "{{secret:NOPE}}"]), context: exampleNet)
        XCTAssertEqual(missing.status, .needsSetup("Add the \"NOPE\" secret in Settings → Secrets"))
    }

    func testSettingsPlaceholders() async {
        let transport = MockTransport.json("[]")
        let engine = makeEngine(transport)
        let config = rest("https://api.example.com/users/{{settings.username}}/events")
        let unset = await engine.fetch(config, context: exampleNet)
        XCTAssertEqual(unset.status, .needsSetup("Set \"username\" in the widget's settings"))
        var context = exampleNet
        context.settings = ["username": "octo cat"]
        let set = await engine.fetch(config, context: context)
        XCTAssertEqual(set.status, .ok)
        XCTAssertEqual(transport.requests.last?.url.absoluteString, "https://api.example.com/users/octo%20cat/events")
    }

    func testLocalHTTPRequiresLocalAddress() async {
        let transport = MockTransport.json("{\"up\":true}")
        let engine = makeEngine(transport)
        let local = DataSourceConfig(id: "svc", kind: .localHTTP, url: "http://localhost:8080/health")
        let ok = await engine.fetch(local, context: FetchContext(permissions: PermissionManifest(network: ["localhost"])))
        XCTAssertEqual(ok.value, ["up": true])
        let remote = DataSourceConfig(id: "svc", kind: .localHTTP, url: "http://api.example.com/health")
        let denied = await engine.fetch(remote, context: exampleNet)
        guard case .needsSetup = denied.status else { return XCTFail("expected needsSetup") }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testConcurrentIdenticalRequestsShareOneFetch() async {
        let transport = MockTransport.json("{\"v\":1}")
        let engine = makeEngine(transport)
        async let a = engine.fetch(rest(cacheTTL: 60), context: exampleNet)
        async let b = engine.fetch(rest(cacheTTL: 60), context: exampleNet)
        async let c = engine.fetch(rest(cacheTTL: 60), context: exampleNet)
        let results = await [a, b, c]
        XCTAssertTrue(results.allSatisfy { $0.value == ["v": 1] })
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testFileSourcesNeedAnAuthorisedFile() async {
        let files = MockFiles(files: ["f1": Data("{\"a\":1}".utf8), "f2": Data("x,y\n1,2\n".utf8)])
        let engine = makeEngine(MockTransport.json(""), files: files)
        let granted = FetchContext(permissions: PermissionManifest(files: ["f1", "f2"]))
        let json = await engine.fetch(DataSourceConfig(id: "j", kind: .jsonFile, fileID: "f1"), context: granted)
        XCTAssertEqual(json.value, ["a": 1])
        let csv = await engine.fetch(DataSourceConfig(id: "c", kind: .csvFile, fileID: "f2"), context: granted)
        XCTAssertEqual(csv.value, [["x": 1, "y": 2]])
        let denied = await engine.fetch(DataSourceConfig(id: "j", kind: .jsonFile, fileID: "f1"), context: FetchContext(permissions: .none))
        XCTAssertEqual(denied.status, .needsSetup("Choose a file for this data source"))
    }

    func testSystemMetricsRequirePermission() async {
        let metrics = StaticMetricsProvider(["cpu": ["usage": 0.25]])
        let engine = makeEngine(MockTransport.json(""), metrics: metrics)
        let allowed = await engine.fetch(.metric("cpu"), context: FetchContext(permissions: PermissionManifest(systemMetrics: true)))
        XCTAssertEqual(allowed.value, ["usage": 0.25])
        let denied = await engine.fetch(.metric("cpu"), context: FetchContext(permissions: .none))
        guard case .needsSetup = denied.status else { return XCTFail("expected needsSetup") }
    }

    func testIntervalsAreClamped() {
        XCTAssertEqual(rest(interval: 0.1).effectiveInterval, 15)
        XCTAssertEqual(rest(interval: 0).effectiveInterval, 0)
        XCTAssertEqual(rest(interval: 120).effectiveInterval, 120)
        XCTAssertEqual(DataSourceConfig.metric("cpu", interval: 0.01).effectiveInterval, 1)
        XCTAssertEqual(RetryPolicy().delay(afterAttempt: 1), 1)
        XCTAssertEqual(RetryPolicy().delay(afterAttempt: 3), 4)
        XCTAssertEqual(RetryPolicy().delay(afterAttempt: 30), 60)
    }

    func testPollingStopsWhenSuspendedAndOnUnsubscribe() async {
        let transport = MockTransport.json("{\"tick\":1}")
        let engine = makeEngine(transport, tick: 0.002)     // every poll interval becomes a 2 ms sleep
        let collector = ResultCollector()
        await engine.subscribe(owner: "w1", config: rest(interval: 30), context: exampleNet) { collector.add($0) }
        let started = await eventually { collector.results.count >= 3 }
        XCTAssertTrue(started)

        await engine.suspend()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let whileSuspended = transport.requests.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(transport.requests.count, whileSuspended, "no requests while suspended")

        await engine.resume()
        let resumed = await eventually { transport.requests.count > whileSuspended }
        XCTAssertTrue(resumed)

        await engine.unsubscribe(owner: "w1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        let afterStop = transport.requests.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(transport.requests.count, afterStop, "no requests after unsubscribe")
        let remaining = await engine.activeSubscriptionCount
        XCTAssertEqual(remaining, 0)
    }

    func testOneShotSourceFetchesOnce() async {
        let transport = MockTransport.json("1")
        let engine = makeEngine(transport)
        let collector = ResultCollector()
        await engine.subscribe(owner: "w", config: rest(interval: 0), context: exampleNet) { collector.add($0) }
        let got = await eventually { collector.results.count == 1 }
        XCTAssertTrue(got)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testWebSocketStreamDeliversAndFallsBack() async {
        struct FakeStream: StreamTransport {
            func messages(url: URL, headers: [String: String]) -> AsyncThrowingStream<Data, Error> {
                AsyncThrowingStream { c in
                    c.yield(Data("{\"price\":101}".utf8))
                    c.finish(throwing: URLError(.networkConnectionLost))
                }
            }
        }
        let engine = makeEngine(MockTransport.json(""), streams: FakeStream(), tick: 0.002)
        let collector = ResultCollector()
        let config = DataSourceConfig(id: "ws", kind: .webSocket, url: "wss://api.example.com/stream", retry: RetryPolicy(maxAttempts: 1, baseDelay: 30))
        await engine.subscribe(owner: "w", config: config, context: exampleNet) { collector.add($0) }
        let delivered = await eventually { collector.results.count >= 2 }
        XCTAssertTrue(delivered)
        XCTAssertEqual(collector.results[0].value, ["price": 101])
        XCTAssertEqual(collector.results[0].status, .ok)
        guard case .stale = collector.results[1].status else { return XCTFail("expected stale after disconnect") }
        XCTAssertEqual(collector.results[1].value, ["price": 101])
        await engine.unsubscribe(owner: "w")

        let blocked = ResultCollector()
        await engine.subscribe(owner: "x", config: config, context: FetchContext(permissions: .none)) { blocked.add($0) }
        let refused = await eventually { blocked.results.count == 1 }
        XCTAssertTrue(refused)
        guard case .needsSetup = blocked.results[0].status else { return XCTFail("expected needsSetup") }
    }
}
