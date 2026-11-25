import AppIntents
import AppKit

// Actions for the Shortcuts app, Spotlight and Siri. Each one is a thin wrapper over the same
// `DeepLinkCommand` the URL scheme uses, so there is one implementation and one set of rules.

struct SetWidgetsVisibleIntent: AppIntent {
    static var title: LocalizedStringResource = "Show or Hide Widgets"
    static var description = IntentDescription("Shows or hides all WidgetForge desktop widgets.")

    @Parameter(title: "Show Widgets", default: true)
    var visible: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AppModel.shared.perform(visible ? .showWidgets : .hideWidgets)))
    }
}

struct SwitchProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Widget Profile"
    static var description = IntentDescription("Activates a WidgetForge profile by name. Leave the name empty to show all widgets.")

    @Parameter(title: "Profile Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = name?.trimmingCharacters(in: .whitespaces)
        return .result(dialog: IntentDialog(stringLiteral: AppModel.shared.perform(.profile(key?.isEmpty == false ? key : nil))))
    }
}

struct ApplyThemeIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Widget Theme"
    static var description = IntentDescription("Applies a theme (Glass, Midnight, Paper, Neon, Graphite or Minimal) to every widget.")

    @Parameter(title: "Theme Name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AppModel.shared.perform(.theme(name))))
    }
}

struct TidyWidgetsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tidy Up Widgets"
    static var description = IntentDescription("Packs widgets into neat columns on the left edge of each display.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AppModel.shared.perform(.tidy(.left))))
    }
}

struct RunAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Run WidgetForge Automation"
    static var description = IntentDescription("Runs one of your WidgetForge automations by name.")

    @Parameter(title: "Automation Name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The person building the shortcut chose this automation, so no further confirmation is asked.
        .result(dialog: IntentDialog(stringLiteral: AppModel.shared.perform(.runAutomation(name), confirmed: true)))
    }
}

struct WidgetForgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetWidgetsVisibleIntent(), phrases: ["Show \(.applicationName) widgets", "Toggle \(.applicationName) widgets"],
                    shortTitle: "Show or Hide Widgets", systemImageName: "eye")
        AppShortcut(intent: TidyWidgetsIntent(), phrases: ["Tidy up \(.applicationName)"], shortTitle: "Tidy Up Widgets", systemImageName: "rectangle.3.group")
    }
}
