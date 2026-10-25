import AppKit
import SwiftUI
import SipCore

/// One band of a layered bottle: a drink and how much of the goal it fills.
struct LiquidLayer: Equatable {
    var drink: DrinkKind
    var fraction: Double
}

/// Things floating in or rising from the water.
struct BottleExtras: Equatable {
    var iceCubes = 0
    var lemon = false
    var steam = false
}

/// Everything about how a bottle looks that comes from Settings.
struct BottleAppearance: Equatable {
    var style: BottleStyle = .classic
    var theme: LiquidTheme = .ocean
    var motion: MotionLevel = .full
    var maxFPS: Int = 60
    var showTicks = true
    var showCondensation = true
    var showBubbles = true
    var layered = true
    var unit: VolumeUnit = .milliliters
    var goalML: Double = 2500
    /// Room around the bottle's frame that effects may draw into.
    var bleed: CGFloat = 0
    /// Changes when the Daylight liquid moves to a new time of day, so the
    /// bottle redraws in the new colours.
    var phase = 0
    /// The designer's shape, used when `style` is `.custom`.
    var custom = CustomBottleSpec()
    /// Printed on the glass, if set.
    var label = ""
    var tint: GlassTint = .clear
    /// Hour marks on the glass ("by 1 PM, here").
    var timeMarks: [TimeMarkSpec] = []
    var celebration: CelebrationStyle = .surprise

    init() {}

    /// Everything baked into the still images, so they're redrawn only when
    /// one of these changes.
    var imageKey: String {
        "\(style)|\(style == .custom ? custom.key : "")|\(theme)|\(phase)|\(showTicks)|\(showCondensation)|\(unit)|\(goalML)|\(bleed)|\(label)|\(tint)|\(timeMarks.map { "\($0.fraction)\($0.label)" })"
    }

    init(_ settings: SettingsStore) {
        style = settings.bottleStyle
        theme = settings.theme
        // A Focus with "calm the water" turns Full down to Calm.
        motion = settings.focusCalmMotion && settings.motion == .full ? .calm : settings.motion
        maxFPS = settings.maxFPS
        showTicks = settings.showTicks
        showCondensation = settings.showCondensation
        showBubbles = settings.showBubbles
        layered = settings.layeredDrinks
        unit = settings.unit
        goalML = settings.dailyGoalML
        phase = settings.theme == .daylight ? DaylightPhase.current.rawValue : 0
        custom = settings.customBottle
        label = settings.bottleLabel
        tint = settings.glassTint
        celebration = settings.celebrationStyle
    }
}

/// App-wide hints for how hard bottles should work.
@Observable
final class AnimationPolicy {
    static let shared = AnimationPolicy()
    /// No keyboard or mouse input for a while: nobody is watching closely, so
    /// idle waves drop to a slow drift until you're back.
    var userAway = false
}

/// The animated bottle. A thin SwiftUI wrapper around `LiquidLayerView`, which
/// does the simulation and drawing with Core Animation.
struct BottleView: View {
    var progress: Double
    var layers: [LiquidLayer] = []
    var appearance: BottleAppearance
    var fizz: Double = 1
    var paused = false
    /// Accepts taps and drag-to-pour.
    var interactive = false
    /// Sloshes when its window is dragged.
    var followsWindow = false
    var extras = BottleExtras()
    var life = BottleLife()
    var onTap: (() -> Void)?
    var onPour: ((Double) -> Void)?
    var onPourOut: (() -> Void)?

    @Environment(\.animationsPaused) private var windowHidden

    var body: some View {
        BottleLayerRepresentable(
            config: LiquidLayerView.Config(progress: max(progress, 0), layers: layers, look: appearance, fizz: fizz,
                                           paused: paused || windowHidden, interactive: interactive,
                                           followsWindow: followsWindow, extras: extras, life: life),
            onTap: onTap, onPour: onPour, onPourOut: onPourOut)
            // Effects may spill past the bottle's frame by `bleed`.
            .padding(-appearance.bleed)
            .accessibilityElement()
            .accessibilityLabel("Water bottle, \(Int((progress * 100).rounded())) percent of today's goal")
    }
}

private struct BottleLayerRepresentable: NSViewRepresentable {
    var config: LiquidLayerView.Config
    var onTap: (() -> Void)?
    var onPour: ((Double) -> Void)?
    var onPourOut: (() -> Void)?

    func makeNSView(context: Context) -> LiquidLayerView {
        LiquidLayerView(frame: .zero)
    }

    func updateNSView(_ view: LiquidLayerView, context: Context) {
        view.onTap = onTap
        view.onPour = onPour
        view.onPourOut = onPourOut
        view.apply(config)
    }
}

/// A still bottle for small multiples (the week strip, pickers). Drawn once
/// per change rather than on a timeline.
struct MiniBottle: View {
    var style: BottleStyle
    var fraction: Double
    var theme: LiquidTheme
    var highlighted = false
    var custom = CustomBottleSpec()

    var body: some View {
        Canvas { context, size in
            let geometry = BottleGeometry.of(style, custom: custom)
            let layout = BottleLayout(size: size, inset: 1)
            var ctx = context
            ctx.translateBy(x: layout.origin.x, y: layout.origin.y)
            ctx.scaleBy(x: layout.scale, y: layout.scale)
            let px = 1 / layout.scale
            ctx.fill(geometry.outer, with: .color(.white.opacity(0.08)))
            let f = min(max(fraction, 0), 1)
            if f > 0.005 {
                var liquid = ctx
                liquid.clip(to: geometry.inner)
                let top = geometry.levelY(f)
                let rect = CGRect(x: 0, y: top, width: 100, height: geometry.emptyY - top + 6)
                liquid.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [theme.surface, theme.mid, theme.deep]),
                    startPoint: CGPoint(x: 50, y: top), endPoint: CGPoint(x: 50, y: geometry.emptyY)))
                liquid.fill(Path(CGRect(x: 0, y: top, width: 100, height: 3 * px)), with: .color(.white.opacity(0.6)))
            }
            ctx.stroke(geometry.outer, with: .color(.white.opacity(highlighted ? 0.95 : 0.5)),
                       lineWidth: (highlighted ? 1.6 : 1.1) * px)
            if let handle = geometry.handle {
                ctx.stroke(handle, with: .color(.white.opacity(highlighted ? 0.8 : 0.45)), lineWidth: 4 * px)
            }
            if geometry.cap != .none {
                ctx.fill(Path(roundedRect: geometry.capRect, cornerRadius: 4),
                         with: .color(fraction >= 1 ? theme.mid : .white.opacity(0.35)))
            }
        }
    }
}
