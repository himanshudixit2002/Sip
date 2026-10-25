import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }

private func evaluate(_ entries: [Entry], bestStreak: Int = 0, challengeDays: Set<DayKey> = [],
                      repairedDays: Set<DayKey> = [], plannedFollowDays: Set<DayKey> = [],
                      temperatures: [DayKey: Double] = [:], level: Int = 0) -> [String: AchievementStatus] {
    let history = HydrationHistory(entries: entries)
    let summaries = HistoryMath.summaries(history, clock: clock, factors: HydrationFactors(), fallbackGoal: 2000)
    let list = Achievements.evaluate(.init(history: history, summaries: summaries, bestStreak: bestStreak, clock: clock,
                                           bottleML: 750, maxTemperatureByDay: temperatures,
                                           challengeDays: challengeDays, repairedDays: repairedDays,
                                           plannedFollowDays: plannedFollowDays, level: level))
    return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
}

@Suite("Achievements v2")
struct AchievementV2Tests {
    @Test func thirtyFiveUniqueBadgesWithTheOriginalsFirst() {
        let list = Achievements.evaluate(.init(history: HydrationHistory(), summaries: [:], bestStreak: 0, clock: clock,
                                               bottleML: 750))
        #expect(list.count == 35)
        #expect(Set(list.map(\.id)).count == 35)
        #expect(Set(list.map(\.title)).count == 35)
        let originals = ["first_sip", "goal_getter", "streak_3", "streak_7", "streak_14", "streak_30", "streak_100",
                         "perfect_week", "early_bird", "little_often", "overachiever", "variety", "refills",
                         "litres_100", "litres_500"]
        #expect(Array(list.prefix(15).map(\.id)) == originals)
        #expect(list.allSatisfy { !$0.unlocked })
        #expect(list.first { $0.id == "streak_100" }?.rarity == .legendary)
        #expect(list.first { $0.id == "first_sip" }?.rarity == .common)
        #expect(AchievementRarity.common < .legendary)
    }

    @Test func aBigLateDay() {
        // Goal met at 13:00 (early finisher), 2 L after 8 PM (night owl), 205% (marathon).
        let badges = evaluate([Entry(date: at(10, 6, 8), amountML: 1000), Entry(date: at(10, 6, 13), amountML: 1100),
                               Entry(date: at(10, 6, 21), amountML: 2000)],
                              temperatures: [key("2026-10-06"): 36])
        for id in ["night_owl", "early_finisher", "marathon", "overachiever", "weather_warrior"] {
            #expect(badges[id]?.unlocked == true, "\(id)")
        }
        #expect(badges["night_owl"]?.progressText == "30% / 30%")
        #expect(badges["weather_warrior"]?.rarity == .rare)
    }

    @Test func countsFromTheAppsOwnRecords() {
        let days = Set((0..<10).map { key("2026-09-01").adding(days: $0) })
        let badges = evaluate([Entry(date: at(10, 6, 9), amountML: 250)], bestStreak: 0, challengeDays: days,
                              repairedDays: [key("2026-09-03")], plannedFollowDays: Set(days.prefix(5)), level: 12)
        #expect(badges["challenger_1"]?.unlocked == true)
        #expect(badges["challenger_10"]?.unlocked == true)
        #expect(badges["challenger_50"]?.progressText == "10 / 50")
        #expect(badges["comeback"]?.unlocked == true)
        #expect(badges["planner"]?.unlocked == true)
        #expect(badges["level_10"]?.unlocked == true)
        #expect(badges["level_20"]?.progressText == "12 / 20")
        #expect(badges["weather_warrior"]?.unlocked == false)
    }

    @Test func aPerfectFebruary() {
        // Every day of February 2026: 250 ml of water each hour from 8 AM to 3 PM.
        var entries: [Entry] = []
        for d in 1...28 {
            for h in 8...15 { entries.append(Entry(date: at(2, d, h), amountML: 250)) }
        }
        // Then 5 small teas a day for ten days and 5 sparklings a day for five, never reaching the goal.
        entries += (0..<50).map { Entry(date: at(3, 2 + $0 / 5, 9, $0 % 5), amountML: 100, drink: .tea) }
        entries += (0..<25).map { Entry(date: at(3, 12 + $0 / 5, 9, $0 % 5), amountML: 100, drink: .sparkling) }
        let badges = evaluate(entries, bestStreak: 28)
        for id in ["perfect_month", "steady", "coffee_free_week", "early_bird", "tea_time", "sparkle", "streak_14"] {
            #expect(badges[id]?.unlocked == true, "\(id)")
        }
        // The goal is only reached by the 15:00 drink: not before 3 PM.
        #expect(badges["early_finisher"]?.unlocked == false)
        #expect(badges["weekend_warrior"]?.progressText == "3 / 4")
        #expect(badges["centurion"]?.progressText == "28 / 100")
        #expect(badges["streak_365"]?.unlocked == false)
    }

    @Test func coffeeBreaksTheDecafRun() {
        var entries: [Entry] = []
        for d in 1...10 { entries.append(Entry(date: at(9, d, 9), amountML: 500, drink: d == 5 ? .coffee : .water)) }
        let badges = evaluate(entries)
        #expect(badges["coffee_free_week"]?.progressText == "5 / 7")
    }
}
