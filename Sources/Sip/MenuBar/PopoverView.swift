import SwiftUI
import SipCore

struct PopoverView: View {
    let state: AppState
    let presence: PopoverPresence

    var body: some View {
        let store = state.store
        let settings = state.settings
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BottleView(progress: store.progress, layers: store.todayLayers,
                           appearance: BottleAppearance(settings), fizz: store.fizz,
                           paused: !presence.shown, interactive: true, extras: state.bottleExtras,
                           onTap: { state.bottleTapped(source: .popover) },
                           onPour: { ml in state.pour(ml: ml, source: .popover) })
                    .frame(width: 74, height: 136)
                TodaySummaryView(state: state, title: "Today")
            }

            if let challenge = state.derived.challenge {
                ChallengeCard(progress: challenge, theme: settings.theme)
            }

            CupRow(state: state, source: .popover)

            CustomAmountView(state: state, focus: presence.focusCustom) { ml, drink, _ in
                state.logAmount(ml, drink: drink, source: .popover)
            }

            extrasRow(settings: settings)

            if let tip = state.derived.tips.first {
                CoachCard(tip: tip)
            }

            if !state.buddies.cards.isEmpty {
                BuddiesRow(cards: state.buddies.cards, theme: settings.theme, style: settings.bottleStyle) { state.buddies.poke($0) }
            }

            Divider()

            entriesList(store: store, settings: settings)

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 360)
        .focusEffectDisabled()
    }

    /// Finished-bottle button and refill count (if you track refills), and
    /// today's caffeine.
    @ViewBuilder
    private func extrasRow(settings: SettingsStore) -> some View {
        if settings.showRefills || (settings.caffeineTracking && state.caffeineToday >= 1) {
            HStack(spacing: 10) {
                if settings.showRefills {
                    Button {
                        SipCommand.refill.perform(state, source: .popover)
                    } label: {
                        Label("Finished my bottle", systemImage: SipCommand.refill.symbol)
                    }
                    .help("Log \(Volume.format(settings.bottleSizeML, settings.unit))")
                    Text("\(state.refill.finished) of \(state.refill.needed) bottles")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CaffeineBadge(state: state)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func entriesList(store: HydrationStore, settings: SettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's drinks")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    SipCommand.undo.perform(state, source: .popover)
                } label: {
                    Label("Undo", systemImage: SipCommand.undo.symbol)
                }
                .buttonStyle(.borderless)
                .disabled(!SipCommand.undo.isEnabled(state))
                .keyboardShortcut("z", modifiers: .command)
            }
            if store.todayEntries.isEmpty {
                Text("Nothing yet. Click a cup, or drag up on the bottle.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.todayEntries.reversed()) { entry in
                            EntryRow(entry: entry, unit: settings.unit, theme: settings.theme) {
                                state.delete(entry, source: .popover)
                            }
                        }
                    }
                }
                // A popover sizes to its content, and a scroll view has no
                // height of its own, so give it one.
                .frame(height: min(CGFloat(store.todayEntries.count) * 30, 150))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { SipCommand.settings.perform(state, source: .popover) } label: {
                Label("Settings", systemImage: SipCommand.settings.symbol)
            }
            .help("Settings (⌘,)")
            if !state.settings.widgetVisible {
                Text("Widget hidden")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ForEach([SipCommand.quickLog, .share, .insights, .quit], id: \.self) { command in
                Button { command.perform(state, source: .popover) } label: { Image(systemName: command.symbol) }
                    .help(command.title(state).replacingOccurrences(of: "…", with: ""))
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13))
    }
}

/// Today's headline numbers: streak, amount, the pace bar and pill. Shared by
/// the widget and the popover.
struct TodaySummaryView: View {
    let state: AppState
    var title: String
    var amountSize: CGFloat = 26
    var showsStreakLine = true

    var body: some View {
        let store = state.store
        let settings = state.settings
        let now = state.now
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                StreakChip(streak: store.streak)
            }
            AmountReadout(consumedML: store.consumed, goalML: store.goal, unit: settings.unit, size: amountSize)
            PaceBar(progress: store.progress, expected: store.expectedFraction(at: now), theme: settings.theme)
            PacePill(info: PaceInfo(status: store.pace(at: now), unit: settings.unit,
                                    wake: store.wakingWindow.wake.formatted(date: .omitted, time: .shortened),
                                    nudging: state.isNudging))
            if showsStreakLine {
                Text(streakLine(store.streak))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func streakLine(_ streak: StreakResult) -> String {
        var text = "Best streak \(streak.best)"
        if let next = streak.nextMilestone, streak.current > 0 {
            text += " · \(next - streak.current) to \(next) days"
        }
        if streak.freezesBanked > 0 { text += " · ❄︎ \(streak.freezesBanked)" }
        if state.settings.levelsEnabled {
            text += " · Lv \(state.derived.level.level) \(state.derived.level.title)"
        }
        return text
    }
}

/// The quick-add cups, as buttons.
struct CupRow: View {
    let state: AppState
    var source: LogSource
    var limit: Int?

