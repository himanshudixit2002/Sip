import SwiftUI
import SipCore

/// Window-level state the card needs but doesn't own.
@Observable
final class WidgetVisibility {
    /// Hidden behind other windows, or the screens are asleep: stop animating.
    var hidden = false
    var hovering = false
}

/// The widget window's root: the card at its base size, scaled, centred in a
/// window with room around it for the shadow.
struct WidgetRoot: View {
    let state: AppState
    let visibility: WidgetVisibility

    var body: some View {
        let settings = state.settings
        let size = settings.widgetSize.cardSize
        let scale = settings.widgetScale
        WidgetCard(state: state, hovering: visibility.hovering)
            .frame(width: size.width, height: size.height)
            .environment(\.animationsPaused, visibility.hidden)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(colorScheme(settings))
    }

    private func colorScheme(_ settings: SettingsStore) -> ColorScheme? {
        if let forced = DebugHooks.appearance { return forced == "light" ? .light : .dark }
        // Frosted and Solid are dark materials; text has to be light on them.
        switch settings.cardBackground {
        case .frosted, .solid, .none: return .dark
        case .glass, .clearGlass: return nil
        }
    }
}

struct WidgetCard: View {
    let state: AppState
    var hovering: Bool

    var body: some View {
        let _ = BodyCounter.hit("WidgetCard")
        let settings = state.settings
        Group {
            switch settings.widgetSize {
            case .small: SmallLayout(state: state, hovering: hovering)
            case .medium: MediumLayout(state: state)
            case .large: LargeLayout(state: state)
            case .extraLarge: ExtraLargeLayout(state: state)
            }
        }
        .padding(settings.widgetSize == .small ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .modifier(WindowDraggable(enabled: !settings.lockPosition))
        .modifier(CardBackgroundModifier(style: settings.cardBackground, opacity: settings.cardOpacity))
        .overlay(alignment: .top) {
            ToastView(toast: state.toast).offset(y: -12)
        }
        .overlay(alignment: .topTrailing) {
            // Only built while the pointer is over the card, so the resting
            // widget stays exactly as it was.
            if hovering {
                CardMenuButton { state.showWidgetMenu() }
                    .offset(x: 7, y: -7)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The ⋯ badge on the card's corner while the pointer is over it: the way in
/// to Settings, Insights and the rest without knowing about right-click.
private struct CardMenuButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.62)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Settings, Insights, cups and more")
        .accessibilityLabel("Sip menu")
    }
}

// MARK: - Shared pieces

/// The animated bottle wired to the store and actions.
struct WidgetBottle: View {
    let state: AppState
    /// The pot plant sits beside the bottle on the larger sizes.
    var showsPlant = false

    var body: some View {
        let _ = BodyCounter.hit("WidgetBottle")
        let store = state.store
        let settings = state.settings
        var look = BottleAppearance(settings)
        look.bleed = 12
        look.timeMarks = state.derived.timeMarks.map { TimeMarkSpec(fraction: $0.fraction, label: $0.label) }
        return BottleView(progress: store.progress,
                          layers: store.todayLayers,
                          appearance: look,
                          fizz: store.fizz,
                          interactive: true,
                          followsWindow: true,
                          extras: state.bottleExtras,
                          life: state.bottleLife,
                          onTap: { state.bottleTapped(source: .widget) },
                          onPour: { ml in state.pour(ml: ml, source: .widget) },
                          onPourOut: { SipCommand.undo.perform(state, source: .widget) })
            .overlay(alignment: .bottomTrailing) {
                if showsPlant, settings.companionPlant {
                    PlantView(plant: state.plant, theme: settings.theme)
                        .frame(width: 24, height: 38)
                        .offset(x: 6)
                        .allowsHitTesting(false)
                }
            }
            .help("Click to log \(Volume.format(settings.defaultCup.amountML, settings.unit)). Drag up to pour any amount\(settings.pourOutUndo ? "; drag down from the neck to pour the last one out" : "").")
    }
}

private struct OverflowBadge: View {
    var progress: Double

    var body: some View {
        if progress >= 1.05 {
            Text("×\(String(format: "%.1f", progress))")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient(colors: [Palette.goal, Palette.goalDeep],
                                                          startPoint: .top, endPoint: .bottom)))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Small

struct SmallLayout: View {
    let state: AppState
    var hovering: Bool

    var body: some View {
        let store = state.store
        let settings = state.settings
        let percent = Int((store.progress * 100).rounded())
        HStack(spacing: 2) {
            WidgetBottle(state: state)
                .frame(width: 62)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    StreakChip(streak: store.streak, compact: true)
                }
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(percent)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(percent)))
                        .animation(.snappy(duration: 0.5), value: percent)
                    Text("%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                Text(Volume.formatCompact(store.consumed, settings.unit))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("of \(Volume.formatCompact(store.goal, settings.unit))")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                QuickAddPill(cup: settings.defaultCup, unit: settings.unit, theme: settings.theme) {
                    SipCommand.logDefault.perform(state, source: .widget)
                }
                .opacity(hovering || store.progress < 1 ? 1 : 0.6)
            }
        }
    }
}

// MARK: - Medium

