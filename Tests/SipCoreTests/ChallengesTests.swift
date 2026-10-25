import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

/// A time on 6 October 2026.
private func at(_ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: h, minute: min))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }
private let today = key("2026-10-06")

private func challenge(_ kind: ChallengeKind, target: Double) -> Challenge {
    Challenge(kind: kind, title: "", detail: "", symbol: "", target: target, xp: 50)
}

private func progress(_ c: Challenge, _ entries: [Entry], now: Date, goal: Double = 2000,
                      yesterday: Double = 1500) -> ChallengeProgress {
    Challenges.progress(c, entries: entries, day: today, clock: clock, goal: goal, yesterdayML: yesterday,
                        factors: HydrationFactors(), wakeMinutes: 7 * 60, now: now)
}

/// The first day from 6 October 2026 with a challenge of `kind`.
private func firstDay(_ kind: ChallengeKind) -> DayKey {
    var day = today
    while Challenges.kind(for: day, yesterdayML: 1000) != kind { day = day.next }
    return day
}

@Suite("Challenges")
struct ChallengeTests {
    @Test func theSameDayAlwaysGivesTheSameChallenge() {
        let a = Challenges.challenge(for: today, goal: 2500, wakeMinutes: 420, sleepMinutes: 1380, yesterdayML: 2000)
        let b = Challenges.challenge(for: today, goal: 2500, wakeMinutes: 420, sleepMinutes: 1380, yesterdayML: 2000)
        #expect(a == b)
    }

    @Test func kindsVaryAndNeverRepeatOnConsecutiveDays() {
        for yesterday in [1000.0, 0] {
            var kinds: [ChallengeKind] = []
            var day = key("1999-12-01")
            for _ in 0..<800 {
                kinds.append(Challenges.kind(for: day, yesterdayML: yesterday))
                day = day.next
            }
            #expect(zip(kinds, kinds.dropFirst()).allSatisfy { $0 != $1 })
            if yesterday > 0 {
                #expect(Set(kinds).count == ChallengeKind.allCases.count)
            } else {
                #expect(!kinds.contains(.beatYesterday))
            }
        }
    }

    @Test func numbersComeFromTheGoalAndHours() {
        let morning = Challenges.challenge(for: firstDay(.morningAmount), goal: 2600, wakeMinutes: 420,
                                           sleepMinutes: 1380, yesterdayML: 1000)
        #expect(morning.target == 1050)
        #expect(morning.detail == "Drink 1.05 L before noon.")

        let sips = Challenges.challenge(for: firstDay(.manySips), goal: 2600, wakeMinutes: 420, sleepMinutes: 1380,
                                        yesterdayML: 1000)
        #expect((6...8).contains(Int(sips.target)))

        let clockGoal = Challenges.challenge(for: firstDay(.goalBy), goal: 2600, wakeMinutes: 420, sleepMinutes: 1380,
                                             yesterdayML: 1000)
        #expect(clockGoal.target == 20)
        #expect(clockGoal.detail == "Reach your goal by 8 PM.")
        #expect(clockGoal.xp == 65)

        let early = Challenges.challenge(for: firstDay(.earlyStart), goal: 2600, wakeMinutes: 450, sleepMinutes: 1380,
                                         yesterdayML: 1000)
        #expect(early.detail.hasSuffix("by 8:30 AM."))

        let beat = Challenges.challenge(for: firstDay(.beatYesterday), goal: 2600, wakeMinutes: 420, sleepMinutes: 1380,
                                        yesterdayML: 2100)
        #expect(beat.target == 2100)
        #expect(beat.detail == "Drink more than yesterday's 2.1 L.")
    }

    @Test func goalByHourIsThreeHoursBeforeSleepWithinLimits() {
        #expect(Challenges.goalByHour(wakeMinutes: 420, sleepMinutes: 23 * 60) == 20)
        #expect(Challenges.goalByHour(wakeMinutes: 420, sleepMinutes: 18 * 60) == 17)
        #expect(Challenges.goalByHour(wakeMinutes: 600, sleepMinutes: 60) == 21)   // sleep at 1 AM
    }

    @Test func rewardsStayBetweenFortyAndEighty() {
        var day = today
        for _ in 0..<60 {
            let c = Challenges.challenge(for: day, goal: 2500, wakeMinutes: 420, sleepMinutes: 1380, yesterdayML: 2000)
            #expect((40...80).contains(c.xp))
            #expect(!c.title.isEmpty && !c.detail.isEmpty && !c.symbol.isEmpty)
            day = day.next
        }
    }