    var body: some View {
        let settings = state.settings
        let cups = limit.map { Array(settings.cups.prefix($0)) } ?? settings.cups
        HStack(spacing: limit == nil ? 8 : 6) {
            ForEach(cups) { cup in
                QuickAddButton(cup: cup, unit: settings.unit, theme: settings.theme) {
                    state.log(cup: cup, source: source)
                }
            }
        }
    }
}

/// Today's caffeine, orange past your limit.
struct CaffeineBadge: View {
    let state: AppState

    private var help: String {
        var text = "Caffeine today (estimated)"
        if let now = state.caffeineNow, now >= 5 {
            text += ". About \(Int(now.rounded())) mg still in you"
            if let clear = state.caffeineClearTime {
                text += ", under 50 mg by \(clear.formatted(date: .omitted, time: .shortened))"
            }
            text += "."
        }
        return text
    }

    var body: some View {
        let settings = state.settings
        let mg = state.caffeineToday
        if settings.caffeineTracking, mg >= 1 {
            Label("\(Int(mg.rounded())) mg", systemImage: "cup.and.heat.waves.fill")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(mg > settings.caffeineLimitMG ? Color.orange : Color.secondary)
                .help(help)
        }
    }
}

final class CustomAmountForm: ObservableObject {
    @Published var amount: Double = 300
    @Published var drink: DrinkKind = .water
    @Published var date = Date()
}

/// A drink picker, an amount and an Add button. The popover logs now; the
/// Data tab passes `pickTime` to add something you forgot.
struct CustomAmountView: View {
    let state: AppState
    var focus = false
    var pickTime: Date?
    var add: (Double, DrinkKind, Date?) -> Void
    @StateObject private var form = CustomAmountForm()
    @FocusState private var amountFocused: Bool

    var body: some View {
        let settings = state.settings
        let unit = settings.unit
        HStack(spacing: 8) {
            Picker("", selection: $form.drink) {
                ForEach(settings.enabledDrinks) { drink in
                    Label(drink.title, systemImage: drink.symbol).tag(drink)
                }
            }
            .labelsHidden()
            .frame(width: 128)
            Stepper(value: Binding(get: { Volume.toDisplay(form.amount, unit) },
                                   set: { form.amount = max(Volume.fromDisplay($0, unit), 10) }),
                    in: 1...5000, step: unit == .milliliters ? 50 : 2) {
                HStack(spacing: 3) {
                TextField("", value: Binding(get: { Volume.toDisplay(form.amount, unit) },
                                             set: { form.amount = max(Volume.fromDisplay($0, unit), 10) }),
                          format: .number.precision(.fractionLength(0...1)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .focused($amountFocused)
                    .onSubmit { add(form.amount, form.drink, pickTime.map { _ in form.date }) }
                Text(unit.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            if pickTime != nil {
                DatePicker("", selection: $form.date, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .frame(width: 80)
            }
            Spacer(minLength: 0)
            Button("Add") { add(form.amount, form.drink, pickTime.map { _ in form.date }) }
                .buttonStyle(.borderedProminent)
                .tint(settings.theme.mid)
        }
        .onAppear {
            form.drink = settings.defaultCup.drink
            if let pickTime { form.date = pickTime }
            if focus { amountFocused = true }
        }
        .onChange(of: pickTime) { _, new in if let new { form.date = new } }
    }
}

struct EntryRow: View {
    var entry: Entry
    var unit: VolumeUnit
    var theme: LiquidTheme
    var onDelete: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.drink.symbol)
                .foregroundStyle(theme.color(for: entry.drink))
                .frame(width: 18)
            Text(Volume.format(entry.amountML, unit))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(entry.drink.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hover.value ? 1 : 0.25)
            .help("Delete this drink")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover.value ? 0.07 : 0)))
        .onHover { hover.value = $0 }
    }
}
