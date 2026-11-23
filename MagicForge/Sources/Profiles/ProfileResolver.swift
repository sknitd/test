import Foundation
import MFCore

/// The profile in effect for one moment (frontmost app + manual override), flattened into
/// exactly what the recognizer and the dispatcher need.
public struct ResolvedProfile: Sendable, Equatable {
    public enum Source: String, Sendable {
        /// The user's manual override.
        case manualOverride
        /// Matched the frontmost app's bundle identifier.
        case application
        /// Nothing more specific applied.
        case global
    }

    public let profileID: UUID
    public let profileName: String
    public let source: Source
    /// Bindings that can fire: enabled, deliverable with the given capabilities, not bound to
    /// `.none`, at most one per trigger. The profile's own bindings come first, then inherited
    /// global bindings.
    public let bindings: [GestureBinding]
    /// Winning bindings whose gesture the current input cannot deliver (shown as unavailable).
    public let unavailableBindings: [GestureBinding]
    public let scroll: ScrollSettings
    /// Per-kind tuning taken from the bindings' `sensitivity` / `duration`. Only kinds whose
    /// binding differs from the neutral values (0.5, no duration) appear here.
    public let tuning: [GestureKind: GestureTuning]
    /// Kinds the recognizer / event tap must produce, including every kind used in a sequence.
    public let enabledKinds: Set<GestureKind>

    private let lookup: [GestureTrigger: GestureBinding]

    init(profileID: UUID, profileName: String, source: Source, bindings: [GestureBinding],
         unavailableBindings: [GestureBinding], scroll: ScrollSettings) {
        self.profileID = profileID; self.profileName = profileName; self.source = source
        self.bindings = bindings; self.unavailableBindings = unavailableBindings; self.scroll = scroll
        var lookup: [GestureTrigger: GestureBinding] = [:]
        var kinds = Set<GestureKind>()
        for binding in bindings {
            if lookup[binding.trigger] == nil { lookup[binding.trigger] = binding }
            kinds.formUnion(binding.trigger.kinds)
        }
        self.lookup = lookup
        self.enabledKinds = kinds
        self.tuning = ResolvedProfile.tuning(from: bindings)
    }

    /// O(1) lookup of the binding to run for a trigger.
    public func binding(for trigger: GestureTrigger) -> GestureBinding? { lookup[trigger] }
    public func binding(for kind: GestureKind) -> GestureBinding? { lookup[.single(kind)] }

    /// Kind lists of the sequence triggers in effect (for `SequenceMatcher`).
    public var sequences: [[GestureKind]] {
        bindings.compactMap { binding in
            if case .sequence(let kinds) = binding.trigger { return kinds }
            return nil
        }
    }

    /// Enabled fallback chords, for `PointerEventSource.setEnabledChords`.
    public var chordKinds: Set<GestureKind> { enabledKinds.filter { $0.category == .fallback } }

    /// `base` with this profile's per-binding tuning laid over `RecognizerConfig.tuning`. A
    /// binding's sensitivity replaces the base value only when it is not the neutral 0.5, its
    /// duration only when set.
    public func recognizerConfig(base: RecognizerConfig) -> RecognizerConfig {
        var config = base
        for (kind, override) in tuning {
            var value = base.tuning(for: kind)
            if override.sensitivity != 0.5 { value.sensitivity = override.sensitivity }
            if let duration = override.duration { value.duration = duration }
            config.setTuning(value, for: kind)
        }
        return config
    }

    private static func tuning(from bindings: [GestureBinding]) -> [GestureKind: GestureTuning] {
        var result: [GestureKind: GestureTuning] = [:]
        // A kind's own single-gesture binding decides; sequences only tune kinds nothing else claims.
        let singlesFirst = bindings.filter { if case .single = $0.trigger { return true } else { return false } }
            + bindings.filter { if case .sequence = $0.trigger { return true } else { return false } }
        for binding in singlesFirst where binding.sensitivity != 0.5 || binding.duration != nil {
            for kind in binding.trigger.kinds where result[kind] == nil {
                result[kind] = GestureTuning(sensitivity: binding.sensitivity, duration: binding.duration)
            }
        }
        return result
    }
}