    @Test func morningAmountCountsOnlyBeforeNoon() {
        let c = challenge(.morningAmount, target: 800)
        var entries = [Entry(date: at(9), amountML: 500), Entry(date: at(11, 30), amountML: 200, drink: .tea),
                       Entry(date: at(13), amountML: 500)]
        let midMorning = progress(c, entries, now: at(11, 45))
        #expect(abs(midMorning.fraction - 680.0 / 800) < 1e-9)
        #expect(!midMorning.done && !midMorning.failed)
        let afternoon = progress(c, entries, now: at(13, 30))
        #expect(afternoon.failed && afternoon.text.hasPrefix("Missed"))
        entries.append(Entry(date: at(11, 50), amountML: 200))
        let done = progress(c, entries, now: at(13, 30))
        #expect(done.done && done.fraction == 1 && !done.failed)
    }

    @Test func manySipsAndSteadyHoursCount() {
        let sips = challenge(.manySips, target: 7)
        let six = (0..<6).map { Entry(date: at(8 + $0), amountML: 100) }
        #expect(abs(progress(sips, six, now: at(15)).fraction - 6.0 / 7) < 1e-9)
        #expect(progress(sips, six + [Entry(date: at(16), amountML: 100)], now: at(16)).done)

        let hours = challenge(.steadyHours, target: 6)
        let spread = [8, 9, 10, 12, 14, 16].map { Entry(date: at($0), amountML: 100) }
            + [Entry(date: at(9, 30), amountML: 100)]
        #expect(progress(hours, Array(spread.prefix(5)), now: at(15)).text == "5 of 6 hours")
        #expect(progress(hours, spread, now: at(17)).done)
    }

    @Test func goalByNeedsTheGoalBeforeTheDeadline() {
        let c = challenge(.goalBy, target: 20)
        let onTime = [Entry(date: at(9), amountML: 1000), Entry(date: at(19), amountML: 1000)]
        #expect(progress(c, onTime, now: at(19, 30)).done)
        let late = [Entry(date: at(9), amountML: 1000), Entry(date: at(20, 30), amountML: 1000)]
        let p = progress(c, late, now: at(21))
        #expect(!p.done && p.failed && p.fraction == 0.5)
        #expect(!progress(c, [Entry(date: at(9), amountML: 1000)], now: at(15)).failed)
    }

    @Test func noLateCaffeineCompletesOnlyWithTheGoalAndFailsOnALateCup() {
        let c = challenge(.noLateCaffeine, target: 2000)
        var entries = [Entry(date: at(9), amountML: 200, drink: .coffee), Entry(date: at(12), amountML: 1000)]
        let halfway = progress(c, entries, now: at(13))
        #expect(!halfway.done && !halfway.failed)
        entries.append(Entry(date: at(18), amountML: 900))
        #expect(progress(c, entries, now: at(18)).done)   // 160 + 1000 + 900
        entries.append(Entry(date: at(15), amountML: 200, drink: .tea))
        let failed = progress(c, entries, now: at(19))
        #expect(!failed.done && failed.failed && failed.fraction == 1)
        #expect(failed.text.contains("after 2 PM"))
    }

    @Test func waterOnlyFailsOnAnyOtherDrink() {
        let c = challenge(.waterOnly, target: 1200)
        let water = [Entry(date: at(9), amountML: 700), Entry(date: at(12), amountML: 600, drink: .sparkling)]
        #expect(progress(c, water, now: at(13)).done)
        let juice = water + [Entry(date: at(14), amountML: 200, drink: .juice)]
        let p = progress(c, juice, now: at(14))
        #expect(!p.done && p.failed)
    }

    @Test func beatYesterdayNeedsMore() {
        let c = challenge(.beatYesterday, target: 1500)
        let some = progress(c, [Entry(date: at(9), amountML: 1400)], now: at(12))
        #expect(!some.done && abs(some.fraction - 1400.0 / 1500) < 1e-9)
        #expect(progress(c, [Entry(date: at(9), amountML: 1600)], now: at(12)).done)
    }

