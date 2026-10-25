import Foundation
import Testing
@testable import SipCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: cal)
private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
}
private let cups = [QuickLogCup(name: "Sip", ml: 150, drink: .water),
                    QuickLogCup(name: "Glass", ml: 250, drink: .water),
                    QuickLogCup(name: "Bottle", ml: 500, drink: .water),
                    QuickLogCup(name: "Coffee", ml: 200, drink: .coffee)]

@Suite("Quick log")
struct QuickLogTests {
    func p(_ s: String, _ unit: VolumeUnit = .milliliters) -> ParsedLog? { QuickLogParser.parse(s, cups: cups, unit: unit) }

    @Test func numbersAndUnits() {
        #expect(p("330") == ParsedLog(ml: 330, drink: nil))
        #expect(p("330 tea") == ParsedLog(ml: 330, drink: .tea))
        #expect(p("tea 330") == ParsedLog(ml: 330, drink: .tea))
        #expect(p("1.5l") == ParsedLog(ml: 1500, drink: nil))
        #expect(p("1,5 L water") == ParsedLog(ml: 1500, drink: .water))
        #expect(p("33cl juice") == ParsedLog(ml: 330, drink: .juice))
        #expect(abs((p("12 oz coffee")?.ml ?? 0) - 354.88) < 0.1)
        #expect(abs((p("12", .fluidOunces)?.ml ?? 0) - 354.88) < 0.1)
    }

    @Test func cupsAndCounts() {
        #expect(p("glass") == ParsedLog(ml: 250, drink: .water))
        #expect(p("a glass") == ParsedLog(ml: 250, drink: .water))
        #expect(p("2 glasses") == ParsedLog(ml: 500, drink: .water))
        #expect(p("two bottles") == ParsedLog(ml: 1000, drink: .water))
        #expect(p("half a bottle") == ParsedLog(ml: 250, drink: .water))
        #expect(p("bottle of juice") == ParsedLog(ml: 500, drink: .juice))
        #expect(p("coffee") == ParsedLog(ml: 200, drink: .coffee))
        #expect(p("milk") == ParsedLog(ml: 250, drink: .milk))
    }

    @Test func nonsenseIsRejected() {
        #expect(p("") == nil)
        #expect(p("hello there") == nil)
        #expect(p("99999") == nil)
    }
}

