import SwiftUI
import AppKit
import MFCore

/// Forwards "the user closed the window" to a closure.
@MainActor
final class AIPanelCloseObserver: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        let handler: (() -> Void)? = onClose
        onClose = nil
        handler?()
    }
}

/// Consent and result panels for the AI flow.
///
/// Both panels are non-activating, so the app the user was working in stays frontmost and
/// "Paste" can go back into it. Closing a panel with its close button or Escape counts as
/// Cancel / Dismiss. Every continuation is resumed exactly once.
@MainActor
public final class AIInteractionController: AIInteractionPresenting {
    private var confirmPanel: NSPanel?
    private var confirmObserver: AIPanelCloseObserver?
    private var confirmContinuation: CheckedContinuation<Bool, Never>?

    private var resultPanel: NSPanel?
    private var resultObserver: AIPanelCloseObserver?
    private var resultContinuation: CheckedContinuation<AIResultChoice, Never>?

    nonisolated public init() {}

    // MARK: Consent

    public func confirmSend(text: String, template: PromptTemplate, endpoint: String) async -> Bool {
        // A request that is still waiting for an answer is declined before a new one is shown.
        resolveConfirm(false, windowAlreadyClosing: false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.confirmContinuation = continuation
            let view = AIConfirmSendView(text: text, templateName: template.name, endpoint: endpoint,
                                         onDecision: { [weak self] (send: Bool) in
                                             self?.resolveConfirm(send, windowAlreadyClosing: false)
                                         })
            let observer = AIPanelCloseObserver()
            observer.onClose = { [weak self] in
                self?.resolveConfirm(false, windowAlreadyClosing: true)
            }
            self.confirmObserver = observer
            self.confirmPanel = self.makePanel(title: "Send Text to AI Service?", size: NSSize(width: 520, height: 440),
                                               content: AnyView(view), observer: observer)
        }
    }

    private func resolveConfirm(_ send: Bool, windowAlreadyClosing: Bool) {
        let pending: CheckedContinuation<Bool, Never>? = confirmContinuation
        confirmContinuation = nil
        let panel: NSPanel? = confirmPanel
        confirmPanel = nil
        confirmObserver?.onClose = nil
        confirmObserver = nil
        if let panel = panel, !windowAlreadyClosing {
            panel.delegate = nil
            panel.orderOut(nil)
        }
        pending?.resume(returning: send)
    }

    // MARK: Result

    public func presentResult(_ result: String, template: PromptTemplate) async -> AIResultChoice {
        resolveResult(.dismiss, windowAlreadyClosing: false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<AIResultChoice, Never>) in
            self.resultContinuation = continuation
            let view = AIResultView(result: result, templateName: template.name,
                                    onChoice: { [weak self] (choice: AIResultChoice) in
                                        self?.resolveResult(choice, windowAlreadyClosing: false)
                                    })
            let observer = AIPanelCloseObserver()
            observer.onClose = { [weak self] in
                self?.resolveResult(.dismiss, windowAlreadyClosing: true)
            }
            self.resultObserver = observer
            self.resultPanel = self.makePanel(title: "AI Result", size: NSSize(width: 520, height: 420),
                                              content: AnyView(view), observer: observer)
        }
    }

    private func resolveResult(_ choice: AIResultChoice, windowAlreadyClosing: Bool) {
        let pending: CheckedContinuation<AIResultChoice, Never>? = resultContinuation
        resultContinuation = nil
        let panel: NSPanel? = resultPanel
        resultPanel = nil
        resultObserver?.onClose = nil
        resultObserver = nil
        if let panel = panel, !windowAlreadyClosing {
            panel.delegate = nil
            panel.orderOut(nil)
        }
        pending?.resume(returning: choice)
    }

    // MARK: Panel

    private func makePanel(title: String, size: NSSize, content: AnyView, observer: AIPanelCloseObserver) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 380, height: 280)
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(size)
        panel.delegate = observer
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        return panel
    }
}
