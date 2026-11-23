import SwiftUI
import AppKit
import MFCore
import MFEngine
import MFUtilities

/// Diagnostics export. Touch frames are only included when the user ticks the box.
@MainActor
struct SettingsDiagnosticsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mfConfigurationLocation) private var configurationLocation

    @State private var includeTouchFrames: Bool = false
    @State private var errorMessage: String?

    private let log = Log("ui.settings")

    var body: some View {
        Section("Diagnostics") {
            Toggle("Include touch frames in the report", isOn: $includeTouchFrames)
                .toggleStyle(.checkbox)
            Text("The report contains versions, adapter and capability details, measured metrics, permission status and recent gesture names. Finger coordinates are added only when the box above is ticked. Nothing is sent anywhere; you choose where the file is saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Export Diagnostics Report…") { exportDiagnostics() }
                .shellErrorAlert("Diagnostics", message: $errorMessage)
            if let configurationLocation {
                Button("Reveal Configuration in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([configurationLocation])
                }
            }
        }
    }

    private func exportDiagnostics() {
        let data: Data = model.diagnosticsReport(includeTouchFrames: includeTouchFrames)
        guard !data.isEmpty else {
            errorMessage = "The diagnostics report is empty, so nothing was saved."
            return
        }
        do {
            _ = try ShellFilePanels.saveJSON(data, suggestedName: "MagicForge Diagnostics.json", title: "Export Diagnostics Report")
        } catch {
            log.error("Diagnostics export failed: \(error.localizedDescription)")
            errorMessage = ShellErrorText.describe(error)
        }
    }
}

/// Configuration export and reset.
@MainActor
struct SettingsDataSection: View {
    @Environment(AppModel.self) private var model

    @State private var isConfirmingReset: Bool = false
    @State private var errorMessage: String?

    private let log = Log("ui.settings")

    var body: some View {
        Section("Configuration") {
            if let persistenceError = model.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.octagon")
                    .font(.callout)
                    .foregroundStyle(Color.red)
            }
            Button("Export Configuration…") { exportConfiguration() }
                .shellErrorAlert("Configuration", message: $errorMessage)
            Text("Exports every profile, workflow, radial menu and setting as JSON. The AI API key stays in the Keychain and is never exported.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reset to Defaults…", role: .destructive) {
                isConfirmingReset = true
            }
            .confirmationDialog("Reset MagicForge to its defaults?", isPresented: $isConfirmingReset,
                                titleVisibility: .visible, actions: {
                Button("Reset Everything", role: .destructive) {
                    model.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            }, message: {
                Text("All profiles, gesture bindings, workflows, radial menus, calibrations and settings are replaced by the defaults. Export your configuration first if you want to keep it.")
            })
        }
    }

    private func exportConfiguration() {
        do {
            let data: Data = try model.exportBackup()
            _ = try ShellFilePanels.saveJSON(data, suggestedName: "MagicForge Configuration.json", title: "Export Configuration")
        } catch {
            log.error("Configuration export failed: \(error.localizedDescription)")
            errorMessage = ShellErrorText.describe(error)
        }
    }
}
