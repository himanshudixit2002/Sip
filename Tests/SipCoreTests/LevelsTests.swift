import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }

private func summary(_ effective: Double, goal: Double = 2000) -> DaySummary {
    DaySummary(key: key("2026-10-06"), rawML: effective, effectiveML: effective, goalML: goal, entryCount: 1,
               byDrink: [.water: effective])
}

@Suite("Levels")
struct LevelTests {
    @Test func intakeEarnsOnePointPerTenMillilitres() {
        let xp = XP.forDay(summary(1234), streakDayIndex: 0, effectiveByNoon: 0)
        #expect(xp == DayXP(intake: 123, goal: 0, streak: 0, challenge: 0, early: 0))
        #expect(xp.total == 123)
    }

    @Test func intakeIsCappedAtOneAndAHalfGoals() {
        #expect(XP.forDay(summary(5000, goal: 2000), streakDayIndex: 1, effectiveByNoon: 0).intake == 300)
        #expect(XP.forDay(summary(2999, goal: 2000), streakDayIndex: 1, effectiveByNoon: 0).intake == 299)
    }

    @Test func metDayEarnsEveryBonus() {
        let xp = XP.forDay(summary(2000), streakDayIndex: 4, challengeXP: 60, effectiveByNoon: 500)
        #expect(xp == DayXP(intake: 200, goal: 50, streak: 8, challenge: 60, early: 15))
        #expect(xp.total == 333)
    }

    @Test func streakBonusStopsGrowingAtThirtyDays() {
        #expect(XP.forDay(summary(2000), streakDayIndex: 30, effectiveByNoon: 0).streak == 60)
        #expect(XP.forDay(summary(2000), streakDayIndex: 200, effectiveByNoon: 0).streak == 60)
        // An unmet day gets neither the goal nor the streak bonus.
        let missed = XP.forDay(summary(1000), streakDayIndex: 5, effectiveByNoon: 0)
        #expect(missed.streak == 0 && missed.goal == 0)
    }

    @Test func earlyBonusNeedsAQuarterOfTheGoalByNoon() {
        #expect(XP.forDay(summary(1000), streakDayIndex: 0, effectiveByNoon: 499).early == 0)
        #expect(XP.forDay(summary(1000), streakDayIndex: 0, effectiveByNoon: 500).early == 15)
    }

    @Test func levelThresholds() {
        let start = XP.level(forXP: 0)
        #expect(start.level == 1 && start.title == "Droplet" && start.levelStartXP == 0 && start.nextLevelXP == 1000)
        #expect(XP.level(forXP: 999).level == 1)
        let two = XP.level(forXP: 1000)
        #expect(two.level == 2 && two.title == "Dewdrop" && two.levelStartXP == 1000 && two.nextLevelXP == 2400)
        #expect(abs(XP.level(forXP: 1700).progress - 0.5) < 1e-9)
        #expect(XP.level(forXP: 1700).xpToNextLevel == 700)
        #expect(XP.level(forXP: 23_399).level == 9)
        #expect(XP.level(forXP: 23_400).level == 10)
        #expect(XP.level(forXP: 23_400).title == "Pond")
        let top = XP.level(forXP: 10_000_000)
        #expect(top.level == 30 && top.title == "Poseidon" && top.isMaxLevel && top.progress == 1)
        #expect(XP.level(forXP: -5).xp == 0)
    }

    @Test func thirtyTitlesAndEverLongerLevels() {
        #expect(XP.titles.count == 30)
        #expect(Set(XP.titles).count == 30)
        #expect(XP.titles.first == "Droplet" && XP.titles.last == "Poseidon")
        var previous = 0
        for level in 1..<30 {
            #expect(XP.startXP(of: level + 1) - XP.startXP(of: level) == XP.cost(from: level))
            #expect(XP.cost(from: level) > previous)
            #expect(XP.level(forXP: XP.startXP(of: level + 1)).title == XP.titles[level])
            previous = XP.cost(from: level)
        }
    }

    @Test func aSteadyDrinkerReachesLevelTenInAboutTwoMonths() {
        var total = 0
        for day in 1...60 {
            total += XP.forDay(summary(2500, goal: 2500), streakDayIndex: day, effectiveByNoon: 1000).total
        }
        // Without any challenges this is level 9; with them, level 10.
        #expect((9...11).contains(XP.level(forXP: total).level))
    }

    @Test func totalAddsUpEveryLoggedDay() {
        let history = HydrationHistory(entries: [
            Entry(date: at(2026, 10, 5, 8), amountML: 1000), Entry(date: at(2026, 10, 5, 15), amountML: 1000),
            Entry(date: at(2026, 10, 6, 8), amountML: 1000), Entry(date: at(2026, 10, 6, 15), amountML: 1000),
            Entry(date: at(2026, 10, 7, 9), amountML: 1000),
        ])
        let factors = HydrationFactors()
        let summaries = HistoryMath.summaries(history, clock: clock, factors: factors, fallbackGoal: 2000)
        let days = XP.days(history: history, summaries: summaries, clock: clock, factors: factors,
                           wakeMinutes: 7 * 60, sleepMinutes: 23 * 60, today: key("2026-10-07"))
        #expect(days.count == 3)
        #expect(days[key("2026-10-05")]?.streak == 2)
        #expect(days[key("2026-10-06")]?.streak == 4)
        #expect(days[key("2026-10-07")]?.intake == 100)
        #expect(days[key("2026-10-07")]?.goal == 0)
        #expect(days[key("2026-10-07")]?.early == 15)
        // Each day's challenge XP is either nothing or that day's reward.
        for (day, xp) in days {
            let yesterday = summaries[day.previous]?.effectiveML ?? 0
            let challenge = Challenges.challenge(for: day, goal: 2000, wakeMinutes: 7 * 60, sleepMinutes: 23 * 60,
                                                 yesterdayML: yesterday)
            #expect(xp.challenge == 0 || xp.challenge == challenge.xp)
        }
        let total = XP.total(history: history, summaries: summaries, clock: clock, factors: factors,
                             wakeMinutes: 7 * 60, sleepMinutes: 23 * 60, today: key("2026-10-07"))
        #expect(total == days.values.reduce(0) { $0 + $1.total })
        #expect(XP.total(history: HydrationHistory(), summaries: [:], clock: clock, factors: factors,
                         wakeMinutes: 420, today: key("2026-10-07")) == 0)
    }

    @Test func aRepairedDayKeepsTheStreakBonusGrowing() {
        let history = HydrationHistory(entries: [
            Entry(date: at(2026, 10, 4, 9), amountML: 2000),
            Entry(date: at(2026, 10, 6, 9), amountML: 2000),
        ])
        let factors = HydrationFactors()
        let summaries = HistoryMath.summaries(history, clock: clock, factors: factors, fallbackGoal: 2000)
        let plain = XP.days(history: history, summaries: summaries, clock: clock, factors: factors,
                            wakeMinutes: 420, today: key("2026-10-06"))
        let repaired = XP.days(history: history, summaries: summaries, clock: clock, factors: factors,
                               wakeMinutes: 420, today: key("2026-10-06"), repairs: [key("2026-10-05")])
        #expect(plain[key("2026-10-06")]?.streak == 2)
        #expect(repaired[key("2026-10-06")]?.streak == 6)
    }
}
