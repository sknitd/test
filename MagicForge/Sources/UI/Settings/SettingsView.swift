import SwiftUI
import AppKit
import MFCore
import MFEngine

/// App-wide settings. Every control writes through `model.update`.
@MainActor
public struct SettingsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MFPageHeader("Settings", subtitle: "Startup, recognition, privacy and diagnostics.")
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
            Form {
                SettingsStartupSection()
                SettingsGeneralSection()
                SettingsPrivacySection()
                SettingsDiagnosticsSection()
                SettingsDataSection()
                SettingsAboutSection()
            }
            .formStyle(.grouped)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Builds a Bool binding into `Configuration.settings`.
@MainActor
struct SettingsBinding {
    let model: AppModel

    func bool(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        let model: AppModel = self.model
        return Binding<Bool>(
            get: { model.configuration.settings[keyPath: keyPath] },
            set: { newValue in
                model.update { configuration in
                    configuration.settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

@MainActor
struct SettingsGeneralSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bindings = SettingsBinding(model: model)
        Section("General") {
            Toggle("Show notifications", isOn: bindings.bool(\.notificationsEnabled))
            Toggle("Animations", isOn: bindings.bool(\.animationsEnabled))
            LabeledContent("Gesture sensitivity") {
                HStack(spacing: 8) {
                    Text("Deliberate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShellCommitSlider(
                        value: model.configuration.recognizer.globalSensitivity,
                        accessibilityLabel: "Gesture sensitivity",
                        onCommit: { newValue in
                            model.update { configuration in
                                configuration.recognizer.globalSensitivity = newValue
                            }
                        }
                    )
                    .frame(minWidth: 160, maxWidth: 260)
                    Text("Light")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ShellFormat.percent(model.configuration.recognizer.globalSensitivity))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Text("Scales every gesture's own sensitivity. Higher values recognize shorter, lighter movements; lower values need more deliberate ones.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct SettingsPrivacySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bindings = SettingsBinding(model: model)
        Section("Privacy") {
            Toggle("Keep recent gestures for the Dashboard", isOn: bindings.bool(\.keepRecentGestures))
            Text("The last recognized gestures are kept in memory only and never written to disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Allow the private multitouch adapter", isOn: privateAdapterBinding)
            Text("Touch gestures need finger positions, which are only available through Apple's private MultitouchSupport framework. It is unsupported and may break with macOS updates. When this is off, only fallback triggers (Control-Option with a click or scroll) work. Changing it restarts input.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("No analytics or telemetry are collected. Touch data never leaves this Mac.", systemImage: "hand.raised")
                .font(.callout)
        }
    }

    private var privateAdapterBinding: Binding<Bool> {
        Binding<Bool>(
            get: { model.configuration.settings.allowPrivateMultitouch },
            set: { newValue in
                model.update { configuration in
                    configuration.settings.allowPrivateMultitouch = newValue
                }
                model.restartInput()
            }
        )
    }
}

@MainActor
struct SettingsAboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: versionText)
            LabeledContent("Bundle identifier", value: Bundle.main.bundleIdentifier ?? "Not running from an app bundle")
            Text("MagicForge is not affiliated with Apple. Magic Mouse is a trademark of Apple Inc.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionText: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String? = info["CFBundleShortVersionString"] as? String
        let build: String? = info["CFBundleVersion"] as? String
        if let version, let build { return "\(version) (\(build))" }
        if let version { return version }
        return "Development build"
    }
}
