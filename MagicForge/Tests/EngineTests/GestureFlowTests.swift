import XCTest
import MFCore
import MFUtilities
import MFGestures
import MFProfiles
@testable import MFEngine

final class GestureFlowTests: XCTestCase {
    @MainActor func testGestureRunsBoundActionExactlyOnce() async {
        let harness = Harness()
        harness.model.start()
        var seen: [GestureKind] = []
        harness.model.onGesture = { seen.append($0.kind) }

        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        await harness.settle()

        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA])
        XCTAssertEqual(seen, [.twoFingerTap])
        XCTAssertEqual(harness.model.recentGestures.count, 1)
        XCTAssertEqual(harness.model.recentGestures.first?.event.kind, .twoFingerTap)
        XCTAssertEqual(harness.model.recentGestures.first?.profileName, "Global")
        XCTAssertNotNil(harness.model.recentGestures.first?.actionName)
        XCTAssertNil(harness.model.recentGestures.first?.failure)
        XCTAssertEqual(harness.model.metrics.gesturesRecognized, 1)
        XCTAssertEqual(harness.model.metrics.actionsExecuted, 1)
        XCTAssertEqual(harness.model.metrics.actionFailures, 0)
        harness.model.stop()
    }

    @MainActor func testFramesFromBackgroundThreadAreRecognized() async {
        let harness = Harness()
        harness.model.start()
        let adapter = harness.adapter
        let frames = TestFrames.gesture(.twoFingerTap)
        Thread.detachNewThread { adapter.push(frames) }
        await harness.wait("action") { harness.performer.performed.count == 1 }
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA])
        harness.model.stop()
    }

    @MainActor func testAppSpecificProfileChangesAction() async {
        let harness = Harness()
        harness.model.start()
        let globalID = harness.model.configuration.globalProfileID
        XCTAssertEqual(harness.model.activeProfileID, globalID)

        harness.frontmost.activate(TestConfig.appBundleID)
        XCTAssertEqual(harness.model.frontmostBundleID, TestConfig.appBundleID)
        XCTAssertEqual(harness.model.activeProfile?.name, "Editor")
        harness.perform(.twoFingerTap)
        await harness.wait("app action") { harness.performer.performed.count == 1 }
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyB])
        XCTAssertEqual(harness.model.recentGestures.first?.profileName, "Editor")

        harness.frontmost.activate("com.example.other")
        XCTAssertEqual(harness.model.activeProfileID, globalID)
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("global action") { harness.performer.performed.count == 2 }
        XCTAssertEqual(harness.performer.performed.last, TestConfig.keyA)
        harness.model.stop()
    }

    @MainActor func testProfileOverrideAndNextProfileControl() async {
        let harness = Harness()
        harness.model.start()
        let editorID = harness.model.configuration.profiles[1].id
        harness.model.setProfileOverride(editorID)
        XCTAssertEqual(harness.model.activeProfileID, editorID)
        XCTAssertEqual(harness.model.effectiveBindings.map(\.action), [TestConfig.keyB])

        harness.model.setProfileOverride(UUID()) // unknown: ignored
        XCTAssertEqual(harness.model.profileOverrideID, editorID)

        let cleared = await harness.model.run(.control(.clearProfileOverride), source: .manualTest)
        XCTAssertEqual(try? cleared.get() == (), true)
        XCTAssertNil(harness.model.profileOverrideID)

        _ = await harness.model.run(.control(.nextProfile), source: .manualTest)
        XCTAssertEqual(harness.model.activeProfileID, editorID)
        _ = await harness.model.run(.control(.nextProfile), source: .manualTest)
        XCTAssertEqual(harness.model.activeProfileID, harness.model.configuration.globalProfileID)

        harness.model.setProfileOverride(editorID)
        harness.model.deleteProfile(editorID)
        XCTAssertNil(harness.model.profileOverrideID)
        XCTAssertEqual(harness.model.configuration.profiles.count, 1)
        harness.model.deleteProfile(harness.model.configuration.globalProfileID)
        XCTAssertEqual(harness.model.configuration.profiles.count, 1, "the global profile cannot be deleted")
        harness.model.stop()
    }

    @MainActor func testPausePreventsExecutionButStillRecords() async {
        let harness = Harness()
        harness.model.start()
        harness.model.setPaused(true)
        XCTAssertTrue(harness.model.isPaused)
        harness.perform(.twoFingerTap)
        await harness.wait("record") { harness.model.recentGestures.count == 1 }
        await harness.settle()
        XCTAssertTrue(harness.performer.performed.isEmpty)
        XCTAssertNil(harness.model.recentGestures.first?.actionName)

        let toggled = await harness.model.run(.control(.toggleGesturesPaused), source: .menuBar)
        XCTAssertNotNil(try? toggled.get())
        XCTAssertFalse(harness.model.isPaused)
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        harness.model.stop()
    }

    @MainActor func testSuppressActionsReportsEveryGestureWithoutExecuting() async {
        let harness = Harness()
        harness.model.start()
        var seen: [GestureKind] = []
        harness.model.onGesture = { seen.append($0.kind) }
        harness.model.suppressActions = true

        harness.perform(.twoFingerTap)
        await harness.wait("bound gesture") { seen.contains(.twoFingerTap) }
        // Not bound anywhere, but test mode listens for every gesture.
        harness.perform(.threeFingerSwipeUp)
        await harness.wait("unbound gesture") { seen.contains(.threeFingerSwipeUp) }
        await harness.settle()
        XCTAssertTrue(harness.performer.performed.isEmpty)

        harness.model.suppressActions = false
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        harness.model.stop()
    }

    @MainActor func testUnboundGestureExecutesNothing() async {
        // Three-finger tap is only part of a sequence, so the recognizer emits it, but alone it is unbound.
        let sequence = GestureBinding(trigger: .sequence([.threeFingerTap, .twoFingerTap]), action: TestConfig.keyC)
        let harness = Harness(configuration: TestConfig.with([sequence]))
        harness.model.start()
        harness.perform(.threeFingerTap)
        await harness.wait("record", timeout: 4) { harness.model.recentGestures.count == 1 }
        await harness.settle()
        XCTAssertTrue(harness.performer.performed.isEmpty)
        XCTAssertNil(harness.model.recentGestures.first?.actionName)
        XCTAssertEqual(harness.model.metrics.actionsExecuted, 0)
        harness.model.stop()
    }

    @MainActor func testSequenceTriggerRunsItsBindingOnce() async {
        let sequence = GestureBinding(trigger: .sequence([.threeFingerTap, .twoFingerTap]), action: TestConfig.keyC)
        let single = GestureBinding(trigger: .single(.twoFingerTap), action: TestConfig.keyA)
        let harness = Harness(configuration: TestConfig.with([sequence, single]))
        harness.model.start()
        harness.perform(.threeFingerTap)
        await harness.settle(0.1)
        harness.perform(.twoFingerTap)
        await harness.wait("sequence action") { !harness.performer.performed.isEmpty }
        await harness.settle(0.8)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyC])
        harness.model.stop()
    }

    @MainActor func testPendingTapIsResolvedByTheDeadlineTimer() async {
        let tap = GestureBinding(trigger: .single(.oneFingerTap), action: TestConfig.keyA)
        let doubleTap = GestureBinding(trigger: .single(.oneFingerDoubleTap), action: TestConfig.keyB)
        let harness = Harness(configuration: TestConfig.with([tap, doubleTap]))
        harness.model.start()
        harness.perform(.oneFingerTap)
        // No further frames arrive: only the pipeline's deadline timer can release the single tap.
        await harness.wait("single tap") { harness.performer.performed.count == 1 }
        await harness.settle(0.4)
        XCTAssertEqual(harness.performer.performed, [TestConfig.keyA])
        harness.model.stop()
    }

    @MainActor func testSlowActionIsNotStartedTwice() async {
        let harness = Harness()
        harness.performer.duration = 0.6
        harness.model.start()
        harness.perform(.twoFingerTap)
        await harness.wait("first record") { harness.model.recentGestures.count == 1 }
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("second record") { harness.model.recentGestures.count == 2 }
        XCTAssertNotNil(harness.model.recentGestures.first?.failure, "the repeat is skipped while the first run is active")
        await harness.wait("action") { harness.performer.performed.count == 1 }
        await harness.settle(0.3)
        XCTAssertEqual(harness.performer.performed.count, 1)
        harness.model.stop()
    }

    @MainActor func testKeepRecentGesturesOffRecordsNothing() async {
        let harness = Harness()
        harness.model.start()
        harness.model.update { $0.settings.keepRecentGestures = false }
        harness.perform(.twoFingerTap)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        XCTAssertTrue(harness.model.recentGestures.isEmpty)
        harness.model.stop()
    }

    @MainActor func testUntrustedScriptIsRefusedUntilApproved() async {
        let script = ScriptAction.shell(command: "echo hello")
        let binding = GestureBinding(trigger: .single(.twoFingerTap), action: .script(script))
        let harness = Harness(configuration: TestConfig.with([binding]))
        harness.model.start()
        XCTAssertFalse(harness.model.isTrusted(script))
        XCTAssertEqual(harness.model.untrustedScripts(), [script])

        harness.perform(.twoFingerTap)
        await harness.wait("failure") { harness.model.recentGestures.first?.failure != nil }
        XCTAssertTrue(harness.performer.performed.isEmpty)
        XCTAssertEqual(harness.model.metrics.actionFailures, 1)
        XCTAssertEqual(harness.model.activityLog.first?.level, .error)
        let direct = await harness.model.run(.script(script), source: .manualTest)
        XCTAssertEqual(direct.failureValue, .untrusted)

        // Editing through update cannot smuggle in an approval.
        harness.model.update { $0.approvedScriptHashes.insert(ScriptTrust.hash(of: script)) }
        XCTAssertFalse(harness.model.isTrusted(script))

        harness.model.approve(script)
        XCTAssertTrue(harness.model.isTrusted(script))
        XCTAssertTrue(harness.model.untrustedScripts().isEmpty)
        await harness.settle(0.25)
        harness.perform(.twoFingerTap)
        await harness.wait("script action") { harness.performer.performed.count == 1 }
        XCTAssertEqual(harness.performer.performed, [.script(script)])

        harness.model.revokeApproval(script)
        XCTAssertFalse(harness.model.isTrusted(script))
        harness.model.stop()
    }

    @MainActor func testPermissionDenialPropagates() async {
        let harness = Harness()
        harness.model.start()
        harness.performer.error = .permissionDenied(.accessibility)
        let result = await harness.model.run(TestConfig.keyA, source: .manualTest)
        XCTAssertEqual(result.failureValue, .permissionDenied(.accessibility))

        harness.perform(.twoFingerTap)
        await harness.wait("failure") { harness.model.recentGestures.first?.failure != nil }
        XCTAssertEqual(harness.model.metrics.actionFailures, 2)
        XCTAssertEqual(harness.model.metrics.actionsExecuted, 0)
        harness.model.stop()
    }

    @MainActor func testSyntheticPlaybackGoesThroughThePipeline() async {
        let harness = Harness()
        harness.model.start()
        let frames = SyntheticTouch.frames(for: .twoFingerTap, startTime: 100)
        harness.model.playSynthetic(frames, realtime: false)
        await harness.wait("action") { harness.performer.performed.count == 1 }
        await harness.wait("playback end") { !harness.model.isSyntheticInputActive }
        XCTAssertTrue(harness.model.touchFeed.snapshot().isSynthetic)

        harness.model.playSynthetic(SyntheticTouch.frames(for: .twoFingerTap, startTime: 5), realtime: true)
        XCTAssertTrue(harness.model.isSyntheticInputActive)
        await harness.wait("realtime action") { harness.performer.performed.count == 2 }
        await harness.wait("realtime end") { !harness.model.isSyntheticInputActive }

        // Stopping a long playback ends it at once and nothing more is recognized.
        harness.model.playSynthetic(SyntheticTouch.demoReel(startTime: 0), realtime: true)
        XCTAssertTrue(harness.model.isSyntheticInputActive)
        harness.model.stopSynthetic()
        XCTAssertFalse(harness.model.isSyntheticInputActive)
        let recognized = harness.model.metrics.gesturesRecognized
        await harness.settle(0.3)
        XCTAssertEqual(harness.model.metrics.gesturesRecognized, recognized)
        harness.model.stop()
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
