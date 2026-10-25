import Charts
import SwiftUI
import SipCore

final class InsightsSelection: ObservableObject {
    @Published var day: Date?
    @Published var hour: Int?
}

/// History at a glance. Every chart is a single series, so the title names it
/// and there's no legend box; values are written in text colours, never in
/// the series colour.
struct InsightsView: View {
    let state: AppState
    @StateObject private var selection = InsightsSelection()

    var body: some View {
        let store = state.store
        let settings = state.settings
        let days = store.recentDays(30)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("How your hydration has gone, from \(store.history.entries.count) drinks logged.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.showRecap()
                    } label: {
                        Label("Recap", systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        _ = ShareCardView.copy(state: state)
                    } label: {
                        Label("Copy Week Card", systemImage: "doc.on.doc")
                    }
                    Button {
                        ShareCardView.save(state: state)
                    } label: {
                        Label("Save Week Card…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.theme.mid)
                }

                StatTiles(store: store, settings: settings, days: days)

                HStack(alignment: .top, spacing: 18) {
                    ChartCard(title: "Level and score", subtitle: "XP from every drink, goal, streak and challenge.") {
                        LevelScoreCard(state: state)
                    }
                    ChartCard(title: "Coach", subtitle: "From your last four weeks.") {
                        CoachList(state: state)
                    }
                }

                if settings.caffeineTracking {
                    ChartCard(title: "Caffeine in you", subtitle: caffeineCurveSubtitle) {
                        CaffeineCurve(state: state)
                            .frame(height: 150)
                    }
                }

                ChartCard(title: "Last 30 days", subtitle: "Daily intake against your goal. The line is the 7-day average.") {
                    DailyChart(days: days, store: store, settings: settings, selection: selection)
                        .frame(height: 220)
                }

                HStack(alignment: .top, spacing: 18) {
                    ChartCard(title: "12 weeks", subtitle: "Each drop is a day; deeper is closer to the goal.") {
                        CalendarGrid(store: store, theme: settings.theme)
                    }
                    ChartCard(title: "What you drink", subtitle: caffeineSubtitle(days: days, settings: settings)) {
                        DrinkBreakdown(days: days, settings: settings)
                    }
                }

                ChartCard(title: "Trophy shelf",
                          subtitle: "\(state.achievements.filter(\.unlocked).count) of \(state.achievements.count) badges. Rarer ones glow differently.") {
                    AchievementsGrid(badges: state.achievements, theme: settings.theme)
                }

                ChartCard(title: "When you drink", subtitle: "Average per hour over the last 30 days. Shaded: your waking hours.") {
                    HourlyChart(store: store, settings: settings, selection: selection)
                        .frame(height: 170)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 760, minHeight: 600)
    }

    private var caffeineCurveSubtitle: String {
        var text = "Today, from waking to bed, at a \(String(format: "%.1f", state.settings.caffeineHalfLifeHours))-hour half-life."
        if let clear = state.caffeineClearTime {
            text += " Under 50 mg by \(clear.formatted(date: .omitted, time: .shortened))."
        }
        return text
    }
}

/// Level, XP to the next, today's score and its parts.
private struct LevelScoreCard: View {
    let state: AppState

    var body: some View {
        let derived = state.derived
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(derived.level.level)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.gold)
                VStack(alignment: .leading, spacing: 0) {
                    Text(derived.level.title).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("\(derived.level.xp.formatted()) XP · \(derived.level.xpToNextLevel.formatted()) to go")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Meter(value: derived.level.progress, tint: Palette.gold)
            if let score = derived.score {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Today's score").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(score.total)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(score.grade).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    part("Amount", score.amount, Score.amountPoints)
                    part("Spread through the day", score.spread, Score.spreadPoints)
                    part("Caffeine", score.caffeine, Score.caffeinePoints)
                    part("Last 7 days", score.consistency, Score.consistencyPoints)
                }
                .font(.caption)
            }
        }
    }

