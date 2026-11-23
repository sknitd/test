import XCTest
import MFCore
import MFUtilities
import MFGestures
@testable import MFEngine

final class InputTests: XCTestCase {
    @MainActor func testCapabilitiesMergeAdapterAndEventTap() async {
        let harness = Harness()
        harness.model.start()
        XCTAssertEqual(harness.model.adapterStatus.state, .running)
        XCTAssertEqual(harness.model.adapterStatus.identifier, "mock")
        XCTAssertTrue(harness.model.adapterStatus.capabilities.rawContacts)
        XCTAssertEqual(harness.model.adapterStatus.capabilities.maxContacts, 5)
        XCTAssertTrue(harness.model.adapterStatus.capabilities.pointerEvents)
        XCTAssertEqual(harness.model.availability(of: .twoFingerTap), .available)
        XCTAssertEqual(harness.model.availability(of: .chordLeftClick), .available)
        harness.model.stop()
        XCTAssertEqual(harness.model.adapterStatus.state, .stopped)
        XCTAssertEqual(harness.model.adapterStatus.capabilities, .none)
    }

    @MainActor func testFingerCountBeyondAdapterLimitIsUnavailable() async {
        let adapter = MockAdapter()
        adapter.capabilities = InputCapabilities(rawContacts: true, maxContacts: 2, contactSize: false, pointerEvents: false)
        let harness = Harness(adapter: adapter)
        harness.model.start()
        XCTAssertEqual(harness.model.availability(of: .twoFingerTap), .available)
        guard case .unavailable(let reason) = harness.model.availability(of: .threeFingerTap) else {
            return XCTFail("three fingers cannot be available with two contacts")
        }
        XCTAssertTrue(reason.contains("3"))
        harness.model.stop()
    }

