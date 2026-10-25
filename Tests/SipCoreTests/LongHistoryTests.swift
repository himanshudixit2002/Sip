import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)
private let today = DayKey("2026-10-06")!

/// Two years of ten drinks a day, with a few skipped days and some coffee.
private let longHistory: HydrationHistory = {
    var entries: [Entry] = []
    for offset in stride(from: 730, through: 0, by: -1) {
        let day = today.adding(days: -offset)
        if offset % 17 == 5 { continue }
        for i in 0..<10 {
            let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                          hour: 7 + i * 3 / 2, minute: (i * 13) % 60))!
            entries.append(Entry(date: date, amountML: 200 + Double((offset + i) % 4) * 25,
                                 drink: i == 2 && offset % 3 == 0 ? .coffee : .water))
        }
    }
    return HydrationHistory(entries: entries)
}()

@Suite("Long history")
struct LongHistoryTests {
    @Test func everythingCopesWithTwoYearsAndWithNothing() {
        let factors = HydrationFactors()
        for history in [longHistory, HydrationHistory()] {
            let summaries = HistoryMath.summaries(history, clock: clock, factors: factors, fallbackGoal: 2200)
            let repairs = Comeback.repairs(summaries: summaries, today: today)
            let streak = Streaks.compute(metDays: Set(summaries.values.filter(\.met).map(\.key)),
                                         firstDay: summaries.keys.min(), today: today, freezesEnabled: true,
                                         repairs: repairs)
            let xp = XP.total(history: history, summaries: summaries, clock: clock, factors: factors,
                              wakeMinutes: 420, sleepMinutes: 1380, today: today, repairs: repairs)
            let challenges = Challenges.completedDays(history: history, summaries: summaries, clock: clock,
                                                      factors: factors, wakeMinutes: 420, sleepMinutes: 1380)
            let badges = Achievements.evaluate(.init(history: history, summaries: summaries, bestStreak: streak.best,
                                                     clock: clock, bottleML: 750, challengeDays: challenges,
                                                     repairedDays: repairs, level: XP.level(forXP: xp).level))
            let tips = Coach.tips(history: history, summaries: summaries, clock: clock, factors: factors,
                                  wakeMinutes: 420, sleepMinutes: 1380, today: today)
            let recap = Recap.year(2026, history: history, summaries: summaries, clock: clock, bottleML: 750)
            #expect(badges.count == 35)
            if history.entries.isEmpty {
                #expect(xp == 0 && challenges.isEmpty && repairs.isEmpty && tips.isEmpty && recap.daysLogged == 0)
            } else {
                #expect(xp > 0 && !challenges.isEmpty && recap.daysLogged > 200)
                #expect(repairs.count <= 25)
            }
        }
    }
}
