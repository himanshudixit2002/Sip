import AppKit
import SwiftUI
import SipCore

// MARK: - Card background

/// `NSVisualEffectView` pinned to the active state: Sip never becomes the
/// active app, and the default would draw the "inactive window" grey.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blending
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

struct CardBackgroundModifier: ViewModifier {
    var style: CardBackground
    var opacity: Double
    var cornerRadius: CGFloat = 26

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    func body(content: Content) -> some View {
        switch style {
        case .glass, .clearGlass:
            if #available(macOS 26.0, *) {
                // A light smoke tint keeps the white text readable when the
                // glass sits over something bright.
                content.glassEffect((style == .glass ? Glass.regular : Glass.clear).tint(.black.opacity(style == .glass ? 0.42 : 0.3)), in: shape)
            } else {
                frosted(content)
            }
        case .frosted:
            frosted(content)
        case .solid:
            content
                .background(shape.fill(LinearGradient(colors: [Color(hex: 0x16233F), Color(hex: 0x0A1122)],
                                                      startPoint: .top, endPoint: .bottom)).opacity(opacity))
                .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        case .none:
            content.shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        }
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(VisualEffectBlur().clipShape(shape).opacity(opacity))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

/// Drag anywhere on the card that isn't a control to move the window.
struct WindowDraggable: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture(), including: enabled ? .all : .none)
        } else {
            content
        }
    }
}

// MARK: - Streak

struct StreakChip: View {
    var streak: StreakResult
    var compact = false

    var body: some View {
        let tier = FlameTier(streak: streak.current)
        let atRisk = streak.current > 0 && !streak.todayMet
        HStack(spacing: 3) {
            flame(tier: tier, lit: streak.todayMet)
                .opacity(atRisk ? 0.6 : 1)
            Text("\(streak.current)")
                .font(.system(size: compact ? 12 : 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(streak.current)))
            if !compact, streak.freezesBanked > 0 {
                Image(systemName: "snowflake")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.freeze)
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((tier.colors.dropFirst().first ?? .orange).opacity(tier == .none ? 0.12 : 0.2)))
        .overlay(Capsule().strokeBorder((tier.colors.first ?? .orange).opacity(0.25), lineWidth: 0.5))
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: streak.current)
        .help(helpText)
    }

    /// A lit flame glows; it bounces once when the streak grows. Nothing here
    /// loops: a repeating SwiftUI effect redraws the whole card every frame,
    /// even while the widget is covered.
    private func flame(tier: FlameTier, lit: Bool) -> some View {
        Image(systemName: tier == .none ? "flame" : "flame.fill")
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(tier.gradient)
            .shadow(color: (tier.colors.first ?? .orange).opacity(lit && tier != .none ? 0.7 : 0), radius: 3)
            .symbolEffect(.bounce, value: streak.current)
    }

    private var helpText: String {
        var parts = ["\(streak.current)-day streak", "best \(streak.best)"]
        if streak.freezesBanked > 0 {
            parts.append("\(streak.freezesBanked) freeze\(streak.freezesBanked == 1 ? "" : "s") banked")
        }
        if streak.current > 0, !streak.todayMet { parts.append("drink up to keep it going") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Pace

struct PaceInfo {
    var icon: String
    var text: String
    var color: Color

    init(status: PaceStatus, unit: VolumeUnit, wake: String, nudging: Bool) {
        switch status {
        case .goalMet:
            self.init("checkmark.seal.fill", "Goal reached", Palette.goal)
        case .ahead(let ml):
            self.init("hare.fill", "\(Volume.format(ml, unit)) ahead", Color(hex: 0x5EEAD4))
        case .onTrack:
            self.init("checkmark.circle.fill", "On track", Color(hex: 0x6CC8FF))
        case .behind(let ml):
            self.init(nudging ? "drop.fill" : "exclamationmark.circle.fill",
                      nudging ? "Time for a sip" : "\(Volume.format(ml, unit)) behind", Palette.warning)
        case .notStarted:
            self.init("sunrise.fill", "Day starts \(wake)", Color(hex: 0xFFD27A))
        }
    }

    private init(_ icon: String, _ text: String, _ color: Color) {
        self.icon = icon
        self.text = text
        self.color = color
    }
}

struct PacePill: View {
    var info: PaceInfo

    var body: some View {
        // A plain crossfade: `.interpolate` morphs the glyph outlines on the
        // CPU every frame, which cost ~50 MB and a 20% spike per drink.
        HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(.system(size: 10, weight: .bold))
            Text(info.text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .id(info.text)
        .transition(.opacity)
        .foregroundStyle(info.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(info.color.opacity(0.16)))
        .animation(.smooth(duration: 0.4), value: info.text)
    }
}

/// Progress toward the goal, with a tick where you'd ideally be by now.
struct PaceBar: View {
    var progress: Double
    var expected: Double
    var theme: LiquidTheme

    var body: some View {
        let _ = BodyCounter.hit("PaceBar")
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                // A glow drawn as a soft, wider capsule rather than a shadow:
                // an animated shadow is re-rendered off screen every frame.
                Capsule()
                    .fill(theme.mid.opacity(0.35))
                    .frame(width: max(w * min(progress, 1), progress > 0 ? 6 : 0) + 4, height: g.size.height + 4)
                    .offset(x: -2)
                Capsule()
                    .fill(theme.barGradient)
                    .frame(width: max(w * min(progress, 1), progress > 0 ? 6 : 0))
                if expected > 0, expected < 1 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.9))
                        .frame(width: 2, height: g.size.height + 5)
                        .offset(x: w * expected - 1)
                        .help("Where you'd be on an even pace")
                }
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.8, dampingFraction: 0.78), value: progress)
    }
}

