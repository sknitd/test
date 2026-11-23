import SwiftUI
import MFCore
import MFEngine

/// Settings for the optional AI integration. Everything is off until the user turns it on.
@MainActor
public struct AIIntegrationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    public init() {}

    public var body: some View {
        let isEnabled: Bool = model.configuration.ai.isEnabled
        MFPage("AI Integrations", subtitle: "Optional. Send selected text or the clipboard to an OpenAI-compatible service you choose.") {
            VStack(alignment: .leading, spacing: 16) {
                AIMasterCard()
                if !isEnabled {
                    Label("AI is turned off. The settings below are kept but inactive, and nothing can be sent.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                AIConnectionCard()
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
                AIKeyCard(isEnabled: isEnabled)
                AITemplatesCard()
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
            }
        }
    }
}

/// Bindings into `Configuration.ai`, written through `AppModel.update`.
@MainActor
enum AISettingsEditing {
    static func binding<Value>(_ keyPath: WritableKeyPath<AISettings, Value>, model: AppModel) -> Binding<Value> {
        Binding<Value>(
            get: { model.configuration.ai[keyPath: keyPath] },
            set: { newValue in
                model.update { configuration in
                    configuration.ai[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

/// Master switch and the privacy explanation.
@MainActor
struct AIMasterCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MFCard("AI Integration", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable AI actions", isOn: AISettingsEditing.binding(\.isEnabled, model: model))
                VStack(alignment: .leading, spacing: 6) {
                    AIPrivacyPoint(symbolName: "hand.raised", text: "Off by default. While it is off, MagicForge makes no AI requests at all.")
                    AIPrivacyPoint(symbolName: "cursorarrow.click", text: "A request is only made when you trigger an AI action yourself (a gesture, a menu item or a button here). Nothing runs in the background.")
                    AIPrivacyPoint(symbolName: "doc.text", text: "Only the text of that one request is sent: your prompt template with the selected text or clipboard inserted. It goes directly to the address you enter below, not to MagicForge servers (there are none).")
                    AIPrivacyPoint(symbolName: "key", text: "The API key is stored in your macOS Keychain, never in the configuration file or in exports.")
                    AIPrivacyPoint(symbolName: "building.2", text: "What the service does with your text is governed by that service's own terms. Do not send text you may not share.")
                }
            }
        }
    }
}

struct AIPrivacyPoint: View {
    let symbolName: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum AIConnectionTestStatus: Equatable {
    case idle
    case running
    case succeeded(String)
    case failed(String)
}

/// Endpoint, model, timeout, consent toggle and the connection test.
@MainActor
struct AIConnectionCard: View {
    @Environment(AppModel.self) private var model
    @State private var testStatus: AIConnectionTestStatus = .idle

    var body: some View {
        let settings: AISettings = model.configuration.ai
        MFCard("Service", systemImage: "network") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Base URL")
                        .frame(width: 80, alignment: .leading)
                    TextField("Base URL", text: AISettingsEditing.binding(\.baseURL, model: model),
                              prompt: Text("https://api.openai.com/v1"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(Text("Base URL"))
                }
                if let problem = AIText.baseURLProblem(settings.baseURL) {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text("Model")
                        .frame(width: 80, alignment: .leading)
                    TextField("Model", text: AISettingsEditing.binding(\.model, model: model),
                              prompt: Text("Model identifier exactly as the service names it"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(Text("Model"))
                }
                Stepper(value: AISettingsEditing.binding(\.timeout, model: model), in: 5...300, step: 5) {
                    Text("Give up after \(Int(settings.timeout)) seconds")
                }
                Toggle("Show the exact text and ask before every request", isOn: AISettingsEditing.binding(\.confirmBeforeSending, model: model))
                Divider()
                testRow
            }
        }
    }

    private var testRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: { runTest() }) {
                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(testStatus == .running)
            .help("Sends one minimal request to check the address, model and key")
            testResult
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testStatus {
        case .idle:
            Text("Sends a tiny test prompt (no personal text) to the service.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded(let reply):
            Label(Self.successText(reply), systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Color.green)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private static func successText(_ reply: String) -> String {
        if reply.isEmpty { return "Connection works." }
        return "Connection works. Reply: " + ActionText.firstLine(reply, limit: 80)
    }

    private func runTest() {
        testStatus = .running
        Task {
            let result: Result<String, AIError> = await model.testAIConnection()
            switch result {
            case .success(let reply): testStatus = .succeeded(reply)
            case .failure(let error): testStatus = .failed(AIText.describe(error))
            }
        }
    }
}

/// API key entry. The stored key is never read back into the UI.
@MainActor
struct AIKeyCard: View {
    let isEnabled: Bool
    @Environment(AppModel.self) private var model
    @State private var draft: String = ""
    @State private var errorText: String = ""
    /// Bumped after every Keychain change so `hasAPIKey` is read again.
    @State private var revision: Int = 0

    var body: some View {
        let hasKey: Bool = revision >= 0 && model.hasAPIKey
        MFCard("API Key", systemImage: "key") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    MFStatusBadge(hasKey ? "Key stored in Keychain" : "No key stored", style: hasKey ? .good : .neutral)
                    Spacer(minLength: 8)
                    Button("Remove Key", role: .destructive) { store(nil) }
                        .disabled(!hasKey)
                }
                HStack(spacing: 8) {
                    SecureField("API key", text: $draft, prompt: Text(hasKey ? "Enter a new key to replace the stored one" : "Paste your API key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(Text("API key"))
                        .onSubmit { saveDraft() }
                    Button("Save Key") { saveDraft() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.55)
                Text("The key is written to your macOS Keychain and is never shown again. Services that need no key (for example a local server) can leave this empty if they accept that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !errorText.isEmpty {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func saveDraft() {
        let trimmed: String = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store(trimmed)
    }

    private func store(_ key: String?) {
        do {
            try model.setAPIKey(key)
            draft = ""
            errorText = ""
        } catch {
            errorText = "The Keychain refused the change: \(error.localizedDescription)"
        }
        revision += 1
    }
}
