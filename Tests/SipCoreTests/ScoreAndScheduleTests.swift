import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func at(_ h: Int, _ min: Int = 0, day: Int = 6) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: min))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }
private let today = key("2026-10-06")
private let hours = ActiveHours(wakeMinutes: 7 * 60, sleepMinutes: 23 * 60)

private func summary(_ k: DayKey, _ effective: Double, goal: Double = 2000) -> DaySummary {
    DaySummary(key: k, rawML: effective, effectiveML: effective, goalML: goal, entryCount: 3, byDrink: [.water: effective])
}

/// The seven days before today, the first `met` of them met.
private func previousWeek(met: Int) -> [DayKey: DaySummary] {
    var result: [DayKey: DaySummary] = [:]
    for i in 1...7 { result[today.adding(days: -i)] = summary(today.adding(days: -i), i <= met ? 2100 : 900) }
    return result
}

private func score(_ entries: [Entry], limit: Double? = 400, met: Int = 7) -> HydrationScore {
    Score.daily(entries: entries, day: today, goal: 2000, hours: hours, clock: clock, factors: HydrationFactors(),
                rates: CaffeineRates(), caffeineLimitMG: limit, summaries: previousWeek(met: met))
}

@Suite("Score")
struct ScoreTests {
    @Test func aPerfectDayScoresOneHundred() {
        let s = score([8, 12, 16, 20].map { Entry(date: at($0), amountML: 500) })
        #expect(s == HydrationScore(amount: 50, spread: 20, caffeine: 10, consistency: 20))
        #expect(s.total == 100 && s.grade == "Excellent")
    }

    @Test func partsAddUpOnAnOrdinaryDay() {
        // 500 water + 600 coffee (480 effective, 240 mg) all before 11 AM.
        let s = score([Entry(date: at(8), amountML: 500), Entry(date: at(9), amountML: 600, drink: .coffee)], met: 3)
        #expect(s.amount == 24)
        #expect(s.spread == 5)
        #expect(s.caffeine == 8)
        #expect(s.consistency == 9)
        #expect(s.total == 46 && s.grade == "Fair")
    }

    @Test func caffeineScoring() {
        let lots = (0..<5).map { Entry(date: at(8 + $0), amountML: 250, drink: .coffee) }   // 500 mg
        #expect(score(lots).caffeine == 0)
        #expect(score(lots, limit: nil).caffeine == 10)
        #expect(score([Entry(date: at(8), amountML: 250, drink: .coffee)]).caffeine == 10)   // 100 mg
    }

    @Test func grades() {
        #expect(HydrationScore.grade(for: 95) == "Excellent")
        #expect(HydrationScore.grade(for: 75) == "Great")
        #expect(HydrationScore.grade(for: 60) == "Good")
        #expect(HydrationScore.grade(for: 40) == "Fair")
        #expect(HydrationScore.grade(for: 39) == "Low")
        #expect(score([], met: 0).total == 10)
    }
}

@Suite("Weekly schedule")
struct ScheduleTests {
    @Test func weekdayGoalsAndWorkoutBonus() {
        let schedule = WeeklySchedule(goalsByWeekday: [1: 3000], workoutWeekdays: [3])
        #expect(schedule.goal(for: key("2026-10-11"), base: 2500, hasWorkoutEvent: false) == 3000)   // Sunday
        #expect(schedule.goal(for: key("2026-10-06"), base: 2500, hasWorkoutEvent: false) == 3000)   // Tuesday
        #expect(schedule.goal(for: key("2026-10-06"), base: 2500, hasWorkoutEvent: true) == 3000)    // bonus once
        #expect(schedule.goal(for: key("2026-10-07"), base: 2500, hasWorkoutEvent: true) == 3000)
        #expect(schedule.goal(for: key("2026-10-07"), base: 2500, hasWorkoutEvent: false) == 2500)
        #expect(schedule.goal(for: key("2026-10-11"), base: 2500, hasWorkoutEvent: true) == 3500)
        #expect(schedule.isWorkoutDay(key("2026-10-06"), hasWorkoutEvent: false))
        #expect(schedule.isWorkout(title: "Evening Yoga"))
        #expect(!schedule.isWorkout(title: "Brunch"))
    }

