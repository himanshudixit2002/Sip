import AppKit
import SwiftUI
import SipCore

/// A Spotlight-style box: press the shortcut, type "330 tea" or "2 glasses",
/// press Return. It takes the keyboard without activating Sip, and gets out of
/// the way as soon as it loses focus.
@MainActor
final class QuickLogController: NSObject, NSWindowDelegate {
    private let panel: KeyPanel
    private let model = QuickLogModel()
    private unowned let state: AppState

    init(state: AppState) {
        self.state = state
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.configureTransparent(level: .modalPanel, shadow: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let view = QuickLogView(model: model, state: state,
                                submit: { [weak self] in self?.submit() },
                                cancel: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
    }

    var isShown: Bool { panel.isVisible }

    func toggle() { isShown ? close() : show() }

    func show() {
        model.text = ""
        model.focusToken += 1
        panel.positionTopCenter()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    /// For checking the look from a shell: shows the box without taking the keyboard.
    func preview(text: String) {
        model.text = text
        panel.positionTopCenter()
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.close() }
    }

    private func submit() {
        let text = model.text
        guard QuickLogParser.parse(text, cups: state.settings.quickLogCups, unit: state.settings.unit) != nil else {
            NSSound.beep()
            return
        }
        close()
        state.logParsed(text, source: .quickLog)
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

/// A borderless panel that can still take the keyboard.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class QuickLogModel: ObservableObject {
    @Published var text = ""
    @Published var focusToken = 0
}

private struct QuickLogView: View {
    @ObservedObject var model: QuickLogModel
    let state: AppState
    var submit: () -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let settings = state.settings
        let parsed = QuickLogParser.parse(model.text, cups: settings.quickLogCups, unit: settings.unit)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(settings.theme.gradient)
                TextField("330 tea, 2 glasses, 1.5 L…", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand(perform: cancel)
            }
            HStack(spacing: 6) {
                if model.text.isEmpty {
                    Text("Type an amount, a drink or a cup name. Return logs it; Esc closes.")
                } else if let parsed {
                    Image(systemName: (parsed.drink ?? settings.defaultCup.drink).symbol)
                    Text("Log \(Volume.format(parsed.ml, settings.unit)) of \((parsed.drink ?? settings.defaultCup.drink).title.lowercased())")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("↩").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "questionmark.circle")
                    Text("Not sure what that is — try “250”, “330 tea” or “bottle”.")
                }
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(height: 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 460, height: 120)
        .background(VisualEffectBlur(material: .popover).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .onChange(of: model.focusToken) { _, _ in focused = true }
        .onAppear { focused = true }
    }
}
