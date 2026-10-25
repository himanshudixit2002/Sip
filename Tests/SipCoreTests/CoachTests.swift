import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func key(_ s: String) -> DayKey { DayKey(s)! }
/// Tuesday 6 October 2026; the coach looks at 8 Sep – 5 Oct.
private let today = key("2026-10-06")

private func at(_ day: DayKey, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: h, minute: min))!
}

/// 28 days of history before today, each built by `make` (day, index 0–27).
private func history(days: Int = 28, _ make: (DayKey, Int) -> [(hour: Int, ml: Double, drink: DrinkKind)]) -> HydrationHistory {
    var entries: [Entry] = []
    for i in 0..<days {
        let day = today.adding(days: -days + i)
        for item in make(day, i) { entries.append(Entry(date: at(day, item.hour), amountML: item.ml, drink: item.drink)) }
    }
    return HydrationHistory(entries: entries)
}

/// 250 ml of water every two hours from 8 AM to 8 PM: 1.75 L, nothing notable.
private func plain(_ day: DayKey, _ i: Int) -> [(hour: Int, ml: Double, drink: DrinkKind)] {
    stride(from: 8, through: 20, by: 2).map { ($0, 250, .water) }
}

private func tips(_ h: HydrationHistory, goal: Double = 2000) -> [CoachTip] {
    let summaries = HistoryMath.summaries(h, clock: clock, factors: HydrationFactors(), fallbackGoal: goal)
    return Coach.tips(history: h, summaries: summaries, clock: clock, factors: HydrationFactors(),
                      wakeMinutes: 7 * 60, sleepMinutes: 23 * 60, today: today)
}

private func ids(_ list: [CoachTip]) -> Set<String> { Set(list.map(\.id)) }

@Suite("Coach")
struct CoachTests {
    @Test func staysQuietWithoutAWeekOfData() {
        let h = history(days: 6) { _, _ in [(18, 3000, .water)] }
        #expect(tips(h).isEmpty)
    }

    @Test func staysQuietWhenNothingStandsOut() {
        #expect(tips(history(plain)).isEmpty)
    }

    @Test func lateHeavy() {
        let h = history { _, _ in [(8, 300, .water), (17, 1200, .water), (20, 800, .water)] }
        let list = tips(h)
        let tip = list.first { $0.id == "lateHeavy" }
        #expect(tip?.detail.hasPrefix("87%") == true)
        // Ranked strongest first.
        #expect(zip(list, list.dropFirst()).allSatisfy { $0.weight >= $1.weight })
    }

    @Test func weekendDip() {
        let h = history { day, i in
            let weekend = day.weekday == 1 || day.weekday == 7
            return weekend ? Array(plain(day, i).prefix(4)) : plain(day, i)
        }
        let tip = tips(h).first { $0.id == "weekendDip" }
        #expect(tip?.detail.hasPrefix("Weekends average 1 L, against 1.75 L") == true)
        #expect(tip?.detail.contains("1.75 L") == true)
    }

    @Test func coffeeDays() {
        let h = history { day, i in
            var list = plain(day, i)
            if i % 2 == 0 { list[1].drink = .coffee; list[2].drink = .coffee }
            return list
        }
        let list = tips(h)
        #expect(list.first { $0.id == "coffeeDays" }?.detail.contains("500 ml less water") == true)
    }

    @Test func morningStart() {
        let h = history { _, i in
            i % 2 == 0 ? [(8, 1000, .water), (12, 1000, .water)] : [(11, 600, .water), (13, 600, .water)]
        }
        let tip = tips(h).first { $0.id == "morningStart" }
        #expect(tip?.detail.contains("100% of days") == true)
        #expect(tip?.detail.contains("and 0% of the others") == true)
    }

    @Test func longGapsAndBigGulps() {
        let gaps = tips(history { _, _ in [(8, 400, .water), (13, 400, .water), (18, 400, .water), (20, 400, .water)] })
        #expect(gaps.first { $0.id == "longGaps" }?.detail.contains("5.0 hours") == true)
        #expect(!ids(gaps).contains("bigGulps"))

        let gulps = tips(history { _, _ in [(8, 600, .water), (10, 600, .water), (12, 600, .water), (14, 600, .water)] })
        #expect(gulps.first { $0.id == "bigGulps" }?.detail.contains("600 ml") == true)
    }

    @Test func consistentGetsAPositiveNote() {
        let h = history { _, _ in stride(from: 8, through: 22, by: 2).map { ($0, 250, .water) } }
        let list = tips(h)
        #expect(ids(list) == ["consistent"])
        #expect(list.first?.detail.contains("28 of the last 28 days") == true)
    }
}

@Suite("Goal suggestion")
struct GoalSuggestionTests {
    private func summaries(_ effective: Double, goal: Double, days: Int = 14) -> [DayKey: DaySummary] {
        var result: [DayKey: DaySummary] = [:]
        for i in 1...days {
            let k = today.adding(days: -i)
            result[k] = DaySummary(key: k, rawML: effective, effectiveML: effective, goalML: goal, entryCount: 4, byDrink: [:])
        }
        return result
    }

    @Test func easyWeeksSuggestAStepUp() {
        let s = Coach.goalSuggestion(summaries: summaries(2400, goal: 2000), today: today, goal: 2000)
        #expect(s?.goalML == 2250)
        #expect(s?.reason.contains("14 of the last 14 days") == true)
    }

    @Test func hardWeeksSuggestASteppingStone() {
        #expect(Coach.goalSuggestion(summaries: summaries(1800, goal: 2500), today: today, goal: 2500)?.goalML == 2000)
        // Never below 1.5 L.
        #expect(Coach.goalSuggestion(summaries: summaries(600, goal: 2500), today: today, goal: 2500)?.goalML == 1500)
    }

    @Test func noSuggestionWhenTheGoalFitsOrDataIsThin() {
        var mixed = summaries(2100, goal: 2000)
        for i in 1...6 { mixed[today.adding(days: -i)]?.effectiveML = 1500 }   // 8 of 14 met
        #expect(Coach.goalSuggestion(summaries: mixed, today: today, goal: 2000) == nil)
        #expect(Coach.goalSuggestion(summaries: summaries(1200, goal: 2500, days: 6), today: today, goal: 2500) == nil)
        // A stepping stone above the current goal isn't a step down.
        #expect(Coach.goalSuggestion(summaries: summaries(1900, goal: 2000), today: today, goal: 2000) == nil)
    }
}
