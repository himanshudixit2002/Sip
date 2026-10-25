import SwiftUI
import SipCore

// Pieces for the gameplay and coaching features: the plant, level, today's
// challenge, a coach tip, buddies and a small calendar heatmap. All static
// drawing with one-shot, value-driven animations; nothing here runs a clock.

/// A little pot plant that grows with your good days, flowers on a streak
/// and droops when you're behind.
struct PlantView: View {
    var plant: PlantState
    var theme: LiquidTheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Pot.
            let potTop = h * 0.66
            var pot = Path()
            pot.move(to: CGPoint(x: w * 0.18, y: potTop))
            pot.addLine(to: CGPoint(x: w * 0.82, y: potTop))
            pot.addLine(to: CGPoint(x: w * 0.72, y: h))
            pot.addLine(to: CGPoint(x: w * 0.28, y: h))
            pot.closeSubpath()
            ctx.fill(pot, with: .linearGradient(Gradient(colors: [Color(hex: 0xE07A4D), Color(hex: 0xA44A2A)]),
                                                startPoint: CGPoint(x: 0, y: potTop), endPoint: CGPoint(x: 0, y: h)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.12, y: potTop - 3, width: w * 0.76, height: 5), cornerRadius: 2),
                     with: .color(Color(hex: 0xF0956A)))

            // Stem, bending over as it droops.
            let droop = CGFloat(plant.droop)
            let base = CGPoint(x: w / 2, y: potTop - 2)
            let height = h * (0.22 + 0.06 * CGFloat(min(plant.leaves, 8)))
            let tip = CGPoint(x: w / 2 + droop * w * 0.28, y: base.y - height * (1 - droop * 0.35))
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: tip, control: CGPoint(x: w / 2 - droop * 2, y: base.y - height * 0.6))
            ctx.stroke(stem, with: .color(Color(hex: 0x3FAE5A)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            // Leaves up the stem, alternating sides.
            for i in 0..<plant.leaves {
                let f = CGFloat(i + 1) / CGFloat(max(plant.leaves, 1) + 1)
                let p = CGPoint(x: base.x + (tip.x - base.x) * f * f, y: base.y + (tip.y - base.y) * f)
                let side: CGFloat = i % 2 == 0 ? -1 : 1
                let length = w * 0.24 * (1 - f * 0.35)
                var leaf = Path()
                leaf.move(to: p)
                let end = CGPoint(x: p.x + side * length, y: p.y - length * (0.35 - droop * 0.6))
                leaf.addQuadCurve(to: end, control: CGPoint(x: p.x + side * length * 0.5, y: p.y - length * 0.55))
                leaf.addQuadCurve(to: p, control: CGPoint(x: p.x + side * length * 0.55, y: p.y + length * 0.05))
                ctx.fill(leaf, with: .color(Color(hex: i % 3 == 0 ? 0x4BD16B : 0x37B657)))
            }
            if plant.flowering {
                for k in 0..<5 {
                    let a = Double(k) / 5 * .pi * 2
                    let petal = CGRect(x: tip.x + CGFloat(cos(a)) * 2.6 - 2.2, y: tip.y + CGFloat(sin(a)) * 2.6 - 2.2,
                                       width: 4.4, height: 4.4)
                    ctx.fill(Path(ellipseIn: petal), with: .color(Color(hex: 0xFF8FB1)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 1.6, y: tip.y - 1.6, width: 3.2, height: 3.2)),
                         with: .color(Color(hex: 0xFFE27A)))
            }
        }
        // Still: redrawn only when the plant changes. (A drop arcing over it
        // redrew the canvas every frame of every pour, ~50 MB of buffers.)
        .accessibilityLabel("Plant with \(plant.leaves) leaves\(plant.flowering ? ", flowering" : "")")
    }
}

/// "Lv 9 · Stream" with a progress bar to the next level.
struct LevelBar: View {
    var level: LevelInfo
    var theme: LiquidTheme

    var body: some View {
        HStack(spacing: 6) {
            Text("Lv \(level.level)")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.gold)
            Text(level.title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [Palette.gold, Color(hex: 0xFF9F1C)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(g.size.width * level.progress, 3))
                }
            }
            .frame(height: 4)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: level.xp)
        .help("\(level.xp.formatted()) XP · \(level.xpToNextLevel.formatted()) to level \(level.level + 1)")
    }
}

/// Today's challenge, with a bar.
struct ChallengeCard: View {
    var progress: ChallengeProgress
    var theme: LiquidTheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: progress.done ? "checkmark.seal.fill" : progress.challenge.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(progress.done ? Palette.goal : (progress.failed ? Color.secondary : Palette.badge))
                .frame(width: 22)
                .symbolEffect(.bounce, value: progress.done)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(progress.challenge.title)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("+\(progress.challenge.xp) XP")
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.gold)
                }
                ProgressView(value: min(max(progress.fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(progress.done ? Palette.goal : theme.mid)
                    .controlSize(.mini)
                Text(progress.text)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress.fraction)
    }
}

/// One coach tip.
struct CoachCard: View {
    var tip: CoachTip

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: tip.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x8FD3FF))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.system(size: 11.5, weight: .bold, design: .rounded)).lineLimit(1)
                Text(tip.detail).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }
}

/// Friends' bottles, side by side. Hover one to nudge them.
struct BuddiesRow: View {
    var cards: [BuddyCard]
    var theme: LiquidTheme
    var style: BottleStyle
    var poke: (BuddyCard) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(cards.prefix(5)) { card in
                Button { poke(card) } label: {
                    VStack(spacing: 3) {
                        MiniBottle(style: style, fraction: Double(card.percent) / 100, theme: theme,
                                   highlighted: card.percent >= 100)
                            .frame(width: 22, height: 38)
                        Text(card.name).font(.system(size: 9.5, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text("\(card.percent)%").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(width: 48)
                }
                .buttonStyle(PressableStyle())
                .help("\(card.name): \(card.percent)% today, \(card.streak)-day streak, level \(card.level). Click to nudge.")
            }
        }
    }
}

/// Twelve weeks of days, coloured by how much of the goal you drank.
struct HeatmapMini: View {
    var summaries: [DayKey: DaySummary]
    var today: DayKey
    var theme: LiquidTheme

    var body: some View {
        let weeks = 12
        // Columns are weeks ending with this one; rows are days.
        let lastColumnStart = today.adding(days: -(today.weekday - 1))
        let first = lastColumnStart.adding(days: -7 * (weeks - 1))
        Grid(horizontalSpacing: 2.5, verticalSpacing: 2.5) {
            ForEach(0..<7, id: \.self) { row in
                GridRow {
                    ForEach(0..<weeks, id: \.self) { column in
                        let day = first.adding(days: column * 7 + row)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(day))
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .help("The last 12 weeks")
    }

    private func color(_ day: DayKey) -> Color {
        guard day <= today else { return .clear }
        guard let summary = summaries[day], summary.entryCount > 0 else { return .white.opacity(0.07) }
        let p = min(summary.progress, 1)
        return summary.met ? Palette.goal.opacity(0.95) : theme.mid.opacity(0.18 + p * 0.6)
    }
}