struct MediumLayout: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 12) {
            WidgetBottle(state: state, showsPlant: true)
                .frame(width: 96)
            MediumDetails(state: state)
        }
    }
}

struct MediumDetails: View {
    let state: AppState

    var body: some View {
        let _ = BodyCounter.hit("MediumDetails")
        let store = state.store
        let settings = state.settings
        let now = state.now
        let wake = store.wakingWindow.wake
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(text: "TODAY")
                OverflowBadge(progress: store.progress)
                Spacer(minLength: 0)
                if settings.showRefills {
                    RefillChip(progress: state.refill, unit: settings.unit, theme: settings.theme) {
                        SipCommand.refill.perform(state, source: .widget)
                    }
                    .fixedSize()
                }
                StreakChip(streak: store.streak)
                    .fixedSize()
            }
            .animation(.spring, value: store.progress >= 1.05)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AmountReadout(consumedML: store.consumed, goalML: store.goal, unit: settings.unit, size: 26)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                HeatBadge(bonusML: store.goalBonusML, temperature: state.weather.maxTemperatureC, unit: settings.unit)
            }
            PaceBar(progress: store.progress, expected: store.expectedFraction(at: now), theme: settings.theme)
            HStack(spacing: 6) {
                PacePill(info: PaceInfo(status: store.pace(at: now), unit: settings.unit,
                                        wake: wake.formatted(date: .omitted, time: .shortened),
                                        nudging: state.isNudging))
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(RelativeText.lastSip(store.todayEntries.last?.date, now: now, today: store.clock.start(of: store.today)))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            CupRow(state: state, source: .widget, limit: 3)
        }
    }
}

// MARK: - Large

struct LargeLayout: View {
    let state: AppState
    init(state: AppState) { self.state = state }

    fileprivate func paceCaption(store: HydrationStore) -> String {
        let drinks = "\(store.todayEntries.count) drink\(store.todayEntries.count == 1 ? "" : "s")"
        let caffeine = state.caffeineToday
        return caffeine >= 1 ? "\(drinks) · ☕︎ \(Int(caffeine.rounded())) mg" : drinks
    }

    var body: some View {
        let _ = BodyCounter.hit("LargeLayout")
        let store = state.store
        let settings = state.settings
        let window = store.wakingWindow
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WidgetBottle(state: state, showsPlant: true)
                    .frame(width: 96)
                MediumDetails(state: state)
            }
            .frame(height: 142)

            Divider().opacity(0.4)

            HStack {
                SectionLabel(text: "THIS WEEK")
                Spacer()
                if settings.levelsEnabled {
                    LevelBar(level: state.derived.level, theme: settings.theme)
                        .frame(width: 150)
                } else {
                    Text("Best streak \(store.streak.best)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            WeekStrip(days: store.recentDays(7), today: store.today, frozen: store.streak.frozenDays,
                      style: settings.bottleStyle, theme: settings.theme, custom: settings.customBottle)

            HStack {
                SectionLabel(text: "TODAY'S PACE")
                Spacer()
                Text(paceCaption(store: store))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            SipTimeline(entries: store.todayEntries, factors: settings.factors, goal: store.goal,
                        wake: window.wake, sleep: window.sleep, now: state.now, theme: settings.theme)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Extra large

/// The large widget plus a second column: level and score, today's
/// challenge, a coach tip, and your buddies or the last twelve weeks.
struct ExtraLargeLayout: View {
    let state: AppState

    var body: some View {
        let settings = state.settings
        let store = state.store
        let derived = state.derived
        HStack(alignment: .top, spacing: 16) {
            LargeLayout(state: state)
                .frame(width: 328)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "YOUR DAY")
                    Spacer()
                    if let score = derived.score, !store.todayEntries.isEmpty {
                        Text("Score \(score.total)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                        Text(score.grade)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if let caffeine = state.caffeineNow, caffeine >= 5 {
                    Label(caffeineLine(caffeine), systemImage: "cup.and.heat.waves.fill")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let challenge = derived.challenge {
                    ChallengeCard(progress: challenge, theme: settings.theme)
                }
                if let suggestion = derived.goalSuggestion {
                    CoachCard(tip: CoachTip(id: "goal", symbol: "target", title: "Try \(Volume.formatCompact(suggestion.goalML, settings.unit)) a day",
                                            detail: suggestion.reason, weight: 1))
                } else if let tip = derived.tips.first {
                    CoachCard(tip: tip)
                }
                Spacer(minLength: 0)
                if !state.buddies.cards.isEmpty {
                    SectionLabel(text: "BUDDIES")
                    BuddiesRow(cards: state.buddies.cards, theme: settings.theme, style: .classic) { state.buddies.poke($0) }
                } else {
                    HStack {
                        SectionLabel(text: "12 WEEKS")
                        Spacer()
                        Text("\(store.streak.current)-day streak · best \(store.streak.best)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    HeatmapMini(summaries: store.summaries, today: store.today, theme: settings.theme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caffeineLine(_ mg: Double) -> String {
        var text = "~\(Int(mg.rounded())) mg caffeine in you now"
        if let clear = state.caffeineClearTime {
            text += ", under 50 by \(clear.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }
}
