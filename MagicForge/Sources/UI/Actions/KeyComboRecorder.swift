import SwiftUI
import AppKit
import Observation
import MFCore

/// Virtual key codes the recorder treats specially.
enum KeyComboRecorderKeys {
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    /// F1…F20.
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    /// Arrows, Home, End, Page Up / Down, Forward Delete, Help: AppKit always reports the fn flag for these.
    static let navigationKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 117, 114]
}

enum KeyComboRecorderOutcome {
    case recorded(KeyCombo)
    case cleared
    case cancelled
}

/// Owns the local key-down monitor while a shortcut is being recorded.
@MainActor
@Observable
final class KeyComboRecorderSession {
    var isRecording: Bool = false
    var hint: String = ""
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var completion: ((KeyComboRecorderOutcome) -> Void)?

    nonisolated init() {}

    func begin(completion: @escaping (KeyComboRecorderOutcome) -> Void) {
        end()
        self.completion = completion
        hint = ""
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] (event: NSEvent) -> NSEvent? in
            let keyCode: UInt16 = event.keyCode
            let flags: NSEvent.ModifierFlags = event.modifierFlags
            MainActor.assumeIsolated {
                if let session = self {
                    session.handle(keyCode: keyCode, rawFlags: flags)
                }
            }
            // Swallow every key while recording so it neither types nor triggers menu shortcuts.
            return nil
        }
    }

    /// Stops recording and removes the monitor. Safe to call repeatedly.
    func end() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        completion = nil
        isRecording = false
    }

    private func finish(_ outcome: KeyComboRecorderOutcome) {
        let callback: ((KeyComboRecorderOutcome) -> Void)? = completion
        end()
        callback?(outcome)
    }

    private func handle(keyCode: UInt16, rawFlags: NSEvent.ModifierFlags) {
        let flags: NSEvent.ModifierFlags = rawFlags.intersection(.deviceIndependentFlagsMask)
        let command: Bool = flags.contains(.command)
        let option: Bool = flags.contains(.option)
        let control: Bool = flags.contains(.control)
        let shift: Bool = flags.contains(.shift)
        let isFunctionKey: Bool = KeyComboRecorderKeys.functionKeys.contains(keyCode)
        let isNavigationKey: Bool = KeyComboRecorderKeys.navigationKeys.contains(keyCode)
        let hasModifier: Bool = command || option || control || shift

        if !hasModifier {
            if keyCode == KeyComboRecorderKeys.escape {
                finish(.cancelled)
                return
            }
            if keyCode == KeyComboRecorderKeys.delete || keyCode == KeyComboRecorderKeys.forwardDelete {
                finish(.cleared)
                return
            }
            if !isFunctionKey {
                hint = "Hold at least one of ⌃ ⌥ ⇧ ⌘ (function keys work alone)."
                return
            }
        }
        let function: Bool = flags.contains(.function) && !isFunctionKey && !isNavigationKey
        var combo = KeyCombo(keyCode: keyCode, command: command, option: option, control: control,
                             shift: shift, function: function)
        combo.label = combo.displayString
        finish(.recorded(combo))
    }
}

/// Click-to-record keyboard shortcut field. Escape cancels, Delete clears.
@MainActor
public struct KeyComboRecorder: View {
    @Binding private var combo: KeyCombo?
    @State private var session = KeyComboRecorderSession()

    public init(combo: Binding<KeyCombo?>) {
        self._combo = combo
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: { toggleRecording() }) {
                Text(buttonTitle)
                    .frame(minWidth: 120)
            }
            .accessibilityLabel(Text(accessibilityTitle))
            .help("Click, then press the shortcut. Escape cancels, Delete clears.")
            if combo != nil && !session.isRecording {
                Button(action: { clear() }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear shortcut"))
                .help("Clear shortcut")
            }
            if session.isRecording && !session.hint.isEmpty {
                Text(session.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { session.end() }
    }

    private var buttonTitle: String {
        if session.isRecording { return "Type shortcut…" }
        if let combo = combo { return combo.displayString }
        return "Record Shortcut"
    }

    private var accessibilityTitle: String {
        if session.isRecording { return "Recording shortcut. Press Escape to cancel." }
        if let combo = combo { return "Shortcut \(combo.displayString). Click to record a new one." }
        return "Record shortcut"
    }

    private func toggleRecording() {
        if session.isRecording {
            session.end()
            return
        }
        let binding: Binding<KeyCombo?> = $combo
        session.begin { outcome in
            switch outcome {
            case .recorded(let recorded): binding.wrappedValue = recorded
            case .cleared: binding.wrappedValue = nil
            case .cancelled: break
            }
        }
    }

    private func clear() {
        session.end()
        combo = nil
    }
}