    private func part(_ label: String, _ value: Int, _ max: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Meter(value: Double(value) / Double(max), tint: state.settings.theme.mid)
                .frame(minWidth: 120)
            Text("\(value)/\(max)").monospacedDigit()
        }
    }
}

private struct CoachList: View {
    let state: AppState

    var body: some View {
        let derived = state.derived
        VStack(alignment: .leading, spacing: 10) {
            if let suggestion = derived.goalSuggestion {
                HStack(alignment: .top) {
                    Image(systemName: "target").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try \(Volume.formatCompact(suggestion.goalML, state.settings.unit)) a day").bold()
                        Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Use It") { state.acceptGoalSuggestion() }
                            Button("Not Now") { state.dismissGoalSuggestion() }
                        }
                        .controlSize(.small)
                    }
                }
            }
            ForEach(derived.tips.prefix(4)) { tip in
                HStack(alignment: .top) {
                    Image(systemName: tip.symbol).foregroundStyle(Color(hex: 0x8FD3FF)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).bold()
                        Text(tip.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if derived.tips.isEmpty, derived.goalSuggestion == nil {
                Text(state.settings.coachEnabled ? "Tips appear after a week of logging." : "Coach tips are off (Settings → Coach & Play).")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A thin rounded bar.
private struct Meter: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: max(g.size.width * min(max(value, 0), 1), 4))
            }
        }
        .frame(height: 6)
    }
}

/// Caffeine through today, with the 50 mg sleep line and a mark for now.
private struct CaffeineCurve: View {
    let state: AppState

    var body: some View {
        let settings = state.settings
        let window = state.store.wakingWindow
        let entries = state.store.history.entries.filter { window.wake.timeIntervalSince($0.date) < 36 * 3600 && $0.date <= window.sleep }
        let points = CaffeineModel.curve(from: window.wake, to: window.sleep, step: 900, entries: entries,
                                         rates: settings.caffeineRates, halfLifeHours: settings.caffeineHalfLifeHours)
        Chart {
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), y: .value("mg", point.mg))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xC98B3C).opacity(0.5), Color(hex: 0xC98B3C).opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("mg", point.mg))
                    .foregroundStyle(Color(hex: 0xC98B3C))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(y: .value("Sleep-friendly", 50))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("50 mg").font(.caption2).foregroundStyle(.secondary)
                }
            if state.now > window.wake, state.now < window.sleep {
                RuleMark(x: .value("Now", state.now))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .chartYAxisLabel("mg")
    }
}

private func caffeineSubtitle(days: [DaySummary], settings: SettingsStore) -> String {
    guard settings.caffeineTracking else { return "Total by type, last 30 days." }
    let logged = days.filter { $0.entryCount > 0 }
    let mg = logged.reduce(0.0) { total, day in
        total + day.byDrink.reduce(0) { $0 + $1.value * settings.caffeineRates[$1.key] }
    }
    let average = logged.isEmpty ? 0 : mg / Double(logged.count)
    return "Total by type, last 30 days. Caffeine averages \(Int(average.rounded())) mg a day."
}

