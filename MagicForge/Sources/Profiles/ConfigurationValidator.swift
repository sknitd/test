import Foundation
import MFCore

/// Enforces the invariants the rest of the app relies on.
///
/// `repair` never throws and never discards user content it can keep: out-of-range numbers are
/// clamped, duplicate identifiers are regenerated, and references to things that no longer exist
/// are reported but left in place (the action simply fails with "not found" when triggered).
public enum ConfigurationValidator {
    public static let maxSequenceLength = 4
    public static let maxRadialDepth = 3
    public static let maxRadialItemsPerRing = 12

    /// Repairs `configuration` in place and returns one human-readable line per repair or
    /// warning. An empty result means the configuration was already valid.
    @discardableResult
    public static func repair(_ configuration: inout Configuration) -> [String] {
        var report = RepairReport()
        if configuration.schemaVersion < 1 {
            configuration.schemaVersion = Configuration.currentSchemaVersion
            report.add("The schema version was invalid and has been reset.")
        }
        ensureGlobalProfile(&configuration, &report)
        repairProfiles(&configuration, &report)
        repairWorkflows(&configuration, &report)
        repairRadialMenus(&configuration, &report)
        repairAI(&configuration, &report)
        NumericLimits.repair(&configuration.recognizer, &report)
        NumericLimits.repair(&configuration.calibrations, &report)
        repairApprovals(&configuration, &report)
        reportDanglingReferences(configuration, &report)
        return report.messages
    }

    /// The messages `repair` would produce, without changing anything.
    public static func issues(in configuration: Configuration) -> [String] {
        var copy = configuration
        return repair(&copy)
    }

    // MARK: Profiles

    private static func ensureGlobalProfile(_ configuration: inout Configuration, _ report: inout RepairReport) {
        if configuration.globalProfile != nil { return }
        if let adopted = configuration.profiles.first(where: {
            $0.bundleIdentifiers.isEmpty && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "global"
        }) {
            configuration.globalProfileID = adopted.id
            report.add("The global profile reference was broken; the profile named “Global” is used again.")
            return
        }
        let global = DefaultConfiguration.makeGlobalProfile(id: configuration.globalProfileID, radialMenuID: nil)
        configuration.profiles.insert(global, at: 0)
        report.add("The global profile was missing and has been recreated with default gestures.")
    }

