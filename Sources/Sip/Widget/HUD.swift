import AppKit
import SwiftUI
import SipCore

/// A small glass card that drops in at the top of the screen when you log a
/// drink without the widget in sight: from a hotkey, Siri, the command line
/// or your phone. Like the volume HUD, it ignores the mouse, never takes
/// focus, and is gone (views and all) a couple of seconds later.
@MainActor
final class HUDController {
    private unowned let state: AppState
    private var panel: NSPanel?
    private var hideLater = Debouncer()
    private let model = HUDModel()

    init(state: AppState) { self.state = state }

    func show(ml: Double, drink: DrinkKind) {
        guard state.settings.hudEnabled, !state.settings.focusQuiet else { return }
        let store = state.store
        model.update(ml: ml, drink: drink, progress: store.progress, consumed: store.consumed, goal: store.goal,
                     settings: state.settings)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            panel.positionTopCenter(fromTop: 0.08)
            let final = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: final.x, y: final.y + 18))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.3, 0.4, 1)
                panel.animator().setFrameOrigin(final)
                panel.animator().alphaValue = 1
            }
        }
        hideLater.schedule(after: 1.8) { [weak self] in self?.hide() }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                // Drop the views; the next drink builds them again.
                self?.panel = nil
                Memory.relieve()
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 92),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.configureTransparent(level: .statusBar, shadow: true)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

@Observable
final class HUDModel {
    var ml: Double = 0
    var drink: DrinkKind = .water
    var progress: Double = 0
    var consumed: Double = 0
    var goal: Double = 1
    var unit: VolumeUnit = .milliliters
    var theme: LiquidTheme = .ocean
    var style: BottleStyle = .classic
    var custom = CustomBottleSpec()

    func update(ml: Double, drink: DrinkKind, progress: Double, consumed: Double, goal: Double, settings: SettingsStore) {
        self.ml = ml
        self.drink = drink
        self.progress = progress
        self.consumed = consumed
        self.goal = goal
        unit = settings.unit
        theme = settings.theme
        style = settings.bottleStyle
        custom = settings.customBottle
    }
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: 14) {
            MiniBottle(style: model.style, fraction: model.progress, theme: model.theme, highlighted: true, custom: model.custom)
                .frame(width: 30, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: model.ml < 0 ? "arrow.uturn.backward" : model.drink.symbol)
                        .foregroundStyle(model.theme.color(for: model.drink))
                    Text(model.ml < 0 ? "Removed \(Volume.format(-model.ml, model.unit))"
                                      : "+\(Volume.format(model.ml, model.unit)) \(model.drink.title.lowercased())")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Text("\(Volume.format(model.consumed, model.unit)) of \(Volume.format(model.goal, model.unit)) · \(model.progress.percent)%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressView(value: min(model.progress, 1))
                    .progressViewStyle(.linear)
                    .tint(model.theme.mid)
                    .frame(width: 170)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 92)
        .background(VisualEffectBlur(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.16)))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
