import AppKit
import SwiftUI
import SipCore

/// Numbers worked out from the whole history: level, today's challenge,
/// coach tips, the score, time markers and the day's plan. Recomputed when a
/// drink is logged or a setting they depend on changes, never per frame or
/// per view update.
struct DerivedStats {
    var level = XP.level(forXP: 0)
    var todayXP = 0
    var challenge: ChallengeProgress?
    var completedChallengeDays: Set<DayKey> = []
    var tips: [CoachTip] = []
    var goalSuggestion: GoalSuggestion?
    var score: HydrationScore?
    var timeMarks: [TimeMark] = []
    var plan: [PlannedSip] = []
    var metLast14 = 0
}

/// Why the next reminder is coming.
enum ReminderKind: Equatable {
    case regular
    case planned(ml: Double)
    case meeting(title: String, start: Date)
    case workout
    case lastCall
    case morning
}

extension AppState {
    // MARK: - Derived stats

    func recomputeDerived(announce: Bool) {
        let s = settings
        let clock = store.clock
        let today = store.today
        var d = DerivedStats()
        let before = derived

        var t0 = CFAbsoluteTimeGetCurrent()
        func lap(_ name: String) {
            guard DebugHooks.has("timing") else { return }
            let t = CFAbsoluteTimeGetCurrent()
            print(String(format: "derived %@: %.1f ms", name, (t - t0) * 1000)); fflush(stdout)
            t0 = t
        }
        let xpDays = XP.days(history: store.history, summaries: store.summaries, clock: clock, factors: s.factors,
                             wakeMinutes: s.wakeMinutes, sleepMinutes: s.sleepMinutes, today: today, repairs: store.repairs)
        d.level = XP.level(forXP: xpDays.values.reduce(0) { $0 + $1.total })
        d.todayXP = xpDays[today]?.total ?? 0
        lap("xp")
        d.completedChallengeDays = Challenges.completedDays(history: store.history, summaries: store.summaries, clock: clock,
                                                            factors: s.factors, wakeMinutes: s.wakeMinutes,
                                                            sleepMinutes: s.sleepMinutes)

        lap("completedChallenges")
        if s.challengesEnabled {
            let yesterday = store.summaries[today.previous]?.effectiveML ?? 0
            let challenge = Challenges.challenge(for: today, goal: store.goal, wakeMinutes: s.wakeMinutes,
                                                 sleepMinutes: s.sleepMinutes, yesterdayML: yesterday, unit: s.unit)
            d.challenge = Challenges.progress(challenge, entries: store.todayEntries, day: today, clock: clock,
                                              goal: store.goal, yesterdayML: yesterday, factors: s.factors,
                                              wakeMinutes: s.wakeMinutes, now: Date(), unit: s.unit)
        }
        lap("challenge")
        if s.coachEnabled {
            d.tips = Coach.tips(history: store.history, summaries: store.summaries, clock: clock, factors: s.factors,
                                wakeMinutes: s.wakeMinutes, sleepMinutes: s.sleepMinutes, today: today, unit: s.unit)
            // A dismissed suggestion stays away for two weeks.
            if s.dismissedGoalSuggestion.map({ Date().timeIntervalSince($0) > 14 * 86400 }) ?? true {
                d.goalSuggestion = Coach.goalSuggestion(summaries: store.summaries, today: today, goal: s.dailyGoalML, unit: s.unit)
            }
        }
        lap("coach")
        d.score = Score.daily(entries: store.todayEntries, day: today, goal: store.goal, hours: s.activeHours, clock: clock,
                              factors: s.factors, rates: s.caffeineRates,
                              caffeineLimitMG: s.caffeineTracking ? s.caffeineLimitMG : nil, summaries: store.summaries)
        if s.timeMarkers {
            d.timeMarks = TimeMarkers.marks(wakeMinutes: s.wakeMinutes, sleepMinutes: s.sleepMinutes)
        }
        d.metLast14 = (1...14).filter { store.summaries[today.adding(days: -$0)]?.met == true }.count
        d.plan = makePlan()
        lap("score+plan")
        derived = d

        guard announce, !DebugHooks.demo || DebugHooks.has("announce") else { return }
        if d.level.level > before.level.level, before.level.xp > 0 {
            // A level-up gets its own celebration after the drink's.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self else { return }
                SipEvents.post(SipEvents.celebrate, ["style": CelebrationStyle.rainbow.rawValue])
                self.showToast(Toast(icon: "arrow.up.circle.fill", text: "Level \(d.level.level) · \(d.level.title)",
                                     tint: Palette.gold), duration: 4)
            }
        } else if let now = d.challenge, now.done, before.challenge?.done == false, before.challenge?.challenge == now.challenge {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                SipEvents.post(SipEvents.celebrate, ["style": CelebrationStyle.confetti.rawValue])
                self?.showToast(Toast(icon: now.challenge.symbol, text: "Challenge done · +\(now.challenge.xp) XP",
                                      tint: Palette.badge), duration: 4)
            }
        }
    }

    /// Today's drinks spread over your free time, when the planner is on.
    private func makePlan() -> [PlannedSip] {
        guard settings.calendarPlanner else { return [] }
        let window = store.wakingWindow
        let busy = calendar.events(from: store.clock.start(of: store.today), to: store.clock.end(of: store.today))
            .filter(\.busy).map(\.interval)
        return DayPlanner.plan(now: Date(), wake: window.wake, sleep: window.sleep, goal: store.goal,
                               consumed: store.consumed, busy: busy, sipML: settings.defaultCup.amountML,
                               windDownMinutes: settings.windDown ? settings.windDownMinutes : 0)
    }

    // MARK: - The bottle's life

    /// What lives in the widget's bottle right now. Cheap: comparisons only.
    var bottleLife: BottleLife {
        let s = settings
        var life = BottleLife()
        life.playful = s.playfulWater
        life.pourOut = s.pourOutUndo && !store.todayEntries.isEmpty
        let window = store.wakingWindow
        let night = now < window.wake || now > window.sleep
        if s.companionFish {
            life.fish = Companions.fishCount(streak: store.streak.current)
            life.fishSleeping = night
            if case .behind = store.pace(at: now) { life.fishSluggish = true }
        }
        life.night = s.nightDim && night
        if s.livingGlass, let hour = weather.now(now) {
            let mood = GlassMood.make(temperatureC: hour.temperatureC, humidity: hour.humidity, weatherCode: hour.code)
            life.frost = mood.frost
            life.rain = mood.rain
            life.humid = mood.humid
            life.heat = mood.heat
        }
        if s.seasonalPacks, let season = Seasons.active(on: now, calendar: .current) {
            life.season = season.rawValue
        }
        if s.timeMarkers {
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            life.nextMark = TimeMarkers.nextMark(derived.timeMarks, nowMinutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))?.fraction
        }
        // Debug hooks, for checking each look from a shell:
        // `glass=frost|rain|heat|humid`, `season=diwali|…`, `fish=N`, `night`.
        switch DebugHooks.value("glass") {
        case "frost": life.frost = 1
        case "rain": life.rain = true
        case "heat": life.heat = 1
        case "humid": life.humid = 1
        default: break
        }
        if let season = DebugHooks.value("season") { life.season = season }
        if let fish = DebugHooks.value("fish").flatMap(Int.init) { life.fish = fish }
        if DebugHooks.has("night") { life.night = true; life.fishSleeping = true }
        return life
    }

    var plant: PlantState {
        var behind = false
        if case .behind = store.pace(at: now) { behind = true }
        return Companions.plant(metLast14: derived.metLast14, streak: store.streak.current, behindPace: behind)
    }

    /// Caffeine still in your system, if you track it.
    var caffeineNow: Double? {
        guard settings.caffeineTracking else { return nil }
        let recent = store.history.entries.filter { now.timeIntervalSince($0.date) < 48 * 3600 }
        return CaffeineModel.level(at: now, entries: recent, rates: settings.caffeineRates,
                                   halfLifeHours: settings.caffeineHalfLifeHours)
    }

    /// When caffeine drops below a sleep-friendly 50 mg.
    var caffeineClearTime: Date? {
        guard settings.caffeineTracking, (caffeineNow ?? 0) >= 50 else { return nil }
        let recent = store.history.entries.filter { now.timeIntervalSince($0.date) < 48 * 3600 }
        return CaffeineModel.clearTime(below: 50, after: now, entries: recent, rates: settings.caffeineRates,
                                       halfLifeHours: settings.caffeineHalfLifeHours)
    }

    /// The celebration for reaching today's goal.
    func celebrationStyle(milestone: Bool) -> CelebrationStyle {
        if milestone { return .fireworks }
        if settings.seasonalPacks, Seasons.active(on: Date(), calendar: .current) == .newYear { return .fireworks }
        return settings.celebrationStyle.resolved()
    }

    // MARK: - Reminders

    /// Every reason for a reminder, earliest first: your planned sips (or the
    /// usual interval), meetings, workouts, last call and a morning glass.
    func nextReminder(now: Date) -> (date: Date, kind: ReminderKind)? {
        let s = settings
        guard s.remindersEnabled else { return nil }
        let window = store.wakingWindow
        let windDownStart = s.windDown ? window.sleep.addingTimeInterval(-Double(s.windDownMinutes) * 60) : window.sleep
        var candidates: [(Date, ReminderKind)] = []
        let met = store.consumed >= store.goal - 0.5

        if s.calendarPlanner, !derived.plan.isEmpty {
            if let next = derived.plan.first(where: { $0.date > now.addingTimeInterval(30) }) {
                candidates.append((next.date, .planned(ml: next.ml)))
            }
        } else {
            let config = ReminderConfig(enabled: true, intervalMinutes: s.reminderInterval, smart: s.smartReminders,
                                        hours: s.activeHours, snoozedUntil: s.snoozedUntil, lastReminder: lastReminderShown)
            if let next = ReminderPlanner.nextFire(now: now, lastSip: store.lastSip, consumed: store.consumed,
                                                   goal: store.goal, config: config, clock: store.clock) {
                candidates.append((next, .regular))
            }
        }
        if !met {
            let dayStart = store.clock.start(of: store.today), dayEnd = store.clock.end(of: store.today)
            if s.preMeetingNudges {
                let events = calendar.events(from: dayStart, to: dayEnd).filter(\.busy)
                for date in DayPlanner.preMeetingNudges(events: events.map(\.interval), now: now) {
                    let event = events.first { abs($0.interval.start.timeIntervalSince(date) - 600) < 60 }
                    candidates.append((date, .meeting(title: event?.title ?? "your meeting", start: date.addingTimeInterval(600))))
                }
            }
            if s.workoutFromCalendar {
                let events = calendar.events(from: dayStart, to: dayEnd).map { ($0.interval, $0.title) }
                for end in DayPlanner.workoutEnds(events: events, keywords: s.weeklySchedule.workoutKeywords) {
                    let at = end.addingTimeInterval(15 * 60)
                    if at > now { candidates.append((at, .workout)) }
                }
            }
            if s.lastCall {
                let at = window.sleep.addingTimeInterval(-2.5 * 3600)
                if at > now { candidates.append((at, .lastCall)) }
            }
            if s.morningGlass, store.todayEntries.isEmpty {
                let at = window.wake.addingTimeInterval(3600)
                if at > now { candidates.append((at, .morning)) }
            }
        }
        if let snoozed = s.snoozedUntil, snoozed > now {
            candidates = candidates.map { ($0.0 < snoozed ? snoozed : $0.0, $0.1) }
        }
        // Wind-down: nothing after it except the last call, which comes before.
        return candidates
            .filter { $0.0 > now && ($0.0 <= windDownStart || $0.1 == .lastCall) }
            .min { $0.0 < $1.0 }
    }

    func reminderText(kind: ReminderKind, at date: Date) -> (title: String, body: String) {
        let unit = settings.unit
        let remaining = max(store.goal - store.consumed, 0)
        switch kind {
        case .planned(let ml):
            return ("Time for \(Volume.format(ml, unit))", "Your next planned sip. \(Volume.format(remaining, unit)) to go today.")
        case .meeting(let title, let start):
            return ("Grab some water", "\(title) starts at \(start.formatted(date: .omitted, time: .shortened)).")
        case .workout:
            return ("Rehydrate", "Good workout. A big glass now helps you recover.")
        case .lastCall:
            let glasses = max(Int((remaining / max(settings.defaultCup.amountML, 100)).rounded(.up)), 1)
            return ("Last call", "\(Volume.format(remaining, unit)) to go — about \(glasses) \(settings.defaultCup.name.lowercased())\(glasses == 1 ? "" : "s") before bed.")
        case .morning:
            return ("Good morning", "Start with a glass. Your goal today is \(Volume.formatCompact(store.goal, unit)).")
        case .regular:
            return reminderContent(at: date)
        }
    }

    // MARK: - Status for the command line

    /// `~/Library/Application Support/Sip/status.json`, read by `sip status`.
    /// Written a moment after things settle, and only if the command is installed.
    func writeStatusSoon() {
        guard !DebugHooks.demo || DebugHooks.has("status"), CLIInstaller.isInstalled else { return }
        statusDebounce.schedule(after: 2) { [weak self] in
            guard let self else { return }
            let status = SipStatus(consumedML: self.store.consumed, goalML: self.store.goal, unit: self.settings.unit,
                                   streak: self.store.streak.current, bestStreak: self.store.streak.best,
                                   level: self.derived.level.level, levelTitle: self.derived.level.title,
                                   caffeineNowMG: self.caffeineNow, challengeTitle: self.derived.challenge?.challenge.title,
                                   challengeDone: self.derived.challenge?.done ?? false,
                                   nextReminder: self.reminders.nextFire, updated: Date())
            try? status.write(to: SipPaths.statusFile)
        }
    }
}
