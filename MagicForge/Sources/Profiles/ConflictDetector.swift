import Foundation
import MFCore

/// Finds bindings that collide with each other, with macOS, or with what the hardware can deliver.
///
/// Only enabled bindings are considered. A profile is checked in context: when it inherits, the
/// global bindings it does not shadow take part in timing checks (`delaysOther`,
/// `sequencePrefix`), because they are active at the same time. Shadowing a global binding is
/// intended behaviour and is not reported.
public enum ConflictDetector {
    /// Conflicts for `profile` as it would behave inside `configuration`.
    public static func conflicts(in profile: Profile, configuration: Configuration,
                                 capabilities: InputCapabilities? = nil) -> [BindingConflict] {
        conflicts(in: profile, global: configuration.globalProfile, capabilities: capabilities)
    }

    /// Conflicts for `profile`. Pass the global profile so inherited bindings are taken into
    /// account (it is ignored when `profile` is the global profile or does not inherit).
    public static func conflicts(in profile: Profile, global: Profile?,
                                 capabilities: InputCapabilities? = nil) -> [BindingConflict] {
        let own = profile.bindings.filter(\.isEnabled)
        var inherited: [GestureBinding] = []
        if let global, global.id != profile.id, profile.inheritsGlobal {
            let shadowed = Set(own.map(\.trigger))
            inherited = ProfileResolver.winners(in: global.bindings).filter { !shadowed.contains($0.trigger) }
        }
        var result = duplicateTriggers(own)
        result += delays(own: own, inherited: inherited)
        result += sequencePrefixes(own: own, inherited: inherited)
        result += systemOverlaps(own)
        if let capabilities { result += unavailable(own, capabilities: capabilities) }
        return result
    }

    /// Conflicts that involve `candidate` if it were added to `profile` (or replaced the binding
    /// with the same id).
    public static func conflicts(adding candidate: GestureBinding, to profile: Profile, global: Profile?,
                                 capabilities: InputCapabilities? = nil) -> [BindingConflict] {
        var edited = profile
        if let index = edited.bindings.firstIndex(where: { $0.id == candidate.id }) {
            edited.bindings[index] = candidate
        } else {
            edited.bindings.append(candidate)
        }
        return conflicts(in: edited, global: global, capabilities: capabilities)
            .filter { $0.bindingIDs.contains(candidate.id) }
    }

    public static func conflicts(adding candidate: GestureBinding, to profile: Profile, configuration: Configuration,
                                 capabilities: InputCapabilities? = nil) -> [BindingConflict] {
        conflicts(adding: candidate, to: profile, global: configuration.globalProfile, capabilities: capabilities)
    }

    // MARK: Checks

    private static func duplicateTriggers(_ own: [GestureBinding]) -> [BindingConflict] {
        var groups: [GestureTrigger: [GestureBinding]] = [:]
        var order: [GestureTrigger] = []
        for binding in own {
            if groups[binding.trigger] == nil { order.append(binding.trigger) }
            groups[binding.trigger, default: []].append(binding)
        }
        return order.compactMap { trigger in
            guard let group = groups[trigger], group.count > 1 else { return nil }
            let name = GestureNaming.name(trigger)
            let tied = Set(group.map(\.priority)).count == 1
            let rule = tied ? "They have the same priority, so only the first one in the list runs."
                            : "Only the one with the highest priority runs."
            return make(.duplicateTrigger, .error, group.map(\.id),
                        "\(group.count) enabled bindings use “\(name)”. \(rule)")
        }
    }