    private static func repairProfiles(_ configuration: inout Configuration, _ report: inout RepairReport) {
        var seenProfiles = Set<UUID>()
        var seenBindings = Set<UUID>()
        var claimedApps: [String: String] = [:]
        for index in configuration.profiles.indices {
            var profile = configuration.profiles[index]
            if !seenProfiles.insert(profile.id).inserted {
                profile.id = UUID()
                seenProfiles.insert(profile.id)
                report.add("Two profiles shared an identifier; “\(profile.name)” received a new one.")
            }
            let isGlobal = profile.id == configuration.globalProfileID
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profile.name = isGlobal ? "Global" : "Untitled Profile"
                report.add("A profile without a name was named “\(profile.name)”.")
            }
            repairBundleIdentifiers(&profile, isGlobal: isGlobal, &report)
            if isGlobal {
                if !profile.isEnabled {
                    profile.isEnabled = true
                    report.add("The global profile cannot be disabled; it was enabled again. Pause gestures instead.")
                }
                if profile.scroll == nil { profile.scroll = ScrollSettings() }
            } else {
                for bundleID in profile.bundleIdentifiers where profile.isEnabled {
                    if let other = claimedApps[bundleID.lowercased()] {
                        report.add("“\(other)” and “\(profile.name)” both apply to \(bundleID); “\(other)” is used.")
                    } else {
                        claimedApps[bundleID.lowercased()] = profile.name
                    }
                }
            }
            repairBindings(&profile, seen: &seenBindings, &report)
            if var scroll = profile.scroll {
                NumericLimits.repair(&scroll, owner: "Profile “\(profile.name)”", &report)
                profile.scroll = scroll
            }
            if profile != configuration.profiles[index] { configuration.profiles[index] = profile }
        }
    }

    private static func repairBundleIdentifiers(_ profile: inout Profile, isGlobal: Bool, _ report: inout RepairReport) {
        if isGlobal {
            if !profile.bundleIdentifiers.isEmpty {
                profile.bundleIdentifiers = []
                report.add("The global profile applies everywhere; its app list was cleared.")
            }
            return
        }
        var seen = Set<String>()
        let cleaned = profile.bundleIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        if cleaned != profile.bundleIdentifiers {
            profile.bundleIdentifiers = cleaned
            report.add("Profile “\(profile.name)”: the app list was tidied (blank or repeated entries removed).")
        }
    }

    private static func repairBindings(_ profile: inout Profile, seen: inout Set<UUID>, _ report: inout RepairReport) {
        let owner = "Profile “\(profile.name)”"
        var kept: [GestureBinding] = []
        kept.reserveCapacity(profile.bindings.count)
        for original in profile.bindings {
            var binding = original
            if case .sequence(let kinds) = binding.trigger {
                if kinds.isEmpty {
                    report.add("\(owner): a binding with an empty gesture sequence was removed.")
                    continue
                } else if kinds.count == 1 {
                    binding.trigger = .single(kinds[0])
                    report.add("\(owner): a one-gesture sequence was turned into a plain gesture.")
                } else if kinds.count > maxSequenceLength {
                    binding.trigger = .sequence(Array(kinds.prefix(maxSequenceLength)))
                    report.add("\(owner): a gesture sequence was shortened to \(maxSequenceLength) gestures.")
                }
            }
            if !seen.insert(binding.id).inserted {
                binding.id = UUID()
                seen.insert(binding.id)
                report.add("\(owner): two bindings shared an identifier; one received a new one.")
            }
            NumericLimits.repair(&binding, owner: owner, &report)
            kept.append(binding)
        }
        if kept != profile.bindings { profile.bindings = kept }
    }

    // MARK: Workflows, menus, AI

    private static func repairWorkflows(_ configuration: inout Configuration, _ report: inout RepairReport) {
        var seen = Set<UUID>()
        for index in configuration.workflows.indices {
            var workflow = configuration.workflows[index]
            if !seen.insert(workflow.id).inserted {
                workflow.id = UUID()
                seen.insert(workflow.id)
                report.add("Two workflows shared an identifier; “\(workflow.name)” received a new one.")
            }
            if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workflow.name = "Untitled Workflow"
                report.add("A workflow without a name was named “Untitled Workflow”.")
            }
            NumericLimits.repair(&workflow, &report)
            if workflow != configuration.workflows[index] { configuration.workflows[index] = workflow }
        }
    }

    private static func repairRadialMenus(_ configuration: inout Configuration, _ report: inout RepairReport) {
        var seenMenus = Set<UUID>()
        var seenItems = Set<UUID>()
        for index in configuration.radialMenus.indices {
            var menu = configuration.radialMenus[index]
            if !seenMenus.insert(menu.id).inserted {
                menu.id = UUID()
                seenMenus.insert(menu.id)
                report.add("Two radial menus shared an identifier; “\(menu.name)” received a new one.")
            }
            if menu.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                menu.name = "Untitled Menu"
                report.add("A radial menu without a name was named “Untitled Menu”.")
            }
            menu.items = repairItems(menu.items, depth: 1, menuName: menu.name, seen: &seenItems, &report)
            NumericLimits.repair(&menu.theme, owner: "Radial menu “\(menu.name)”", &report)
            if menu != configuration.radialMenus[index] { configuration.radialMenus[index] = menu }
        }
    }

    private static func repairItems(_ items: [RadialMenuItem], depth: Int, menuName: String, seen: inout Set<UUID>,
                                    _ report: inout RepairReport) -> [RadialMenuItem] {
        var ring = items
        if ring.count > maxRadialItemsPerRing {
            ring = Array(ring.prefix(maxRadialItemsPerRing))
            report.add("Radial menu “\(menuName)”: a ring had more than \(maxRadialItemsPerRing) items; the extra ones were removed.")
        }
        for index in ring.indices {
            if !seen.insert(ring[index].id).inserted {
                ring[index].id = UUID()
                seen.insert(ring[index].id)
                report.add("Radial menu “\(menuName)”: two items shared an identifier; one received a new one.")
            }
            guard !ring[index].children.isEmpty else { continue }
            if depth >= maxRadialDepth {
                ring[index].children = []
                report.add("Radial menu “\(menuName)”: submenus deeper than \(maxRadialDepth) levels were removed.")
            } else {
                ring[index].children = repairItems(ring[index].children, depth: depth + 1, menuName: menuName,
                                                   seen: &seen, &report)
            }
        }
        return ring
    }

    private static func repairAI(_ configuration: inout Configuration, _ report: inout RepairReport) {
        var seen = Set<UUID>()
        for index in configuration.ai.templates.indices {
            if !seen.insert(configuration.ai.templates[index].id).inserted {
                configuration.ai.templates[index].id = UUID()
                seen.insert(configuration.ai.templates[index].id)
                report.add("Two AI prompts shared an identifier; one received a new one.")
            }
            if configuration.ai.templates[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.ai.templates[index].name = "Untitled Prompt"
                report.add("An AI prompt without a name was named “Untitled Prompt”.")
            }
        }
        NumericLimits.repair(&configuration.ai, &report)
    }

    private static func repairApprovals(_ configuration: inout Configuration, _ report: inout RepairReport) {
        let hexDigits = Set("0123456789abcdef".unicodeScalars)
        let valid = configuration.approvedScriptHashes.filter { hash in
            hash.unicodeScalars.count == 64 && hash.unicodeScalars.allSatisfy(hexDigits.contains)
        }
        if valid.count != configuration.approvedScriptHashes.count {
            configuration.approvedScriptHashes = valid
            report.add("Script approvals that were not valid SHA-256 digests were removed.")
        }
    }

    // MARK: References

    private static func reportDanglingReferences(_ configuration: Configuration, _ report: inout RepairReport) {
        let workflows = Set(configuration.workflows.map(\.id))
        let menus = Set(configuration.radialMenus.map(\.id))
        let templates = Set(configuration.ai.templates.map(\.id))

        func missing(_ action: Action) -> String? {
            switch action {
            case .workflow(let id): return workflows.contains(id) ? nil : "a workflow"
            case .radialMenu(let id): return menus.contains(id) ? nil : "a radial menu"
            case .ai(let id): return templates.contains(id) ? nil : "an AI prompt"
            case .none, .system, .window, .app, .keyboard, .mouse, .text, .script, .control: return nil
            }
        }

        for profile in configuration.profiles {
            for binding in profile.bindings {
                if let what = missing(binding.action) {
                    report.add("Profile “\(profile.name)”: “\(GestureNaming.name(binding.trigger))” refers to \(what) that no longer exists.")
                }
            }
        }
        for workflow in configuration.workflows {
            for action in ActionTraversal.actions(in: workflow.steps) {
                if let what = missing(action) {
                    report.add("Workflow “\(workflow.name)” refers to \(what) that no longer exists.")
                }
            }
        }
        for menu in configuration.radialMenus {
            for item in ActionTraversal.allItems(in: menu.items) {
                if let what = missing(item.action) {
                    report.add("Radial menu “\(menu.name)”: “\(item.title)” refers to \(what) that no longer exists.")
                }
            }
        }
    }
}

/// Collects repair messages, dropping exact repeats.
struct RepairReport {
    private(set) var messages: [String] = []
    private var seen = Set<String>()

    mutating func add(_ message: String) {
        if seen.insert(message).inserted { messages.append(message) }
    }
}