/// Decides which profile applies and flattens it together with the global profile.
///
/// Order: an enabled profile named by the manual override, else the first enabled profile that
/// lists the frontmost bundle identifier, else the global profile. Disabled profiles never
/// apply. The global profile always applies, even when the configuration is damaged.
public enum ProfileResolver {
    public static func resolve(configuration: Configuration, frontmostBundleID: String?, overrideID: UUID? = nil,
                               capabilities: InputCapabilities? = nil) -> ResolvedProfile {
        let global = globalProfile(in: configuration)
        let (profile, source) = select(configuration: configuration, global: global,
                                       frontmostBundleID: frontmostBundleID, overrideID: overrideID)
        let effective = effectiveBindings(for: profile, global: global).filter { $0.action != .none }
        var available: [GestureBinding] = []
        var unavailable: [GestureBinding] = []
        for binding in effective {
            if let capabilities, !binding.trigger.kinds.allSatisfy({ $0.isAvailable(with: capabilities) }) {
                unavailable.append(binding)
            } else {
                available.append(binding)
            }
        }
        return ResolvedProfile(profileID: profile.id, profileName: profile.name, source: source, bindings: available,
                               unavailableBindings: unavailable,
                               scroll: profile.scroll ?? global.scroll ?? ScrollSettings())
    }

    /// The profile that applies (see the type's description for the order).
    public static func activeProfile(in configuration: Configuration, frontmostBundleID: String?,
                                     overrideID: UUID? = nil) -> Profile {
        select(configuration: configuration, global: globalProfile(in: configuration),
               frontmostBundleID: frontmostBundleID, overrideID: overrideID).0
    }

    /// The global profile, or a usable stand-in when the configuration has lost it.
    public static func globalProfile(in configuration: Configuration) -> Profile {
        if let global = configuration.globalProfile { return global }
        if let manual = configuration.profiles.first(where: { $0.bundleIdentifiers.isEmpty && $0.isEnabled }) {
            return manual
        }
        return Profile(id: configuration.globalProfileID, name: "Global", symbolName: "globe")
    }

    /// Enabled bindings of `profile` after inheritance, one per trigger, own bindings first.
    ///
    /// Among bindings with the same trigger in one profile the highest `priority` wins (ties:
    /// the first). When the profile inherits, global bindings are added for triggers the profile
    /// does not bind itself. Only enabled bindings shadow; bind a trigger to `.none` to switch an
    /// inherited gesture off for one app.
    public static func effectiveBindings(for profile: Profile, in configuration: Configuration) -> [GestureBinding] {
        effectiveBindings(for: profile, global: globalProfile(in: configuration))
    }

    static func effectiveBindings(for profile: Profile, global: Profile) -> [GestureBinding] {
        var result = winners(in: profile.bindings)
        guard profile.id != global.id, profile.inheritsGlobal else { return result }
        let shadowed = Set(result.map(\.trigger))
        result += winners(in: global.bindings).filter { !shadowed.contains($0.trigger) }
        return result
    }

    /// One enabled binding per trigger, in original order.
    static func winners(in bindings: [GestureBinding]) -> [GestureBinding] {
        var best: [GestureTrigger: GestureBinding] = [:]
        var order: [GestureTrigger] = []
        for binding in bindings where binding.isEnabled {
            if let current = best[binding.trigger] {
                if binding.priority > current.priority { best[binding.trigger] = binding }
            } else {
                best[binding.trigger] = binding
                order.append(binding.trigger)
            }
        }
        return order.compactMap { best[$0] }
    }

    private static func select(configuration: Configuration, global: Profile, frontmostBundleID: String?,
                               overrideID: UUID?) -> (Profile, ResolvedProfile.Source) {
        if let overrideID {
            if overrideID == global.id { return (global, .manualOverride) }
            if let chosen = configuration.profiles.first(where: { $0.id == overrideID && $0.isEnabled }) {
                return (chosen, .manualOverride)
            }
        }
        if let bundleID = frontmostBundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bundleID.isEmpty,
           let match = configuration.profiles.first(where: { profile in
               profile.isEnabled && profile.id != global.id
                   && profile.bundleIdentifiers.contains { $0.lowercased() == bundleID }
           }) {
            return (match, .application)
        }
        return (global, .global)
    }
}
