import SwiftUI
import SipCore

final class RecapModel: ObservableObject {
    @Published var slide = 0
}

/// "Your September in water": a few big-number slides, then a card to save.
struct RecapView: View {
    let state: AppState
    var year: Int?
    @StateObject private var model = RecapModel()

    private var recap: Recap {
        let store = state.store
        if let year {
            return Recap.year(year, history: store.history, summaries: store.summaries, clock: store.clock,
                              bottleML: state.settings.bottleSizeML)
        }
        // Early in a month, last month; otherwise this month so far.
        return store.today.day <= 7
            ? Recap.previousMonth(of: store.today, history: store.history, summaries: store.summaries,
                                  clock: store.clock, bottleML: state.settings.bottleSizeML)
            : Recap.month(containing: store.today, history: store.history, summaries: store.summaries,
                          clock: store.clock, bottleML: state.settings.bottleSizeML)
    }

    var body: some View {
        let recap = self.recap
        let slides = RecapSlides(recap: recap, state: state)
        VStack(spacing: 0) {
            ZStack {
                ForEach(slides.all.indices, id: \.self) { i in
                    if i == model.slide {
                        slides.all[i]
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.slide)

            HStack {
                HStack(spacing: 6) {
                    ForEach(slides.all.indices, id: \.self) { i in
                        Capsule().fill(i == model.slide ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == model.slide ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: model.slide)
                Spacer()
                if model.slide > 0 {
                    Button("Back") { model.slide -= 1 }
                }
                if model.slide < slides.all.count - 1 {
                    Button("Next") { model.slide += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Save Image…") {
                        ImageExport.save(RecapCard(recap: recap, state: state), name: "Sip \(recap.title).png")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .background(RecapBackground(theme: state.settings.theme))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

private struct RecapBackground: View {
    var theme: LiquidTheme
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.nightTop, theme.deep.opacity(0.9), Palette.night],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.mid.opacity(0.45), .clear], center: .init(x: 0.3, y: 0.3),
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

@MainActor
private struct RecapSlides {
    let recap: Recap
    let state: AppState

    var all: [AnyView] {
        let unit = state.settings.unit
        let theme = state.settings.theme
        var slides: [AnyView] = []
        slides.append(AnyView(BigSlide(eyebrow: recap.title, number: Volume.formatCompact(recap.totalML, unit),
                                       caption: "That's \(bathtubText) — or \(recap.bottles) of your bottles.",
                                       symbol: "drop.fill", theme: theme)))
        slides.append(AnyView(BigSlide(eyebrow: "Goal days", number: "\(recap.daysMet) of \(recap.daysLogged)",
                                       caption: recap.bestRun > 1 ? "Your longest run was \(recap.bestRun) days in a row."
                                                                  : "Every day you log is a step.",
                                       symbol: "checkmark.seal.fill", theme: theme)))
        if let drink = recap.favoriteDrink {
            slides.append(AnyView(BigSlide(eyebrow: "Favourite drink", number: drink.title,
                                           caption: "\(Int((recap.favoriteDrinkShare * 100).rounded()))% of everything you drank.",
                                           symbol: drink.symbol, theme: theme)))
        }
        if let hour = recap.peakHour {
            let label = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())?
                .formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
            slides.append(AnyView(BigSlide(eyebrow: "Your thirstiest hour", number: label,
                                           caption: "More drinks then than any other hour.",
                                           symbol: "clock.fill", theme: theme)))
        }
        if let best = recap.bestDay {
            slides.append(AnyView(BigSlide(eyebrow: "Best day", number: Volume.formatCompact(best.effectiveML, unit),
                                           caption: best.key.date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                                           symbol: "trophy.fill", theme: theme)))
        }
        let level = state.derived.level
        slides.append(AnyView(BigSlide(eyebrow: "Level \(level.level)", number: level.title,
                                       caption: level.isMaxLevel ? "The top. Nothing left but water."
                                                                  : "\(level.xpToNextLevel.formatted()) XP to the next level.",
                                       symbol: "star.circle.fill", theme: theme)))
        slides.append(AnyView(RecapCard(recap: recap, state: state).scaleEffect(0.42).frame(width: 460, height: 560)))
        return slides
    }

    private var bathtubText: String {
        if recap.bathtubs >= 1 {
            let n = recap.bathtubs
            return n >= 10 ? "\(Int(n.rounded())) bathtubs" : String(format: "%.1f bathtubs", n)
        }
        return "\(Int((recap.bathtubs * 100).rounded()))% of a bathtub"
    }
}

private struct BigSlide: View {
    var eyebrow: String
    var number: String
    var caption: String
    var symbol: String
    var theme: LiquidTheme

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(theme.gradient)
                .symbolEffect(.bounce, value: number)
            Text(eyebrow.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.6))
            Text(number)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

/// The saved image: 1080 × 1350, every number on one card.
struct RecapCard: View {
    let recap: Recap
    let state: AppState

    var body: some View {
        let settings = state.settings
        let unit = settings.unit
        let theme = settings.theme
        ZStack {
            RecapBackground(theme: theme)
            VStack(alignment: .leading, spacing: 40) {
                HStack {
                    Image(systemName: "drop.fill").font(.system(size: 44, weight: .bold)).foregroundStyle(theme.gradient)
                    Text("My \(recap.title) in water").font(.system(size: 54, weight: .heavy, design: .rounded))
                }
                HStack(alignment: .center, spacing: 50) {
                    MiniBottle(style: settings.bottleStyle, fraction: min(Double(recap.daysMet) / Double(max(recap.daysLogged, 1)), 1),
                               theme: theme, highlighted: true, custom: settings.customBottle)
                        .frame(width: 240, height: 500)
                    VStack(alignment: .leading, spacing: 28) {
                        stat("Total", Volume.formatCompact(recap.totalML, unit))
                        stat("Goal days", "\(recap.daysMet) of \(recap.daysLogged)")
                        stat("Longest run", "\(recap.bestRun) days")
                        if let drink = recap.favoriteDrink { stat("Favourite", drink.title) }
                        stat("Per day", Volume.formatCompact(recap.averageML, unit))
                    }
                }
                Spacer()
                HStack {
                    Text("Tracked with Sip")
                    Spacer()
                    Text("Level \(state.derived.level.level) · \(state.derived.level.title)")
                }
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            }
            .padding(80)
            .foregroundStyle(.white)
        }
        .frame(width: 1080, height: 1350)
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(2)
                .foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 50, weight: .bold, design: .rounded))
        }
    }
}

extension DayKey {
    /// Noon on this day, for formatting.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}

/// Shown once after an update.
struct WhatsNewView: View {
    let state: AppState

    private let items: [(String, String, String)] = [
        ("fish", "Life in the bottle", "Fish that join as your streak grows, a plant that grows with you, and time markers on the glass."),
        ("waterbottle", "Nine bottles and a designer", "Steel flask, mason jar, gallon jug, lab flask, or shape your own with a label."),
        ("cloud.sun.rain", "Weather on the glass", "Frost on cold days, rain running down, heat haze, and festival touches like Diwali lights."),
        ("trophy", "Levels, challenges and 35 badges", "A daily challenge sized to you, XP for every drink, and a comeback that saves a streak."),
        ("brain.head.profile", "A coach and a day planner", "Tips from your own patterns, goals that adapt, caffeine in your body, and sips planned around your meetings."),
        ("person.2", "Buddies", "Share today's progress with friends through an iCloud folder, and nudge each other."),
        ("waveform", "Siri, Shortcuts and the command line", "“Log water in Sip”, a Focus filter, Spotlight actions, and `sip log 330 tea` in Terminal or Raycast."),
        ("ellipsis.circle", "Easy to reach", "Point at the widget for its ⋯ menu, click the ring in the menu bar, or open Sip from Spotlight for Settings."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("What's New in Sip \(AppState.version)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items, id: \.1) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.0)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(state.settings.theme.gradient)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.1).font(.headline)
                                Text(item.2).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 34)
            }
            HStack {
                Button("Open Settings") { state.openSettings() }
                Spacer()
                Button("Continue") { state.whatsNewWindow?.close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)
        }
    }
}
