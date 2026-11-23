import Foundation
import XCTest
import MFCore
@testable import MFProfiles

final class ResolverTests: XCTestCase {
    private let safari = "com.apple.Safari"
    private let finder = "com.apple.finder"

    func testGlobalFallback() {
        let configuration = Fixtures.configuration(global: [Fixtures.binding(.twoFingerTap)])
        for bundleID in [nil, "", "com.unknown.app"] {
            let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: bundleID)
            XCTAssertEqual(resolved.profileID, configuration.globalProfileID)
            XCTAssertEqual(resolved.profileName, "Global")
            XCTAssertEqual(resolved.source, .global)
            XCTAssertEqual(resolved.binding(for: .twoFingerTap)?.action, .system(.missionControl))
            XCTAssertEqual(resolved.enabledKinds, [.twoFingerTap])
        }
    }

    func testAppProfileShadowsAndInheritsGlobal() {
        let app = Profile(name: "Safari", bundleIdentifiers: [safari], bindings: [
            Fixtures.binding(.twoFingerTap, .system(.launchpad)),
            Fixtures.binding(.pinchIn, .system(.showDesktop)),
        ])
        let configuration = Fixtures.configuration(
            global: [Fixtures.binding(.twoFingerTap), Fixtures.binding(.threeFingerTap, .system(.appExpose))],
            profiles: [app])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari)
        XCTAssertEqual(resolved.profileID, app.id)
        XCTAssertEqual(resolved.source, .application)
        XCTAssertEqual(resolved.binding(for: .twoFingerTap)?.action, .system(.launchpad), "app binding shadows global")
        XCTAssertEqual(resolved.binding(for: .threeFingerTap)?.action, .system(.appExpose), "inherited from global")
        XCTAssertEqual(resolved.binding(for: .pinchIn)?.action, .system(.showDesktop))
        XCTAssertEqual(resolved.bindings.count, 3)
        XCTAssertEqual(resolved.enabledKinds, [.twoFingerTap, .threeFingerTap, .pinchIn])
        XCTAssertEqual(ProfileResolver.effectiveBindings(for: app, in: configuration).count, 3)
        // Bundle identifiers match regardless of letter case.
        XCTAssertEqual(ProfileResolver.resolve(configuration: configuration, frontmostBundleID: "COM.APPLE.SAFARI").profileID, app.id)
    }

    func testProfileThatDoesNotInheritIsIsolated() {
        let app = Profile(name: "Isolated", bundleIdentifiers: [safari], bindings: [Fixtures.binding(.pinchIn)],
                          inheritsGlobal: false)
        let configuration = Fixtures.configuration(global: [Fixtures.binding(.twoFingerTap)], profiles: [app])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari)
        XCTAssertNil(resolved.binding(for: .twoFingerTap))
        XCTAssertEqual(resolved.enabledKinds, [.pinchIn])
    }

    func testDisabledBindingsDoNotShadowButNoneDoes() {
        let app = Profile(name: "Safari", bundleIdentifiers: [safari], bindings: [
            Fixtures.binding(.twoFingerTap, .system(.launchpad), enabled: false),
            Fixtures.binding(.threeFingerTap, .none),
        ])
        let configuration = Fixtures.configuration(
            global: [Fixtures.binding(.twoFingerTap), Fixtures.binding(.threeFingerTap, .system(.appExpose)),
                     Fixtures.binding(.pinchOut, .system(.spotlight), enabled: false)],
            profiles: [app])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari)
        XCTAssertEqual(resolved.binding(for: .twoFingerTap)?.action, .system(.missionControl))
        XCTAssertNil(resolved.binding(for: .threeFingerTap), "`.none` switches the inherited gesture off")
        XCTAssertNil(resolved.binding(for: .pinchOut))
        XCTAssertEqual(resolved.enabledKinds, [.twoFingerTap])
    }

    func testDuplicateTriggersPreferPriorityThenOrder() {
        let low = Fixtures.binding(.twoFingerTap, .system(.launchpad), priority: 0)
        let high = Fixtures.binding(.twoFingerTap, .system(.spotlight), priority: 5)
        let alsoHigh = Fixtures.binding(.twoFingerTap, .system(.lockScreen), priority: 5)
        let tieFirst = Fixtures.binding(.pinchIn, .system(.mute))
        let tieSecond = Fixtures.binding(.pinchIn, .system(.playPause))
        let configuration = Fixtures.configuration(global: [low, high, alsoHigh, tieFirst, tieSecond])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil)
        XCTAssertEqual(resolved.binding(for: .twoFingerTap)?.id, high.id)
        XCTAssertEqual(resolved.binding(for: .pinchIn)?.id, tieFirst.id)
        XCTAssertEqual(resolved.bindings.count, 2)
    }

    func testManualOverrideBeatsBundleMatch() {
        let safariProfile = Profile(name: "Safari", bundleIdentifiers: [safari], bindings: [Fixtures.binding(.pinchIn)])
        let manual = Profile(name: "Presentation", bindings: [Fixtures.binding(.pinchOut)])
        let configuration = Fixtures.configuration(profiles: [safariProfile, manual])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari, overrideID: manual.id)
        XCTAssertEqual(resolved.profileID, manual.id)
        XCTAssertEqual(resolved.source, .manualOverride)
        // Overriding with the global profile switches app profiles off.
        let global = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari,
                                             overrideID: configuration.globalProfileID)
        XCTAssertEqual(global.profileID, configuration.globalProfileID)
        XCTAssertEqual(global.source, .manualOverride)
        // An override naming nothing falls back to automatic switching.
        let stale = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: safari, overrideID: UUID())
        XCTAssertEqual(stale.profileID, safariProfile.id)
    }

    func testDisabledProfilesAreSkipped() {
        let disabled = Profile(name: "Old Safari", bundleIdentifiers: [safari], isEnabled: false)
        let enabled = Profile(name: "Safari", bundleIdentifiers: [safari])
        let disabledManual = Profile(name: "Manual", isEnabled: false)
        var configuration = Fixtures.configuration(profiles: [disabled, enabled, disabledManual])
        XCTAssertEqual(ProfileResolver.activeProfile(in: configuration, frontmostBundleID: safari).id, enabled.id)
        XCTAssertEqual(ProfileResolver.activeProfile(in: configuration, frontmostBundleID: safari,
                                                     overrideID: disabledManual.id).id, enabled.id)
        configuration.profiles.removeAll { $0.id == enabled.id }
        XCTAssertEqual(ProfileResolver.activeProfile(in: configuration, frontmostBundleID: safari).id,
                       configuration.globalProfileID)
    }

    func testSwitchingAcrossApps() {
        let safariProfile = Profile(name: "Safari", bundleIdentifiers: [safari], bindings: [Fixtures.binding(.pinchIn)])
        let filesProfile = Profile(name: "Files", bundleIdentifiers: [finder, "com.example.files"],
                                   bindings: [Fixtures.binding(.pinchOut)])
        let configuration = Fixtures.configuration(global: [Fixtures.binding(.twoFingerTap)],
                                                   profiles: [safariProfile, filesProfile])
        let sequence: [(String?, UUID)] = [
            (safari, safariProfile.id), (finder, filesProfile.id), ("com.example.other", configuration.globalProfileID),
            ("com.example.files", filesProfile.id), (nil, configuration.globalProfileID), (safari, safariProfile.id),
        ]
        for (bundleID, expected) in sequence {
            XCTAssertEqual(ProfileResolver.resolve(configuration: configuration, frontmostBundleID: bundleID).profileID, expected)
        }
    }

    func testScrollSettingsFallBackToGlobal() {
        var appScroll = ScrollSettings()
        appScroll.isEnabled = true
        appScroll.verticalMultiplier = 2
        let withScroll = Profile(name: "A", bundleIdentifiers: ["a"], scroll: appScroll)
        let withoutScroll = Profile(name: "B", bundleIdentifiers: ["b"])
        var configuration = Fixtures.configuration(profiles: [withScroll, withoutScroll])
        configuration.profiles[0].scroll?.invertVertical = true
        XCTAssertEqual(ProfileResolver.resolve(configuration: configuration, frontmostBundleID: "a").scroll, appScroll)
        XCTAssertTrue(ProfileResolver.resolve(configuration: configuration, frontmostBundleID: "b").scroll.invertVertical)
    }

    func testCapabilitiesFilterBindingsAndKinds() {
        let configuration = Fixtures.configuration(global: [
            Fixtures.binding(.twoFingerTap), Fixtures.binding(.threeFingerTap), Fixtures.binding(.chordLeftClick),
            GestureBinding(trigger: .sequence([.chordScrollUp, .centerTap]), action: .system(.mute)),
        ])
        let all = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil, capabilities: Fixtures.allCapabilities)
        XCTAssertEqual(all.bindings.count, 4)
        XCTAssertEqual(all.enabledKinds, [.twoFingerTap, .threeFingerTap, .chordLeftClick, .chordScrollUp, .centerTap])
        XCTAssertEqual(all.chordKinds, [.chordLeftClick, .chordScrollUp])
        XCTAssertEqual(all.sequences, [[.chordScrollUp, .centerTap]])
        XCTAssertNotNil(all.binding(for: .sequence([.chordScrollUp, .centerTap])))

        let fallback = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil, capabilities: Fixtures.fallbackOnly)
        XCTAssertEqual(fallback.enabledKinds, [.chordLeftClick])
        XCTAssertEqual(fallback.unavailableBindings.count, 3)
        XCTAssertNil(fallback.binding(for: .twoFingerTap))

        let twoFingers = InputCapabilities(rawContacts: true, maxContacts: 2, contactSize: false, pointerEvents: false)
        let limited = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil, capabilities: twoFingers)
        XCTAssertEqual(limited.enabledKinds, [.twoFingerTap])

        let nothing = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil, capabilities: InputCapabilities.none)
        XCTAssertTrue(nothing.bindings.isEmpty)
        XCTAssertTrue(nothing.enabledKinds.isEmpty)
    }

    func testTuningOverridesComeFromBindings() {
        let configuration = Fixtures.configuration(global: [
            Fixtures.binding(.oneFingerHold, sensitivity: 0.8, duration: 0.9),
            Fixtures.binding(.twoFingerTap),
            Fixtures.binding(.pinchIn, sensitivity: 0.2),
            GestureBinding(trigger: .sequence([.oneFingerHold, .threeFingerTap]), action: .system(.mute), sensitivity: 0.1),
        ])
        let resolved = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: nil)
        XCTAssertEqual(resolved.tuning[.oneFingerHold], GestureTuning(sensitivity: 0.8, duration: 0.9))
        XCTAssertEqual(resolved.tuning[.pinchIn], GestureTuning(sensitivity: 0.2))
        XCTAssertEqual(resolved.tuning[.threeFingerTap], GestureTuning(sensitivity: 0.1))
        XCTAssertNil(resolved.tuning[.twoFingerTap], "neutral bindings add no override")

        var base = RecognizerConfig()
        base.setTuning(GestureTuning(sensitivity: 0.3, duration: 0.2), for: .pinchIn)
        base.setTuning(GestureTuning(sensitivity: 0.9), for: .twoFingerTap)
        let merged = resolved.recognizerConfig(base: base)
        XCTAssertEqual(merged.tuning(for: .pinchIn), GestureTuning(sensitivity: 0.2, duration: 0.2))
        XCTAssertEqual(merged.tuning(for: .twoFingerTap), GestureTuning(sensitivity: 0.9))
        XCTAssertEqual(merged.tuning(for: .oneFingerHold), GestureTuning(sensitivity: 0.8, duration: 0.9))
    }

    func testDamagedConfigurationStillResolves() {
        var empty = Configuration()
        empty.profiles = []
        let fromNothing = ProfileResolver.resolve(configuration: empty, frontmostBundleID: safari, overrideID: UUID())
        XCTAssertEqual(fromNothing.profileID, empty.globalProfileID)
        XCTAssertTrue(fromNothing.bindings.isEmpty)
        XCTAssertEqual(fromNothing.scroll, ScrollSettings())

        // The global id points nowhere: a profile without apps stands in.
        var orphaned = Configuration()
        let standIn = Profile(name: "Everything", bindings: [Fixtures.binding(.twoFingerTap)])
        orphaned.profiles = [Profile(name: "Safari", bundleIdentifiers: [safari]), standIn]
        XCTAssertEqual(ProfileResolver.resolve(configuration: orphaned, frontmostBundleID: nil).profileID, standIn.id)
        XCTAssertEqual(ProfileResolver.resolve(configuration: orphaned, frontmostBundleID: safari)
            .binding(for: .twoFingerTap)?.action, .system(.missionControl))
    }

    func testDefaultConfigurationResolvesPerApp() {
        let configuration = DefaultConfiguration.make()
        let finderProfile = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: finder,
                                                    capabilities: Fixtures.allCapabilities)
        XCTAssertEqual(finderProfile.profileName, "Finder")
        XCTAssertEqual(finderProfile.binding(for: .threeFingerTap)?.action, .keyboard(DefaultKeys.quickLook))
        XCTAssertEqual(finderProfile.binding(for: .centerTap)?.action, .mouse(.middleClick))
        XCTAssertNil(finderProfile.binding(for: .twoFingerSwipeLeft))

        let fallback = ProfileResolver.resolve(configuration: configuration, frontmostBundleID: finder,
                                               capabilities: Fixtures.fallbackOnly)
        XCTAssertEqual(fallback.enabledKinds, [.chordRightClick, .chordScrollUp, .chordScrollDown])
    }
}