private struct AchievementsGrid: View {
    let badges: [AchievementStatus]
    let theme: LiquidTheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            // Unlocked first, rarest first within each.
            ForEach(badges.sorted { a, b in
                a.unlocked != b.unlocked ? a.unlocked : (a.rarity != b.rarity ? a.rarity > b.rarity : a.progress > b.progress)
            }) { badge in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(badge.unlocked ? .white : .secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(badge.unlocked
                            ? AnyShapeStyle(LinearGradient(colors: rarityColors(badge.rarity), startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.primary.opacity(0.08))))
                        .overlay(Circle().strokeBorder(.white.opacity(badge.unlocked ? 0.35 : 0), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(badge.title).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            if badge.rarity != .common {
                                Text(badge.rarity.title.uppercased())
                                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(rarityColors(badge.rarity)[1].opacity(0.25)))
                            }
                        }
                        Text(badge.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        if !badge.unlocked {
                            ProgressView(value: badge.progress)
                                .progressViewStyle(.linear)
                                .tint(theme.mid)
                            Text(badge.progressText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(badge.unlocked ? Palette.gold.opacity(0.1) : Color.primary.opacity(0.03)))
                .opacity(badge.unlocked ? 1 : 0.85)
                .help(badge.unlocked ? "Unlocked" : badge.progressText)
            }
        }
    }
}

private func rarityColors(_ rarity: AchievementRarity) -> [Color] {
    switch rarity {
    case .common: return [Color(hex: 0xB9C4D6), Color(hex: 0x7A8699)]
    case .rare: return [Color(hex: 0x8FD3FF), Color(hex: 0x2E8BFF)]
    case .epic: return [Color(hex: 0xD3A6FF), Color(hex: 0x8B4DFF)]
    case .legendary: return [Color(hex: 0xFFE27A), Color(hex: 0xFF9F1C)]
    }
}

private struct ChartCard<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Stat tiles

private struct StatTiles: View {
    let store: HydrationStore
    let settings: SettingsStore
    let days: [DaySummary]

    var body: some View {
        let unit = settings.unit
        let firstDay = store.firstDay
        let tracked = days.filter { day in
            guard let firstDay else { return false }
            return day.key >= firstDay && day.key != store.today
        }
        let logged = tracked.filter { $0.entryCount > 0 }
        let average = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.effectiveML } / Double(logged.count)
        let hitRate = tracked.isEmpty ? 0 : Double(tracked.filter(\.met).count) / Double(tracked.count)
        let total = store.history.entries.reduce(0) { $0 + $1.amountML }
        let best = store.summaries.values.max { $0.effectiveML < $1.effectiveML }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            StatTile(symbol: "drop.fill", tint: settings.theme.mid, label: "Today",
                     value: "\(Int((store.progress * 100).rounded()))%",
                     detail: "\(Volume.format(store.consumed, unit)) of \(Volume.format(store.goal, unit))")
            StatTile(symbol: "chart.line.uptrend.xyaxis", tint: settings.theme.mid, label: "Daily average",
                     value: Volume.formatCompact(average, unit), detail: "Last 30 days, days you logged")
            StatTile(symbol: "target", tint: Palette.goal, label: "Goal hit rate",
                     value: "\(Int((hitRate * 100).rounded()))%", detail: "\(tracked.filter(\.met).count) of \(tracked.count) days")
            StatTile(symbol: "flame.fill", tint: FlameTier(streak: max(store.streak.current, 1)).colors[1], label: "Current streak",
                     value: "\(store.streak.current) day\(store.streak.current == 1 ? "" : "s")",
                     detail: store.streak.freezesBanked > 0 ? "\(store.streak.freezesBanked) freeze\(store.streak.freezesBanked == 1 ? "" : "s") banked"
                                                            : (store.streak.nextMilestone.map { "\($0 - store.streak.current) to \($0)" } ?? ""))
            StatTile(symbol: "trophy.fill", tint: Palette.gold, label: "Best streak",
                     value: "\(store.streak.best) day\(store.streak.best == 1 ? "" : "s")",
                     detail: best.map { "Best day \(Volume.formatCompact($0.effectiveML, unit))" } ?? "")
            StatTile(symbol: "waterbottle.fill", tint: settings.theme.deep, label: "All time",
                     value: Volume.formatCompact(total, unit),
                     detail: "Across \(store.summaries.count) day\(store.summaries.count == 1 ? "" : "s")")
        }
    }
}

private struct StatTile: View {
    var symbol: String
    var tint: Color
    var label: String
    var value: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Daily chart

private struct DailyChart: View {
    let days: [DaySummary]
    let store: HydrationStore
    let settings: SettingsStore
    @ObservedObject var selection: InsightsSelection