@Suite("Extras")
struct ExtrasTests {
    @Test func caffeineTotalsAndWarnings() {
        let rates = CaffeineRates()
        let morning = Entry(date: at(6, 9), amountML: 240, drink: .coffee)
        #expect(abs(rates.milligrams(morning) - 96) < 0.01)
        #expect(Caffeine.check(entry: morning, todayEntries: [morning], rates: rates,
                               cutoffMinutes: 15 * 60, limitMG: 400, calendar: cal) == .fine)
        let late = Entry(date: at(6, 16), amountML: 200, drink: .tea)
        #expect(Caffeine.check(entry: late, todayEntries: [morning, late], rates: rates,
                               cutoffMinutes: 15 * 60, limitMG: 400, calendar: cal) == .afterCutoff)
        let lots = (0..<5).map { Entry(date: at(6, 10 + $0), amountML: 240, drink: .coffee) }
        if case .overLimit = Caffeine.check(entry: lots[4], todayEntries: lots, rates: rates,
                                            cutoffMinutes: 15 * 60, limitMG: 400, calendar: cal) {} else {
            Issue.record("expected over limit")
        }
        let water = Entry(date: at(6, 22), amountML: 300)
        #expect(Caffeine.check(entry: water, todayEntries: [water], rates: rates,
                               cutoffMinutes: 15 * 60, limitMG: 400, calendar: cal) == .fine)
    }

    @Test func refills() {
        let r = RefillProgress(bottleML: 750, consumedML: 1600, goalML: 3000)
        #expect(r.finished == 2)
        #expect(r.needed == 4)
        #expect(abs(r.current - 100.0 / 750) < 0.001)
    }

    @Test func heatBonus() {
        #expect(HeatAdjustment.bonusML(maxTemperatureC: 22) == 0)
        #expect(HeatAdjustment.bonusML(maxTemperatureC: 27) == 250)
        #expect(HeatAdjustment.bonusML(maxTemperatureC: 33) == 500)
        #expect(HeatAdjustment.bonusML(maxTemperatureC: 41) == 750)
    }

    @Test func weeklySummary() {
        var summaries: [DayKey: DaySummary] = [:]
        let last = DayKey("2026-10-11")!
        for i in 0..<7 {
            let key = last.adding(days: -i)
            summaries[key] = DaySummary(key: key, rawML: 2000 + Double(i) * 100, effectiveML: 2000 + Double(i) * 100,
                                        goalML: 2300, entryCount: 6, byDrink: [:])
        }
        let w = WeeklySummary(summaries: summaries, last: last, streak: 4)
        #expect(w.metDays == 4)
        #expect(w.totalML == 16100)
        #expect(w.best?.key == DayKey("2026-10-05"))
        #expect(w.text(unit: .milliliters).title.contains("4 of 7"))
    }

    @Test func inboxLines() {
        let now = at(6, 12)
        let text = "250\n330 tea\n2026-10-06T08:00:00+05:30,500,juice\nnonsense words\n\n"
        let parsed = Inbox.parse(text, now: now, cups: cups, unit: .milliliters)
        #expect(parsed.entries.count == 3)
        #expect(parsed.skipped == 1)
        #expect(parsed.entries[1].drink == .tea)
        #expect(parsed.entries[2].date == at(6, 8))
    }

    @Test func mergeKeepsDeletions() {
        let a1 = Entry(date: at(6, 9), amountML: 250)
        let a2 = Entry(date: at(6, 10), amountML: 300)
        var mac1 = HydrationHistory(entries: [a1, a2])
        var mac2 = HydrationHistory(entries: [a1, a2])
        mac1.remove(id: a2.id)
        mac2.insert(Entry(date: at(6, 11), amountML: 150))
        let merged = mac1.merged(with: mac2)
        #expect(merged.entries.map(\.amountML) == [250, 150])
        #expect(merged.deletedIDs.contains(a2.id))
    }

    @Test func oldFilesWithoutDeletionsStillLoad() throws {
        let json = #"{"version":1,"entries":[],"dayGoals":{}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let h = try decoder.decode(HydrationHistory.self, from: Data(json.utf8))
        #expect(h.deletedIDs.isEmpty)
    }
}

@Suite("Achievements")
struct AchievementTests {
    @Test func unlocksFromHistory() {
        var entries: [Entry] = []
        // Mon 5 Oct – Sun 11 Oct 2026, goal met every day, first sip at 08:00.
        for d in 5...11 {
            entries.append(Entry(date: at(d, 8), amountML: 1000))
            entries.append(Entry(date: at(d, 13), amountML: 750, drink: .tea))
            entries.append(Entry(date: at(d, 18), amountML: 750, drink: .coffee))
        }
        var history = HydrationHistory(entries: entries)
        for d in 5...11 { history.dayGoals["2026-10-\(String(format: "%02d", d))"] = 2000 }
        let summaries = HistoryMath.summaries(history, clock: clock, factors: HydrationFactors(), fallbackGoal: 2000)
        let list = Achievements.evaluate(.init(history: history, summaries: summaries, bestStreak: 7,
                                               clock: clock, bottleML: 750))
        let unlocked = Set(list.filter(\.unlocked).map(\.id))
        #expect(unlocked.contains("first_sip"))
        #expect(unlocked.contains("streak_7"))
        #expect(unlocked.contains("perfect_week"))
        #expect(!unlocked.contains("early_bird"))
        #expect(!unlocked.contains("streak_14"))
        let early = list.first { $0.id == "early_bird" }!
        #expect(early.progressText == "7 / 10")
    }
}