    @MainActor func testAdapterUnavailableKeepsFallbackChordsWorking() async {
        let adapter = MockAdapter()
        adapter.availability = .unavailable(reason: "MultitouchSupport could not be loaded.")
        let chord = GestureBinding(trigger: .single(.chordLeftClick), action: TestConfig.keyC)
        let tap = GestureBinding(trigger: .single(.twoFingerTap), action: TestConfig.keyA)
        let harness = Harness(configuration: TestConfig.with([chord, tap]), adapter: adapter)
        harness.model.start()

        XCTAssertEqual(harness.model.adapterStatus.state, .unavailable(reason: "MultitouchSupport could not be loaded."))
        XCTAssertFalse(harness.model.adapterStatus.capabilities.rawContacts)
        XCTAssertTrue(harness.model.adapterStatus.capabilities.pointerEvents)
        XCTAssertEqual(harness.model.availability(of: .twoFingerTap),
                       .unavailable(reason: "MultitouchSupport could not be loaded."))
        XCTAssertEqual(harness.model.availability(of: .chordLeftClick), .available)
        XCTAssertEqual(harness.pointer.enabledChords, [.chordLeftClick])
        XCTAssertTrue(harness.model.conflicts(inProfile: harness.model.configuration.globalProfileID)
            .contains { $0.kind == .unavailableGesture })

        let handlers = try! XCTUnwrap(harness.pointer.handlers) // swiftlint:disable:this force_try
        XCTAssertTrue(handlers.onChord(.chordLeftClick, MonotonicClock.now()), "bound chord is swallowed")
        XCTAssertFalse(handlers.onChord(.chordRightClick, MonotonicClock.now()), "unbound chord passes through")
        await harness.wait("chord action") { harness.performer.performed.count == 1 }
        await harness.settle()
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyC])
        XCTAssertEqual(harness.model.recentGestures.map(\.event.kind), [.chordRightClick, .chordLeftClick])
        harness.model.stop()
    }

    @MainActor func testChordIsNotSwallowedWhenUnbound() async {
        let harness = Harness()
        harness.model.start()
        XCTAssertTrue(harness.pointer.enabledChords.isEmpty)
        let handlers = try! XCTUnwrap(harness.pointer.handlers) // swiftlint:disable:this force_try
        for kind in GestureKind.allCases where kind.category == .fallback {
            XCTAssertFalse(handlers.onChord(kind, MonotonicClock.now()))
        }
        XCTAssertFalse(handlers.onChord(.twoFingerTap, MonotonicClock.now()), "not a chord at all")
        harness.model.stop()
    }

    @MainActor func testEventTapWaitsForAccessibility() async {
        let chord = GestureBinding(trigger: .single(.chordScrollUp), action: TestConfig.keyC)
        let harness = Harness(configuration: TestConfig.with([chord]))
        harness.permissions.statuses[.accessibility] = .denied
        harness.pointer.canStart = false
        harness.model.start()

        XCTAssertEqual(harness.model.permissions[.accessibility], .denied)
        XCTAssertFalse(harness.model.adapterStatus.capabilities.pointerEvents)
        XCTAssertTrue(harness.model.adapterStatus.capabilities.rawContacts, "touch input does not need the tap")
        guard case .unavailable(let reason) = harness.model.availability(of: .chordScrollUp) else {
            return XCTFail("chords need the event tap")
        }
        XCTAssertTrue(reason.contains("Accessibility"))
        XCTAssertTrue(harness.model.activityLog.contains { $0.level == .warning })

        harness.model.requestPermission(.accessibility)
        XCTAssertEqual(harness.permissions.requested, [.accessibility])
        harness.model.openPermissionSettings(.accessibility)
        XCTAssertEqual(harness.permissions.openedSettings, [.accessibility])

        harness.permissions.statuses[.accessibility] = .granted
        harness.pointer.canStart = true
        harness.model.refreshPermissions()
        XCTAssertEqual(harness.model.permissions[.accessibility], .granted)
        XCTAssertTrue(harness.pointer.isRunning)
        XCTAssertTrue(harness.model.adapterStatus.capabilities.pointerEvents)
        XCTAssertEqual(harness.model.availability(of: .chordScrollUp), .available)
        XCTAssertEqual(harness.pointer.enabledChords, [.chordScrollUp])
        harness.model.stop()
    }

    @MainActor func testNoPointerSourceMeansNoFallbackTriggers() async {
        let harness = Harness(withPointerSource: false)
        harness.model.start()
        XCTAssertFalse(harness.model.adapterStatus.capabilities.pointerEvents)
        guard case .unavailable = harness.model.availability(of: .chordLeftClick) else {
            return XCTFail("no event source, no chords")
        }
        harness.model.stop()
    }

    @MainActor func testDeviceReconnectStartsInput() async {
        let adapter = MockAdapter()
        adapter.startError = .noDevice
        let harness = Harness(adapter: adapter, devices: [])
        harness.model.start()
        XCTAssertNil(harness.model.connectedDevice)
        guard case .unavailable(let reason) = harness.model.adapterStatus.state else {
            return XCTFail("no device, no touch input")
        }
        XCTAssertTrue(reason.contains("No Magic Mouse"))
        XCTAssertEqual(harness.model.availability(of: .twoFingerTap), .unavailable(reason: reason))

        adapter.startError = nil
        harness.monitor.set([TestConfig.mouse])
        XCTAssertEqual(harness.model.connectedDevice, TestConfig.mouse)
        XCTAssertEqual(harness.model.adapterStatus.state, .running)
        XCTAssertEqual(adapter.startCount, 1)
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }

        // Disconnect and reconnect while running: the adapter is told and keeps streaming.
        var disconnected = TestConfig.mouse
        disconnected.isConnected = false
        harness.monitor.set([disconnected])
        XCTAssertNil(harness.model.connectedDevice)
        harness.monitor.set([TestConfig.mouse])
        XCTAssertEqual(adapter.devicesDidChangeCount, 2)
        XCTAssertEqual(harness.model.adapterStatus.state, .running)
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("action after reconnect") { harness.performer.performed.count == 2 }
        harness.model.stop()
    }

    @MainActor func testPrivateAdapterIsSkippedWhenDisabledInSettings() async {
        let privateAdapter = MockAdapter(identifier: "private", displayName: "Private Multitouch", usesPrivateAPI: true)
        let harness = Harness(configuration: TestConfig.base().with { $0.settings.allowPrivateMultitouch = false },
                              adapter: privateAdapter)
        harness.model.start()
        XCTAssertEqual(privateAdapter.startCount, 0)
        guard case .unavailable(let reason) = harness.model.adapterStatus.state else {
            return XCTFail("the only adapter is private and switched off")
        }
        XCTAssertTrue(reason.contains("Settings"))
        XCTAssertTrue(harness.model.adapterStatus.usesPrivateAPI)

        // Switching the setting on starts it without a relaunch.
        harness.model.update { $0.settings.allowPrivateMultitouch = true }
        XCTAssertEqual(privateAdapter.startCount, 1)
        XCTAssertEqual(harness.model.adapterStatus.state, .running)
        harness.model.update { $0.settings.allowPrivateMultitouch = false }
        XCTAssertFalse(privateAdapter.isStarted)
        harness.model.stop()
    }

    @MainActor func testFirstAvailableAdapterWins() async {
        let privateAdapter = MockAdapter(identifier: "private", usesPrivateAPI: true)
        privateAdapter.availability = .unavailable(reason: "Framework missing.")
        let publicAdapter = MockAdapter(identifier: "public")
        let harness = Harness(adapter: privateAdapter, extraAdapters: [publicAdapter])
        harness.model.start()
        XCTAssertEqual(harness.model.adapterStatus.identifier, "public")
        XCTAssertEqual(privateAdapter.startCount, 0)
        XCTAssertEqual(publicAdapter.startCount, 1)
        harness.model.stop()
    }

    @MainActor func testRestartInputRestartsAdapterAndTap() async {
        let harness = Harness()
        harness.model.start()
        harness.model.restartInput()
        XCTAssertEqual(harness.adapter.startCount, 2)
        XCTAssertEqual(harness.pointer.startAttempts, 2)
        XCTAssertEqual(harness.model.adapterStatus.state, .running)
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        harness.model.stop()
    }

    @MainActor func testStopIsIdempotentAndStopsEverything() async {
        let harness = Harness()
        harness.model.start()
        harness.model.start() // second start is a no-op
        XCTAssertEqual(harness.adapter.startCount, 1)
        harness.model.stop()
        harness.model.stop()
        XCTAssertFalse(harness.model.isRunning)
        XCTAssertFalse(harness.adapter.isStarted)
        XCTAssertFalse(harness.pointer.isRunning)
        XCTAssertFalse(harness.monitor.isStarted)
        XCTAssertFalse(harness.frontmost.isObserving)
        XCTAssertEqual(harness.model.availability(of: .twoFingerTap), .unavailable(reason: "MagicForge is not running."))

        // Starting again works and uses the configuration in memory.
        let loads = harness.memoryStore.loadCount
        harness.model.start()
        XCTAssertEqual(harness.memoryStore.loadCount, loads)
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        harness.model.stop()
    }

    @MainActor func testScrollPassesThroughByDefaultAndRewritesWhenEnabled() async {
        let harness = Harness()
        harness.model.start()
        let handlers = try! XCTUnwrap(harness.pointer.handlers) // swiftlint:disable:this force_try
        func sample(_ dy: Double, fromMouse: Bool = true) -> ScrollSample {
            ScrollSample(deltaX: 0, deltaY: dy, isContinuous: true, isFromMagicMouse: fromMouse, timestamp: MonotonicClock.now())
        }
        XCTAssertFalse(harness.pointer.scrollInterceptionEnabled)
        XCTAssertEqual(handlers.onScroll(sample(10)), .passThrough)

        harness.model.update { configuration in
            var scroll = ScrollSettings()
            scroll.isEnabled = true
            scroll.verticalMultiplier = 2
            configuration.profiles[0].scroll = scroll
        }
        XCTAssertTrue(harness.pointer.scrollInterceptionEnabled)
        XCTAssertEqual(handlers.onScroll(sample(10)), .rewrite(deltaX: 0, deltaY: 20))
        XCTAssertEqual(handlers.onScroll(sample(10, fromMouse: false)), .passThrough, "other devices are left alone")

        // The app profile has its own scroll settings.
        harness.model.update { configuration in
            var scroll = ScrollSettings()
            scroll.isEnabled = true
            scroll.invertVertical = true
            configuration.profiles[1].scroll = scroll
        }
        harness.frontmost.activate(TestConfig.appBundleID)
        XCTAssertEqual(handlers.onScroll(sample(10)), .rewrite(deltaX: 0, deltaY: -10))

        harness.model.update { $0.profiles[0].scroll = nil; $0.profiles[1].scroll = nil }
        XCTAssertFalse(harness.pointer.scrollInterceptionEnabled)
        XCTAssertEqual(handlers.onScroll(sample(10)), .passThrough)
        harness.model.stop()
    }

    @MainActor func testPhysicalClickSuppressesTap() async {
        let harness = Harness()
        harness.model.start()
        let handlers = try! XCTUnwrap(harness.pointer.handlers) // swiftlint:disable:this force_try
        handlers.onButton(0, true, MonotonicClock.now())
        await harness.settle(0.05)
        harness.perform(.twoFingerTap)
        await harness.settle(0.3)
        XCTAssertTrue(harness.performer.performed.isEmpty, "a tap around a physical click is the click itself")
        harness.model.stop()
    }
}
