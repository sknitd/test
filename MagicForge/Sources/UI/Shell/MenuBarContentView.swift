import SwiftUI
import AppKit
import MFCore
import MFEngine

/// Content of the menu bar extra (`.menuBarExtraStyle(.menu)`).
@MainActor
public struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Text(deviceText)
        Text(profileText)
        MenuBarProfileMenu()
        Divider()
        Button(model.isPaused ? "Resume Gestures" : "Pause Gestures") {
            model.setPaused(!model.isPaused)
        }
        Button("Open Dashboard") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MagicForgeWindowID.main)
        }
        Divider()
        Button("Quit MagicForge") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var deviceText: String {
        guard let device = model.connectedDevice else { return "No Magic Mouse connected" }
        if let battery = device.batteryPercent { return "\(device.name) — \(battery)%" }
        return device.name
    }

    private var profileText: String {
        let name: String = model.activeProfile?.name ?? "None"
        let mode: String = model.profileOverrideID == nil ? "automatic" : "manual override"
        return "Profile: \(name) (\(mode))"
    }
}

/// Submenu to override the active profile or return to automatic switching.
@MainActor
struct MenuBarProfileMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Switch Profile") {
            Button {
                model.setProfileOverride(nil)
            } label: {
                itemLabel("Automatic", isSelected: model.profileOverrideID == nil)
            }
            Divider()
            ForEach(model.configuration.profiles) { profile in
                Button {
                    model.setProfileOverride(profile.id)
                } label: {
                    itemLabel(profile.name, isSelected: model.profileOverrideID == profile.id)
                }
                .disabled(!profile.isEnabled)
            }
        }
    }

    @ViewBuilder
    private func itemLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