// MARK: - Refills and weather

/// "2/4" with a ring for the current bottle. Clicking it logs a full bottle.
struct RefillChip: View {
    var progress: RefillProgress
    var unit: VolumeUnit
    var theme: LiquidTheme
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(progress.current, 1)))
                        .stroke(theme.surface, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 11, height: 11)
                Text("\(progress.finished)/\(progress.needed)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.finished)))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(theme.mid.opacity(0.2)))
            .overlay(Capsule().strokeBorder(theme.surface.opacity(0.25), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: progress.finished)
        .help("Bottle \(min(progress.finished + 1, progress.needed)) of \(progress.needed). Finished a bottle? Click to log \(Volume.format(progress.bottleML, unit)).")
    }
}

/// A sun beside the goal when hot weather raised it.
struct HeatBadge: View {
    var bonusML: Double
    var temperature: Double?
    var unit: VolumeUnit

    var body: some View {
        if bonusML > 0 {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.gold)
                .help("+\(Volume.format(bonusML, unit)) for today's heat\(temperature.map { " (\(Int($0.rounded()))°)" } ?? "")")
        }
    }
}

// MARK: - Amounts

struct AmountReadout: View {
    var consumedML: Double
    var goalML: Double
    var unit: VolumeUnit
    var size: CGFloat = 30

    var body: some View {
        let _ = BodyCounter.hit("AmountReadout")
        let n = Volume.displayNumber(consumedML, unit)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(n.formatted())
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(n)))
                .animation(.snappy(duration: 0.5), value: n)
            Text("/ \(Volume.format(goalML, unit))")
                .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Quick add

struct QuickAddButton: View {
    var cup: Cup
    var unit: VolumeUnit
    var theme: LiquidTheme
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: cup.symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [theme.color(for: cup.drink).opacity(0.75), theme.color(for: cup.drink)],
                                                    startPoint: .top, endPoint: .bottom))
                    .frame(height: 18)
                Text("+\(Volume.displayNumber(cup.amountML, unit))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.13), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .help("Log \(cup.name.lowercased()): \(Volume.format(cup.amountML, unit)) of \(cup.drink.title.lowercased())")
    }

    /// Bigger cups get bigger icons.
    private var iconSize: CGFloat { 10 + CGFloat(min(cup.amountML / 500, 1.2)) * 6 }
}

struct QuickAddPill: View {
    var cup: Cup
    var unit: VolumeUnit
    var theme: LiquidTheme
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                Text(Volume.format(cup.amountML, unit))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(LinearGradient(colors: [theme.mid, theme.deep], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: theme.mid.opacity(0.5), radius: 5, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help("Log \(Volume.format(cup.amountML, unit))")
    }
}

// MARK: - Week and day charts

struct WeekStrip: View {
    var days: [DaySummary]
    var today: DayKey
    var frozen: Set<DayKey>
    var style: BottleStyle
    var theme: LiquidTheme
    var custom = CustomBottleSpec()