    @Test func codableAndTolerantOfMissingFields() throws {
        let schedule = WeeklySchedule(goalsByWeekday: [2: 2800, 7: 2200], workoutWeekdays: [2, 5], workoutBonusML: 750,
                                      workoutKeywords: ["spin class"])
        let data = try JSONEncoder().encode(schedule)
        #expect(try JSONDecoder().decode(WeeklySchedule.self, from: data) == schedule)
        let empty = try JSONDecoder().decode(WeeklySchedule.self, from: Data("{}".utf8))
        #expect(empty == WeeklySchedule())
        #expect(empty.workoutBonusML == 500 && empty.workoutKeywords.contains("hiit"))
        #expect(schedule.isWorkout(title: "Spin class at 7"))
    }
}

@Suite("Shared helpers")
struct SharedHelperTests {
    @Test func weekStatsFillsGapsOldestFirst() {
        var summaries: [DayKey: DaySummary] = [:]
        summaries[today] = summary(today, 2100)
        summaries[today.adding(days: -2)] = summary(today.adding(days: -2), 2500)
        summaries[today.adding(days: -6)] = summary(today.adding(days: -6), 700)
        summaries[today.adding(days: -9)] = summary(today.adding(days: -9), 9000)   // outside the week
        let week = WeekStats(summaries: summaries, last: today, fallbackGoal: 2000)
        #expect(week.days.map(\.key) == (0..<7).reversed().map { today.adding(days: -$0) })
        #expect(week.days[1].entryCount == 0 && week.days[1].goalML == 2000)
        #expect(abs(week.averageML - 5300.0 / 7) < 1e-9)
        #expect(week.totalML == 5300)
        #expect(week.metCount == 2)
        #expect(week.bestDay?.key == today.adding(days: -2))
        let empty = WeekStats(summaries: [:], last: today, count: 3)
        #expect(empty.days.count == 3 && empty.bestDay == nil && empty.averageML == 0)
    }

    @Test func streakDescription() {
        #expect(StreakResult.zero.description == "No streak yet")
        #expect(StreakResult(current: 6, best: 9, freezesBanked: 0, frozenDays: [], todayMet: true).description == "6-day streak")
    }

    @Test func refillLabels() {
        let r = RefillProgress(bottleML: 750, consumedML: 1600, goalML: 3000)
        #expect(r.label == "2 of 4 bottles")
        #expect(r.shortLabel == "2/4")
        #expect(RefillProgress(bottleML: 1000, consumedML: 200, goalML: 800).label == "0 of 1 bottle")
    }

    @Test func weekdaySymbols() {
        #expect(key("2026-10-05").weekdaySymbol(short: true, calendar: calendar) == "M")
        #expect(key("2026-10-05").weekdaySymbol(short: false, calendar: calendar) == "Mon")
        #expect(key("2026-10-11").weekdaySymbol(short: false, calendar: calendar) == "Sun")
    }

    @Test func entriesByRangeAndByDay() {
        let history = HydrationHistory(entries: [
            Entry(date: at(9, day: 5), amountML: 100), Entry(date: at(2, day: 6), amountML: 200),
            Entry(date: at(9, day: 6), amountML: 300), Entry(date: at(23, day: 6), amountML: 400),
            Entry(date: at(9, day: 7), amountML: 500),
        ])
        let range = HistoryMath.entries(from: clock.start(of: today), to: clock.end(of: today), in: history)
        #expect(range.map(\.amountML) == [300, 400])
        #expect(HistoryMath.entries(on: key("2026-10-05"), in: history, clock: clock).map(\.amountML) == [100, 200])
        #expect(HistoryMath.entries(from: at(12), to: at(11), in: history).isEmpty)
        let byDay = HistoryMath.entriesByDay(history.entries.reversed(), clock: clock)
        #expect(byDay[key("2026-10-05")]?.map(\.amountML) == [100, 200])
        #expect(byDay[today]?.map(\.amountML) == [300, 400])
        #expect(byDay.count == 3)
    }
}