    private static func delays(own: [GestureBinding], inherited: [GestureBinding]) -> [BindingConflict] {
        let all = own + inherited
        let ownIDs = Set(own.map(\.id))
        var result: [BindingConflict] = []
        for delayed in all {
            for kind in Set(delayed.trigger.kinds).sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let rule = DelayRule.rule(for: kind) else { continue }
                let causes = all.filter { other in
                    other.id != delayed.id && !Set(other.trigger.kinds).isDisjoint(with: rule.delayers)
                }
                // Report only pairs the profile being checked takes part in.
                guard !causes.isEmpty, ownIDs.contains(delayed.id) || causes.contains(where: { ownIDs.contains($0.id) })
                else { continue }
                let causeKinds = Set(causes.flatMap { $0.trigger.kinds }).intersection(rule.delayers)
                let causeNames = causeKinds.map(GestureNaming.name).sorted().joined(separator: ", ")
                result.append(make(.delaysOther, .info, [delayed.id] + causes.map(\.id),
                                   "“\(GestureNaming.name(kind))” \(rule.explanation) (\(causeNames))."))
            }
        }
        return result
    }

    private static func sequencePrefixes(own: [GestureBinding], inherited: [GestureBinding]) -> [BindingConflict] {
        let all = own + inherited
        let ownIDs = Set(own.map(\.id))
        var result: [BindingConflict] = []
        for longer in all {
            guard case .sequence(let sequence) = longer.trigger, sequence.count >= 2 else { continue }
            for shorter in all where shorter.id != longer.id && (ownIDs.contains(shorter.id) || ownIDs.contains(longer.id)) {
                let prefix = shorter.trigger.kinds
                guard prefix.count < sequence.count, Array(sequence.prefix(prefix.count)) == prefix else { continue }
                let shortName = GestureNaming.name(shorter.trigger), longName = GestureNaming.name(longer.trigger)
                if case .single = shorter.trigger {
                    result.append(make(.sequencePrefix, .info, [shorter.id, longer.id],
                                       "“\(shortName)” also starts the sequence “\(longName)”. Its own action runs "
                                       + "every time, including when you go on to finish the sequence."))
                } else {
                    result.append(make(.sequencePrefix, .warning, [shorter.id, longer.id],
                                       "The sequence “\(shortName)” is the beginning of “\(longName)”. The shorter "
                                       + "sequence runs first, every time you perform the longer one."))
                }
            }
        }
        return result
    }

    private static func systemOverlaps(_ own: [GestureBinding]) -> [BindingConflict] {
        var result: [BindingConflict] = []
        for binding in own {
            for kind in Set(binding.trigger.kinds).sorted(by: { $0.rawValue < $1.rawValue }) {
                if let message = SystemOverlap.message(for: kind) {
                    result.append(make(.overlapsSystemGesture, .warning, [binding.id], message))
                }
                if kind == .oneFingerTap, case .mouse(let mouse) = binding.action, SystemOverlap.isClick(mouse) {
                    result.append(make(.overlapsSystemGesture, .info, [binding.id],
                                       "A light tap anywhere on the surface will click, in addition to pressing the "
                                       + "mouse. Brushing the surface while moving the mouse can click by accident."))
                }
            }
        }
        return result
    }

    private static func unavailable(_ own: [GestureBinding], capabilities: InputCapabilities) -> [BindingConflict] {
        var result: [BindingConflict] = []
        for binding in own {
            let missing = Set(binding.trigger.kinds.filter { !$0.isAvailable(with: capabilities) })
            for kind in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
                result.append(make(.unavailableGesture, .error, [binding.id],
                                   unavailableMessage(for: kind, capabilities: capabilities)))
            }
        }
        return result
    }

    /// Why `kind` cannot be delivered, or nil when it can.
    public static func unavailabilityReason(for kind: GestureKind, capabilities: InputCapabilities) -> String? {
        kind.isAvailable(with: capabilities) ? nil : unavailableMessage(for: kind, capabilities: capabilities)
    }

    private static func unavailableMessage(for kind: GestureKind, capabilities: InputCapabilities) -> String {
        let name = GestureNaming.name(kind)
        switch kind.requirement {
        case .pointerEvents:
            return "“\(name)” needs MagicForge to observe mouse events, which is not possible right now "
                + "(Accessibility permission is usually the missing piece)."
        case .rawContacts:
            if !capabilities.rawContacts {
                return "“\(name)” needs raw finger positions, which the current input source cannot provide. "
                    + "Only the Control-Option fallback triggers work without them."
            }
            return "“\(name)” needs \(kind.fingerCount) fingers, but the current input source reports at most "
                + "\(capabilities.maxContacts)."
        }
    }

    /// Identifiers are derived from the content so they stay stable while the user edits
    /// (SwiftUI lists keep their rows).
    private static func make(_ kind: BindingConflict.Kind, _ severity: BindingConflict.Severity, _ ids: [UUID],
                             _ message: String) -> BindingConflict {
        let key = "conflict|\(kind.rawValue)|" + ids.map(\.uuidString).joined(separator: ",") + "|" + message
        return BindingConflict(id: Digest.stableUUID(key), kind: kind, severity: severity, bindingIDs: ids, message: message)
    }
}

/// Which gestures force the recognizer to wait before it can emit another one.
private struct DelayRule {
    let delayers: Set<GestureKind>
    let explanation: String

    private static let tapThenSwipes: Set<GestureKind> = [.tapThenSwipeLeft, .tapThenSwipeRight, .tapThenSwipeUp, .tapThenSwipeDown]
    private static let holdThenSwipes: Set<GestureKind> = [.holdThenSwipeLeft, .holdThenSwipeRight, .holdThenSwipeUp, .holdThenSwipeDown]

    static func rule(for kind: GestureKind) -> DelayRule? {
        switch kind {
        case .oneFingerTap, .centerTap, .cornerTapTopLeft, .cornerTapTopRight, .cornerTapBottomLeft, .cornerTapBottomRight:
            return DelayRule(delayers: tapThenSwipes.union([.oneFingerDoubleTap]),
                             explanation: "responds a little later, because MagicForge has to wait and see whether the "
                                + "tap becomes one of the other one-finger gestures you use")
        case .twoFingerTap:
            return DelayRule(delayers: [.twoFingerDoubleTap],
                             explanation: "responds a little later, because MagicForge has to wait and see whether a "
                                + "second tap follows")
        case .oneFingerHold:
            return DelayRule(delayers: holdThenSwipes,
                             explanation: "cannot respond until it is clear that no swipe follows the hold")
        default:
            return nil
        }
    }
}

private enum SystemOverlap {
    static func isClick(_ action: MouseAction) -> Bool {
        switch action {
        case .leftClick, .rightClick, .middleClick, .doubleClick: return true
        case .toggleDrag, .scroll: return false
        }
    }

    static func message(for kind: GestureKind) -> String? {
        switch kind {
        case .oneFingerSwipeUp, .oneFingerSwipeDown:
            return "“\(GestureNaming.name(kind))” is how the Magic Mouse scrolls. The action will also run whenever "
                + "you scroll in that direction."
        case .oneFingerSwipeLeft, .oneFingerSwipeRight:
            return "“\(GestureNaming.name(kind))” is how the Magic Mouse scrolls sideways and, in many apps, swipes "
                + "between pages. The action will also run whenever you do either."
        case .twoFingerSwipeLeft, .twoFingerSwipeRight:
            return "macOS uses a two-finger swipe left or right for “Swipe between full-screen applications”. Both "
                + "will happen unless you turn that off in System Settings › Mouse › More Gestures."
        case .oneFingerDoubleTap:
            return "macOS uses a one-finger double-tap for “Smart zoom”. Both will happen unless you turn that off "
                + "in System Settings › Mouse."
        case .twoFingerDoubleTap:
            return "macOS uses a two-finger double-tap for “Mission Control”. Both will happen unless you turn that "
                + "off in System Settings › Mouse › More Gestures."
        default:
            return nil
        }
    }
}