    private struct Point: Identifiable {
        var id: DayKey { key }
        var key: DayKey
        var date: Date
        var ml: Double
        var goal: Double
        var met: Bool
        var average: Double?
    }

    var body: some View {
        let unit = settings.unit
        let theme = settings.theme
        let points = makePoints()
        let goal = store.goal
        let selected = selection.day.flatMap { day in points.min { abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day)) } }

        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.date, unit: .day),
                        y: .value("Intake", Volume.toDisplay(p.ml, unit)),
                        width: .ratio(0.62))
                    .foregroundStyle(p.met ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(theme.mid.opacity(0.35)))
                    .cornerRadius(4)
                    .opacity(selected == nil || selected?.key == p.key ? 1 : 0.45)
            }
            ForEach(points.filter { $0.average != nil }) { p in
                LineMark(x: .value("Day", p.date, unit: .day),
                         y: .value("7-day average", Volume.toDisplay(p.average ?? 0, unit)))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Goal", Volume.toDisplay(goal, unit)))
                .foregroundStyle(Color.primary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .overlay, alignment: .trailing) {
                    Text("Goal \(Volume.formatCompact(goal, unit))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.regularMaterial))
                }
            if let selected {
                RuleMark(x: .value("Day", selected.date, unit: .day))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(.caption.weight(.semibold))
                            Text("\(Volume.format(selected.ml, unit)) · \(Int((selected.ml / max(selected.goal, 1) * 100).rounded()))%")
                                .font(.caption).monospacedDigit()
                            Label(selected.met ? "Goal met" : "Goal missed",
                                  systemImage: selected.met ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(selected.met ? Color.green : Color.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                    }
            }
        }
        .chartXSelection(value: $selection.day)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Volume.tickLabel(Volume.fromDisplay(v, unit), unit))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }

    private func makePoints() -> [Point] {
        var result: [Point] = []
        for (i, day) in days.enumerated() {
            let window = days[max(0, i - 6)...i]
            let average = i >= 6 ? window.reduce(0) { $0 + $1.effectiveML } / Double(window.count) : nil
            result.append(Point(key: day.key, date: store.clock.time(12 * 60, on: day.key),
                                ml: day.effectiveML, goal: day.goalML, met: day.met, average: average))
        }
        return result
    }
}

// MARK: - Calendar

private struct CalendarGrid: View {
    let store: HydrationStore
    let theme: LiquidTheme

    var body: some View {
        let today = store.today
        // Columns are weeks ending with the current one; rows run Sunday–Saturday.
        let endOfWeek = today.adding(days: 7 - today.weekday)
        let start = endOfWeek.adding(days: -(12 * 7) + 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, letter in
                        Text(letter).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10, height: 16)
                    }
                }
                ForEach(0..<12, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let key = start.adding(days: week * 7 + weekday)
                            cell(key: key, today: today)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.15, 0.4, 0.7, 1.0], id: \.self) { f in
                    DropShape().fill(theme.mid.opacity(0.15 + 0.85 * f)).frame(width: 10, height: 13)
                }
                Text("Goal").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "snowflake").font(.caption2).foregroundStyle(Palette.freeze)
                Text("Freeze").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cell(key: DayKey, today: DayKey) -> some View {
        if key > today {
            Color.clear.frame(width: 14, height: 16)
        } else {
            let summary = store.summary(for: key)
            let f = min(summary.progress, 1)
            ZStack {
                DropShape()
                    .fill(summary.entryCount == 0 ? Color.primary.opacity(0.07) : theme.mid.opacity(0.15 + 0.85 * f))
                if store.streak.frozenDays.contains(key) {
                    Image(systemName: "snowflake").font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.freeze)
                }
            }
            .overlay(DropShape().stroke(key == today ? Color.primary : .clear, lineWidth: 1.2))
            .frame(width: 14, height: 16)
            .help("\(key.description): \(Int((summary.progress * 100).rounded()))%\(summary.met ? " ✓" : "")")
        }
    }
}

struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.64),
                   control1: CGPoint(x: rect.midX + w * 0.18, y: rect.minY + h * 0.2),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.38))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + h * 0.64), radius: w / 2,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.38),
                   control2: CGPoint(x: rect.midX - w * 0.18, y: rect.minY + h * 0.2))
        p.closeSubpath()
        return p
    }
}

// MARK: - Drink breakdown

private struct DrinkBreakdown: View {
    let days: [DaySummary]
    let settings: SettingsStore

    var body: some View {
        let unit = settings.unit
        var totals: [DrinkKind: Double] = [:]
        for day in days { for (drink, ml) in day.byDrink { totals[drink, default: 0] += ml } }
        let rows = totals.sorted { $0.value > $1.value }
        let sum = max(rows.reduce(0) { $0 + $1.value }, 1)
        return Group {
            if rows.isEmpty {
                Text("No drinks in the last 30 days.").foregroundStyle(.secondary)
            } else {
                Chart(rows, id: \.key) { row in
                    BarMark(x: .value("Amount", Volume.toDisplay(row.value, unit)),
                            y: .value("Drink", row.key.title),
                            height: .ratio(0.6))
                        .foregroundStyle(settings.theme.color(for: row.key).gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 6) {
                            Text("\(Volume.formatCompact(row.value, unit)) · \(Int((row.value / sum * 100).rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                }
                .chartXAxis(.hidden)
                .chartXScale(range: .plotDimension(endPadding: 90))
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel().font(.caption) }
                }
                .frame(height: CGFloat(rows.count) * 26 + 10)
            }
        }
    }
}

// MARK: - Hourly

private struct HourlyChart: View {
    let store: HydrationStore
    let settings: SettingsStore
    @ObservedObject var selection: InsightsSelection

    var body: some View {
        let unit = settings.unit
        let theme = settings.theme
        let start = store.clock.start(of: store.today.adding(days: -29))
        var buckets = Array(repeating: 0.0, count: 24)
        for entry in store.history.entries where entry.date >= start {
            buckets[Calendar.current.component(.hour, from: entry.date)] += entry.amountML
        }
        let averages = buckets.map { $0 / 30 }
        let wake = Double(settings.wakeMinutes) / 60
        let sleepRaw = Double(settings.sleepMinutes) / 60
        let sleep = sleepRaw <= wake ? 24 : sleepRaw
        let selected = selection.hour.map { min(max($0, 0), 23) }

        return Chart {
            RectangleMark(xStart: .value("Wake", wake), xEnd: .value("Sleep", sleep))
                .foregroundStyle(theme.mid.opacity(0.07))
            ForEach(0..<24, id: \.self) { hour in
                BarMark(x: .value("Hour", Double(hour) + 0.5),
                        y: .value("Average", Volume.toDisplay(averages[hour], unit)),
                        width: .fixed(14))
                    .foregroundStyle(theme.gradient)
                    .cornerRadius(4)
                    .opacity(selected == nil || selected == hour ? 1 : 0.45)
            }
            if let selected {
                RuleMark(x: .value("Hour", Double(selected) + 0.5))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(String(format: "%02d:00", selected))–\(String(format: "%02d:00", (selected + 1) % 24)): \(Volume.format(averages[selected], unit)) a day")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.regularMaterial))
                    }
            }
        }
        .chartXScale(domain: 0...24)
        .chartXSelection(value: Binding(get: { selection.hour.map(Double.init) },
                                        set: { selection.hour = $0.map { Int($0) } }))
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 24]) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(String(format: "%02d", Int(v) % 24)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Volume.tickLabel(Volume.fromDisplay(v, unit), unit)) }
                }
            }
        }
    }
}