    @Test func earlyStartWantsADrinkWithinAnHourOfWaking() {
        let c = challenge(.earlyStart, target: 60)
        #expect(progress(c, [Entry(date: at(7, 45), amountML: 200)], now: at(9)).done)
        #expect(progress(c, [Entry(date: at(8, 30), amountML: 200)], now: at(9)).failed)
        let waiting = progress(c, [], now: at(7, 30))
        #expect(!waiting.done && !waiting.failed)
        #expect(progress(c, [], now: at(8, 30)).failed)
    }

    @Test func completedDaysMatchesProgress() {
        let history = HydrationHistory(entries: (0..<10).map { Entry(date: at(6 + $0), amountML: 400) })
        let summaries = HistoryMath.summaries(history, clock: clock, factors: HydrationFactors(), fallbackGoal: 2000)
        let days = Challenges.completedDays(history: history, summaries: summaries, clock: clock,
                                            factors: HydrationFactors(), wakeMinutes: 420, sleepMinutes: 1380)
        let c = Challenges.challenge(for: today, goal: 2000, wakeMinutes: 420, sleepMinutes: 1380, yesterdayML: 0)
        let p = Challenges.progress(c, entries: history.entries, day: today, clock: clock, goal: 2000, yesterdayML: 0,
                                    factors: HydrationFactors(), wakeMinutes: 420, now: clock.end(of: today))
        #expect(days.contains(today) == p.done)
    }
}

@Suite("Comeback")
struct ComebackTests {
    private func s(_ k: String, _ effective: Double, goal: Double = 2000) -> (DayKey, DaySummary) {
        (key(k), DaySummary(key: key(k), rawML: effective, effectiveML: effective, goalML: goal, entryCount: 1, byDrink: [:]))
    }

    private func summaries(_ list: [(DayKey, DaySummary)]) -> [DayKey: DaySummary] {
        Dictionary(uniqueKeysWithValues: list)
    }

    @Test func aBigNextDayRepairsAMiss() {
        let all = summaries([s("2026-09-01", 2000), s("2026-09-02", 1000), s("2026-09-03", 2200)])
        #expect(Comeback.repairs(summaries: all, today: key("2026-09-10")) == [key("2026-09-02")])
    }

    @Test func notQuiteEnoughDoesNotRepair() {
        let all = summaries([s("2026-09-01", 2000), s("2026-09-02", 1000), s("2026-09-03", 2100)])
        #expect(Comeback.repairs(summaries: all, today: key("2026-09-10")).isEmpty)
    }

    @Test func oneRepairPerCalendarMonth() {
        let all = summaries([
            s("2026-09-01", 2000), s("2026-09-02", 1000), s("2026-09-03", 2200),
            s("2026-09-05", 1000), s("2026-09-06", 2300),
            s("2026-10-01", 1000), s("2026-10-02", 2200),
        ])
        #expect(Comeback.repairs(summaries: all, today: key("2026-10-06")) == [key("2026-09-02"), key("2026-10-01")])
    }

    @Test func aDayWithNothingLoggedCanBeRepairedAndTodayRepairsYesterday() {
        let gap = summaries([s("2026-10-03", 2000), s("2026-10-05", 2300)])
        #expect(Comeback.repairs(summaries: gap, today: key("2026-10-06")) == [key("2026-10-04")])
        let yesterday = summaries([s("2026-10-04", 2000), s("2026-10-05", 800), s("2026-10-06", 2250)])
        #expect(Comeback.repairs(summaries: yesterday, today: key("2026-10-06")) == [key("2026-10-05")])
        // Today itself is never repaired, even if it's behind.
        let unfinished = summaries([s("2026-10-05", 2000), s("2026-10-06", 100)])
        #expect(Comeback.repairs(summaries: unfinished, today: key("2026-10-06")).isEmpty)
    }

    @Test func repairsKeepTheStreakAlive() {
        var met = Set((0..<5).map { key("2026-09-25").adding(days: $0) })   // 25th–29th
        met.formUnion((0..<5).map { key("2026-10-01").adding(days: $0) })  // 1st–5th, missed the 30th
        let plain = Streaks.compute(metDays: met, firstDay: key("2026-09-25"), today: key("2026-10-06"),
                                    freezesEnabled: false)
        let repaired = Streaks.compute(metDays: met, firstDay: key("2026-09-25"), today: key("2026-10-06"),
                                       freezesEnabled: false, repairs: [key("2026-09-30")])
        #expect(plain.current == 5)
        #expect(repaired.current == 11)
        #expect(repaired.best == 11)
    }
}