    private static let letters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        let _ = BodyCounter.hit("WeekStrip")
        HStack(spacing: 0) {
            ForEach(days) { day in
                let isToday = day.key == today
                VStack(spacing: 3) {
                    // No animation: the big bottle already pours, and an animated
                    // Canvas is redrawn on the CPU every frame.
                    MiniBottle(style: style, fraction: day.progress, theme: theme, highlighted: isToday, custom: custom)
                        .frame(width: 26, height: 46)
                    Text(Self.letters[(day.key.weekday - 1) % 7])
                        .font(.system(size: 9, weight: isToday ? .heavy : .semibold, design: .rounded))
                        .foregroundStyle(isToday ? .primary : .secondary)
                    statusIcon(day, isToday: isToday)
                        .font(.system(size: 8, weight: .bold))
                        .frame(height: 9)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.key.description): \(Int((day.progress * 100).rounded()))% of goal")
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ day: DaySummary, isToday: Bool) -> some View {
        if day.met {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.goal)
        } else if frozen.contains(day.key) {
            Image(systemName: "snowflake").foregroundStyle(Palette.freeze)
        } else if isToday {
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

/// Today's drinks against the ideal even pace: cumulative intake as a filled
/// step line, each drink a droplet sized by amount, the ideal as a dashed
/// diagonal, and a marker for now.
struct SipTimeline: View {
    var entries: [Entry]
    var factors: HydrationFactors
    var goal: Double
    var wake: Date
    var sleep: Date
    var now: Date
    var theme: LiquidTheme

    var body: some View {
        let _ = BodyCounter.hit("SipTimeline")
        Canvas { ctx, size in
            let span = max(sleep.timeIntervalSince(wake), 1)
            let total = entries.reduce(0) { $0 + $1.effectiveML(factors) }
            let top = max(goal, total) * 1.08
            let plot = CGRect(x: 2, y: 4, width: size.width - 4, height: size.height - 16)
            func x(_ d: Date) -> CGFloat { plot.minX + plot.width * CGFloat(min(max(d.timeIntervalSince(wake) / span, 0), 1)) }
            func y(_ ml: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(ml / top) }

            // Baseline and goal line.
            var base = Path()
            base.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            base.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            ctx.stroke(base, with: .color(.white.opacity(0.15)), lineWidth: 1)
            var goalLine = Path()
            goalLine.move(to: CGPoint(x: plot.minX, y: y(goal)))
            goalLine.addLine(to: CGPoint(x: plot.maxX, y: y(goal)))
            ctx.stroke(goalLine, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            // Ideal pace.
            var ideal = Path()
            ideal.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            ideal.addLine(to: CGPoint(x: plot.maxX, y: y(goal)))
            ctx.stroke(ideal, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))

            // Actual: a step line that rises at each drink.
            var cumulative = 0.0
            var points: [(CGPoint, Entry, Double)] = []
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            for entry in entries {
                let ex = x(entry.date)
                line.addLine(to: CGPoint(x: ex, y: y(cumulative)))
                cumulative += entry.effectiveML(factors)
                line.addLine(to: CGPoint(x: ex, y: y(cumulative)))
                points.append((CGPoint(x: ex, y: y(cumulative)), entry, cumulative))
            }
            let endX = now < sleep ? x(now) : plot.maxX
            line.addLine(to: CGPoint(x: max(endX, points.last?.0.x ?? plot.minX), y: y(cumulative)))
            var area = line
            area.addLine(to: CGPoint(x: max(endX, points.last?.0.x ?? plot.minX), y: plot.maxY))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [theme.mid.opacity(0.45), theme.mid.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(line, with: .color(theme.surface), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

            for (point, entry, _) in points {
                let r = 2.4 + CGFloat(min(entry.amountML / 250, 2.2)) * 1.4
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -1.2, dy: -1.2)), with: .color(.black.opacity(0.35)))
                ctx.fill(Path(ellipseIn: rect), with: .color(theme.color(for: entry.drink)))
                ctx.fill(Path(ellipseIn: CGRect(x: point.x - r * 0.45, y: point.y - r * 0.55, width: r * 0.55, height: r * 0.55)),
                         with: .color(.white.opacity(0.8)))
            }

            // Now.
            if now > wake, now < sleep {
                let nx = x(now)
                var marker = Path()
                marker.move(to: CGPoint(x: nx, y: plot.minY))
                marker.addLine(to: CGPoint(x: nx, y: plot.maxY))
                ctx.stroke(marker, with: .color(.white.opacity(0.45)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: nx - 3, y: y(cumulative) - 3, width: 6, height: 6)), with: .color(.white))
            }

            let label = Font.system(size: 8.5, weight: .semibold, design: .rounded)
            ctx.draw(Text(wake.formatted(date: .omitted, time: .shortened)).font(label).foregroundColor(.secondary),
                     at: CGPoint(x: plot.minX, y: size.height - 1), anchor: .bottomLeading)
            ctx.draw(Text(sleep.formatted(date: .omitted, time: .shortened)).font(label).foregroundColor(.secondary),
                     at: CGPoint(x: plot.maxX, y: size.height - 1), anchor: .bottomTrailing)
        }
    }
}

// MARK: - Toast

struct Toast: Equatable, Identifiable {
    var id = UUID()
    var icon: String
    var text: String
    var tint: Color = .white
}

struct ToastView: View {
    var toast: Toast?

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 6) {
                    Image(systemName: toast.icon).foregroundStyle(toast.tint)
                    Text(toast.text).lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.55)))
                .background(VisualEffectBlur(material: .hudWindow).clipShape(Capsule()))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .id(toast.id)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: toast?.id)
    }
}

// MARK: - Formatting

enum RelativeText {
    static func lastSip(_ date: Date?, now: Date, today start: Date) -> String {
        guard let date, date >= start else { return "No drinks yet" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "Last sip just now"
        case ..<60: return "Last sip \(minutes)m ago"
        default:
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "Last sip \(h)h ago" : "Last sip \(h)h \(m)m ago"
        }
    }
}
