import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class ConflictTests: XCTestCase {
    private func kinds(_ conflicts: [BindingConflict]) -> [BindingConflict.Kind] { conflicts.map(\.kind) }

    func testCleanProfileHasNoConflicts() {
        let profile = Profile(name: "P", bindings: [Fixtures.binding(.twoFingerTap), Fixtures.binding(.pinchIn)])
        XCTAssertTrue(ConflictDetector.conflicts(in: profile, global: nil, capabilities: Fixtures.allCapabilities).isEmpty)
    }

    func testDuplicateTrigger() {
        let first = Fixtures.binding(.twoFingerTap), second = Fixtures.binding(.twoFingerTap, .system(.launchpad))
        let disabled = Fixtures.binding(.twoFingerTap, enabled: false)
        let profile = Profile(name: "P", bindings: [first, second, disabled])
        let conflicts = ConflictDetector.conflicts(in: profile, global: nil)
        XCTAssertEqual(kinds(conflicts), [.duplicateTrigger])
        XCTAssertEqual(conflicts[0].severity, .error)
        XCTAssertEqual(conflicts[0].bindingIDs, [first.id, second.id])
        XCTAssertTrue(conflicts[0].message.contains("first"))

        var prioritised = profile
        prioritised.bindings[1].priority = 2
        XCTAssertTrue(ConflictDetector.conflicts(in: prioritised, global: nil)[0].message.contains("highest priority"))
    }

    func testShadowingGlobalIsNotAConflict() {
        let global = Profile(name: "Global", bindings: [Fixtures.binding(.twoFingerTap)])
        let app = Profile(name: "App", bundleIdentifiers: ["a"], bindings: [Fixtures.binding(.twoFingerTap, .system(.mute))])
        XCTAssertTrue(ConflictDetector.conflicts(in: app, global: global).isEmpty)
    }

    func testTapIsDelayedByDoubleTapAndTapThenSwipe() {
        let tap = Fixtures.binding(.oneFingerTap, .system(.mute)), double = Fixtures.binding(.oneFingerDoubleTap, .system(.mute))
        let corner = Fixtures.binding(.cornerTapTopLeft), compound = Fixtures.binding(.tapThenSwipeLeft)
        let profile = Profile(name: "P", bindings: [tap, double, corner, compound])
        let delays = ConflictDetector.conflicts(in: profile, global: nil).filter { $0.kind == .delaysOther }
        XCTAssertEqual(delays.count, 2)
        XCTAssertEqual(delays[0].bindingIDs, [tap.id, double.id, compound.id])
        XCTAssertEqual(delays[1].bindingIDs.first, corner.id)
        XCTAssertTrue(delays.allSatisfy { $0.severity == .info })

        let twoFinger = Profile(name: "P", bindings: [Fixtures.binding(.twoFingerTap), Fixtures.binding(.threeFingerTap)])
        XCTAssertTrue(ConflictDetector.conflicts(in: twoFinger, global: nil).isEmpty, "different finger counts do not delay")
        let twoFingerDouble = Profile(name: "P", bindings: [Fixtures.binding(.twoFingerTap), Fixtures.binding(.pinchIn)])
        let candidate = Fixtures.binding(.twoFingerDoubleTap)
        let added = ConflictDetector.conflicts(adding: candidate, to: twoFingerDouble, global: nil)
        XCTAssertEqual(Set(kinds(added)), [.delaysOther, .overlapsSystemGesture])
    }

    func testHoldIsDelayedByHoldThenSwipe() {
        let hold = Fixtures.binding(.oneFingerHold), compound = Fixtures.binding(.holdThenSwipeUp)
        let profile = Profile(name: "P", bindings: [hold, compound])
        let conflicts = ConflictDetector.conflicts(in: profile, global: nil)
        XCTAssertEqual(kinds(conflicts), [.delaysOther])
        XCTAssertEqual(conflicts[0].bindingIDs, [hold.id, compound.id])
    }

    func testInheritedGlobalBindingsTakePartInTimingChecks() {
        let globalTap = Fixtures.binding(.centerTap, .mouse(.middleClick))
        let global = Profile(name: "Global", bindings: [globalTap])
        let double = Fixtures.binding(.tapThenSwipeUp)
        let app = Profile(name: "App", bundleIdentifiers: ["a"], bindings: [double])
        let conflicts = ConflictDetector.conflicts(in: app, global: global)
        XCTAssertEqual(kinds(conflicts), [.delaysOther])
        XCTAssertEqual(conflicts[0].bindingIDs, [globalTap.id, double.id])

        var isolated = app
        isolated.inheritsGlobal = false
        XCTAssertTrue(ConflictDetector.conflicts(in: isolated, global: global).isEmpty)
        XCTAssertTrue(ConflictDetector.conflicts(in: global, global: global).isEmpty)
    }

    func testSystemOverlaps() {
        let scroll = Fixtures.binding(.oneFingerSwipeUp), sideways = Fixtures.binding(.oneFingerSwipeLeft)
        let fullScreen = Fixtures.binding(.twoFingerSwipeRight)
        let click = Fixtures.binding(.oneFingerTap, .mouse(.leftClick))
        let harmless = Fixtures.binding(.twoFingerSwipeUp)
        let off = Fixtures.binding(.oneFingerSwipeDown, enabled: false)
        let profile = Profile(name: "P", bindings: [scroll, sideways, fullScreen, click, harmless, off])
        let conflicts = ConflictDetector.conflicts(in: profile, global: nil)
        XCTAssertEqual(kinds(conflicts), Array(repeating: .overlapsSystemGesture, count: 4))
        XCTAssertEqual(conflicts.map(\.bindingIDs), [[scroll.id], [sideways.id], [fullScreen.id], [click.id]])
        XCTAssertEqual(conflicts.map(\.severity), [.warning, .warning, .warning, .info])
        XCTAssertTrue(conflicts[0].message.contains("scroll"))
        XCTAssertTrue(conflicts[2].message.contains("full-screen"))
        XCTAssertTrue(conflicts.allSatisfy { !$0.message.isEmpty })

        let nonClick = Profile(name: "P", bindings: [Fixtures.binding(.oneFingerTap, .system(.mute))])
        XCTAssertTrue(ConflictDetector.conflicts(in: nonClick, global: nil).isEmpty)
    }

    func testUnavailableGestures() {
        let touch = Fixtures.binding(.twoFingerTap), three = Fixtures.binding(.threeFingerTap)
        let chord = Fixtures.binding(.chordLeftClick)
        let profile = Profile(name: "P", bindings: [touch, three, chord])
        XCTAssertTrue(ConflictDetector.conflicts(in: profile, global: nil).isEmpty, "no capabilities, no availability check")

        let fallback = ConflictDetector.conflicts(in: profile, global: nil, capabilities: Fixtures.fallbackOnly)
        XCTAssertEqual(kinds(fallback), [.unavailableGesture, .unavailableGesture])
        XCTAssertEqual(fallback.map(\.bindingIDs), [[touch.id], [three.id]])
        XCTAssertTrue(fallback[0].message.contains("raw finger positions"))

        let twoFingers = InputCapabilities(rawContacts: true, maxContacts: 2, contactSize: true, pointerEvents: false)
        let limited = ConflictDetector.conflicts(in: profile, global: nil, capabilities: twoFingers)
        XCTAssertEqual(limited.map(\.bindingIDs), [[three.id], [chord.id]])
        XCTAssertTrue(limited[0].message.contains("3 fingers"))
        XCTAssertTrue(limited[1].message.contains("Accessibility"))
        XCTAssertNil(ConflictDetector.unavailabilityReason(for: .twoFingerTap, capabilities: twoFingers))
        XCTAssertNotNil(ConflictDetector.unavailabilityReason(for: .chordLeftClick, capabilities: twoFingers))
    }

    func testSequencePrefixes() {
        let single = Fixtures.binding(.twoFingerTap)
        let short = GestureBinding(trigger: .sequence([.twoFingerTap, .pinchIn]), action: .system(.mute))
        let long = GestureBinding(trigger: .sequence([.twoFingerTap, .pinchIn, .pinchOut]), action: .system(.mute))
        let unrelated = GestureBinding(trigger: .sequence([.pinchIn, .twoFingerTap]), action: .system(.mute))
        let profile = Profile(name: "P", bindings: [single, short, long, unrelated])
        let conflicts = ConflictDetector.conflicts(in: profile, global: nil).filter { $0.kind == .sequencePrefix }
        XCTAssertEqual(Set(conflicts.map(\.bindingIDs)), [[single.id, short.id], [single.id, long.id], [short.id, long.id]])
        XCTAssertEqual(conflicts.first { $0.bindingIDs == [short.id, long.id] }?.severity, .warning)
        XCTAssertEqual(conflicts.first { $0.bindingIDs == [single.id, short.id] }?.severity, .info)

        let twin = GestureBinding(trigger: .sequence([.twoFingerTap, .pinchIn]), action: .system(.launchpad))
        let equal = ConflictDetector.conflicts(adding: twin, to: profile, global: nil)
        XCTAssertTrue(equal.contains { $0.kind == .duplicateTrigger && $0.bindingIDs == [short.id, twin.id] })
    }

    func testAddingCandidateReportsOnlyItsOwnConflicts() {
        let existingA = Fixtures.binding(.pinchIn), existingB = Fixtures.binding(.pinchIn, .system(.mute))
        let profile = Profile(name: "P", bindings: [existingA, existingB, Fixtures.binding(.twoFingerTap)])
        XCTAssertTrue(ConflictDetector.conflicts(adding: Fixtures.binding(.pinchOut), to: profile, global: nil).isEmpty)

        let candidate = Fixtures.binding(.twoFingerTap, .system(.launchpad))
        let conflicts = ConflictDetector.conflicts(adding: candidate, to: profile, global: nil)
        XCTAssertEqual(kinds(conflicts), [.duplicateTrigger])
        XCTAssertTrue(conflicts[0].bindingIDs.contains(candidate.id))

        // Replacing a binding (same id) does not conflict with its old self.
        var replacement = profile.bindings[2]
        replacement.action = .system(.launchpad)
        XCTAssertTrue(ConflictDetector.conflicts(adding: replacement, to: profile, global: nil).isEmpty)
        replacement.trigger = .single(.pinchIn)
        XCTAssertEqual(kinds(ConflictDetector.conflicts(adding: replacement, to: profile, global: nil)), [.duplicateTrigger])

        let configuration = Fixtures.configuration(global: [Fixtures.binding(.oneFingerDoubleTap, enabled: false)])
        let global = configuration.profiles[0]
        let risky = Fixtures.binding(.oneFingerSwipeUp)
        XCTAssertEqual(kinds(ConflictDetector.conflicts(adding: risky, to: global, configuration: configuration,
                                                        capabilities: Fixtures.fallbackOnly)),
                       [.overlapsSystemGesture, .unavailableGesture])
    }

    func testConflictIdentifiersAreStable() {
        let profile = Profile(name: "P", bindings: [Fixtures.binding(.oneFingerSwipeUp), Fixtures.binding(.oneFingerSwipeDown)])
        let first = ConflictDetector.conflicts(in: profile, global: nil)
        let second = ConflictDetector.conflicts(in: profile, global: nil)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)).count, 2)
    }

    func testDefaultProfilesHaveNoErrorsOrWarnings() {
        let configuration = DefaultConfiguration.make()
        for profile in configuration.profiles + [DefaultProfiles.windowManagement()] {
            let conflicts = ConflictDetector.conflicts(in: profile, configuration: configuration,
                                                       capabilities: Fixtures.allCapabilities)
            XCTAssertTrue(conflicts.isEmpty, "\(profile.name): \(conflicts.map(\.message))")
        }
    }
}
