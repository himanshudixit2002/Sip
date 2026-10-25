import Foundation
import Testing
@testable import SipCore

private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
}

private let calendar = makeCalendar()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }

@Suite("Days")
struct DayTests {
    @Test func earlyHoursBelongToThePreviousDay() {
        #expect(clock.key(for: at(2026, 10, 6, 1, 30)) == key("2026-10-05"))
        #expect(clock.key(for: at(2026, 10, 6, 3, 59)) == key("2026-10-05"))
        #expect(clock.key(for: at(2026, 10, 6, 4, 0)) == key("2026-10-06"))
        #expect(clock.key(for: at(2026, 10, 6, 23, 59)) == key("2026-10-06"))
    }

    @Test func boundariesFollowTheDayStartHour() {
        #expect(clock.start(of: key("2026-10-06")) == at(2026, 10, 6, 4))
        #expect(clock.nextBoundary(after: at(2026, 10, 6, 2)) == at(2026, 10, 6, 4))
        #expect(clock.nextBoundary(after: at(2026, 10, 6, 9)) == at(2026, 10, 7, 4))
    }

    @Test func keyArithmeticCrossesMonthsAndYears() {
        #expect(key("2026-12-31").next == key("2027-01-01"))
        #expect(key("2028-03-01").previous == key("2028-02-29"))
        #expect(key("2026-10-01").days(to: key("2026-10-31")) == 30)
    }

    @Test func midnightClockStillWorks() {
        let midnight = DayClock(dayStartHour: 0, calendar: calendar)
        #expect(midnight.key(for: at(2026, 10, 6, 0, 10)) == key("2026-10-06"))
    }
}

@Suite("Units")
struct UnitTests {
    @Test func ouncesRoundTrip() {
        let ml = Volume.fromDisplay(16, .fluidOunces)
        #expect(abs(ml - 473.176) < 0.01)
        #expect(Volume.displayNumber(ml, .fluidOunces) == 16)
    }

    @Test func formatting() {
        #expect(Volume.format(1250, .milliliters) == "1,250 ml")
        #expect(Volume.formatCompact(1250, .milliliters) == "1.25 L")
        #expect(Volume.formatCompact(750, .milliliters) == "750 ml")
        #expect(Volume.tickLabel(1500, .milliliters) == "1.5L")
        #expect(Volume.tickLabel(2000, .milliliters) == "2L")
        #expect(Volume.tickLabel(500, .milliliters) == "500")
    }

    @Test func snapping() {
        #expect(Volume.snap(324, .milliliters) == 320)
        #expect(Volume.displayNumber(Volume.snap(300, .fluidOunces), .fluidOunces) == 10)
    }
}

@Suite("History")
struct HistoryTests {
    @Test func hydrationFactorsWeightEffectiveIntake() {
        let history = HydrationHistory(entries: [
            Entry(date: at(2026, 10, 6, 9), amountML: 500, drink: .water),
            Entry(date: at(2026, 10, 6, 10), amountML: 200, drink: .coffee),
        ])
        var factors = HydrationFactors()
        let s = HistoryMath.summaries(history, clock: clock, factors: factors, fallbackGoal: 2000)[key("2026-10-06")]!
        #expect(s.rawML == 700)
        #expect(s.effectiveML == 660)
        factors[.coffee] = 0.5
        let t = HistoryMath.summaries(history, clock: clock, factors: factors, fallbackGoal: 2000)[key("2026-10-06")]!
        #expect(t.effectiveML == 600)
    }

    @Test func eachDayKeepsItsOwnGoal() {
        var history = HydrationHistory(entries: [
            Entry(date: at(2026, 10, 4, 9), amountML: 2000),
            Entry(date: at(2026, 10, 5, 9), amountML: 2000),
            Entry(date: at(2026, 10, 6, 9), amountML: 2000),
        ])
        history.dayGoals["2026-10-04"] = 2000
        history.dayGoals["2026-10-06"] = 3000
        let s = HistoryMath.summaries(history, clock: clock, factors: HydrationFactors(), fallbackGoal: 2500)
        #expect(s[key("2026-10-04")]!.met)
        // No goal recorded on the 5th: inherits the 4th's, not today's.
        #expect(s[key("2026-10-05")]!.goalML == 2000)
        #expect(s[key("2026-10-05")]!.met)
        #expect(!s[key("2026-10-06")]!.met)
    }

    @Test func insertKeepsEntriesSorted() {
        var history = HydrationHistory()
        history.insert(Entry(date: at(2026, 10, 6, 12), amountML: 100))
        history.insert(Entry(date: at(2026, 10, 6, 8), amountML: 200))
        history.insert(Entry(date: at(2026, 10, 6, 10), amountML: 300))
        #expect(history.entries.map(\.amountML) == [200, 300, 100])
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sip-test-\(UUID().uuidString)/history.json")
        var history = HydrationHistory(entries: [Entry(date: at(2026, 10, 6, 9), amountML: 250, drink: .tea)])
        history.dayGoals["2026-10-06"] = 2400
        try HistoryFile.save(history, to: url)
        let loaded = try HistoryFile.load(from: url)
        #expect(loaded.entries.count == 1)
        #expect(loaded.entries[0].drink == .tea)
        #expect(loaded.dayGoals["2026-10-06"] == 2400)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func csvRoundTrip() {
        let history = HydrationHistory(entries: [
            Entry(date: at(2026, 10, 6, 9), amountML: 250, drink: .water),
            Entry(date: at(2026, 10, 6, 11), amountML: 180, drink: .coffee),
        ])
        let parsed = HistoryCSV.parse(HistoryCSV.export(history) + "garbage,row\n")
        #expect(parsed.entries.count == 2)
        #expect(parsed.skipped == 1)
        #expect(parsed.entries[1].drink == .coffee)
    }
}

@Suite("Streaks")
struct StreakTests {
    private func days(_ start: String, count: Int) -> [DayKey] {
        (0..<count).map { key(start).adding(days: $0) }
    }

    @Test func unfinishedTodayDoesNotBreakTheStreak() {
        let met = Set(days("2026-10-01", count: 5))   // 1st–5th
        let r = Streaks.compute(metDays: met, firstDay: key("2026-10-01"), today: key("2026-10-06"), freezesEnabled: false)
        #expect(r.current == 5)
        #expect(!r.todayMet)
    }

    @Test func meetingTodayExtendsTheStreak() {
        let met = Set(days("2026-10-01", count: 6))   // includes today, the 6th
        let r = Streaks.compute(metDays: met, firstDay: key("2026-10-01"), today: key("2026-10-06"), freezesEnabled: false)
        #expect(r.current == 6)
        #expect(r.best == 6)
        #expect(r.todayMet)
    }

    @Test func aMissedDayResetsWithoutFreezes() {
        var met = Set(days("2026-09-20", count: 10))   // 20th–29th
        met.formUnion(days("2026-10-01", count: 5))    // 1st–5th, missed the 30th
        let r = Streaks.compute(metDays: met, firstDay: key("2026-09-20"), today: key("2026-10-06"), freezesEnabled: false)
        #expect(r.current == 5)
        #expect(r.best == 10)
    }

    @Test func freezesAreEarnedAndSpent() {
        var met = Set(days("2026-09-20", count: 10))   // earns one freeze at day 7
        met.formUnion(days("2026-10-01", count: 5))
        let r = Streaks.compute(metDays: met, firstDay: key("2026-09-20"), today: key("2026-10-06"), freezesEnabled: true)
        #expect(r.frozenDays == [key("2026-09-30")])
        #expect(r.current == 15)
        // Earned at 7 and 14, one spent on the 30th.
        #expect(r.freezesBanked == 1)
    }

    @Test func freezesDoNotCoverTwoMissesWithOnlyOneBanked() {
        var met = Set(days("2026-09-20", count: 7))    // 20th–26th, one freeze
        met.formUnion(days("2026-09-29", count: 3))    // missed 27th and 28th
        let r = Streaks.compute(metDays: met, firstDay: key("2026-09-20"), today: key("2026-10-02"), freezesEnabled: true)
        #expect(r.frozenDays == [key("2026-09-27")])
        #expect(r.current == 3)
        #expect(r.best == 7)
    }

    @Test func freezeBankIsCapped() {
        let met = Set(days("2026-08-01", count: 40))
        let r = Streaks.compute(metDays: met, firstDay: key("2026-08-01"), today: key("2026-09-10"), freezesEnabled: true)
        #expect(r.freezesBanked == Streaks.maxFreezes)
    }

    @Test func milestones() {
        let r = StreakResult(current: 8, best: 8, freezesBanked: 0, frozenDays: [], todayMet: true)
        #expect(r.milestone == 7)
        #expect(r.nextMilestone == 14)
    }

    @Test func firstDayIsToday() {
        let r = Streaks.compute(metDays: [key("2026-10-06")], firstDay: key("2026-10-06"), today: key("2026-10-06"), freezesEnabled: true)
        #expect(r.current == 1)
    }
}

@Suite("Pace")
struct PaceTests {
    let hours = ActiveHours(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)   // 14 waking hours
    let today = DayKey("2026-10-06")!

    @Test func expectedFractionIsLinearAcrossWakingHours() {
        #expect(Pace.expectedFraction(at: at(2026, 10, 6, 7), on: today, hours: hours, clock: clock) == 0)
        #expect(Pace.expectedFraction(at: at(2026, 10, 6, 15), on: today, hours: hours, clock: clock) == 0.5)
        #expect(Pace.expectedFraction(at: at(2026, 10, 6, 23), on: today, hours: hours, clock: clock) == 1)
    }

    @Test func statusBands() {
        #expect(Pace.status(consumed: 1000, goal: 2000, expectedFraction: 0.5) == .onTrack)
        #expect(Pace.status(consumed: 600, goal: 2000, expectedFraction: 0.5) == .behind(ml: 400))
        #expect(Pace.status(consumed: 1500, goal: 2000, expectedFraction: 0.5) == .ahead(ml: 500))
        #expect(Pace.status(consumed: 2000, goal: 2000, expectedFraction: 0.2) == .goalMet)
        #expect(Pace.status(consumed: 0, goal: 2000, expectedFraction: 0) == .notStarted)
    }

    @Test func sleepAfterMidnightWraps() {
        let late = ActiveHours(wakeMinutes: 10 * 60, sleepMinutes: 2 * 60)
        let w = late.window(on: today, clock: clock)
        #expect(w.wake == at(2026, 10, 6, 10))
        #expect(w.sleep == at(2026, 10, 7, 2))
    }
}

@Suite("Reminders")
struct ReminderTests {
    let hours = ActiveHours(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    @Test func plainIntervalAfterLastSip() {
        let config = ReminderConfig(intervalMinutes: 60, smart: false, hours: hours)
        let next = ReminderPlanner.nextFire(now: at(2026, 10, 6, 10), lastSip: at(2026, 10, 6, 9, 50),
                                            consumed: 500, goal: 2800, config: config, clock: clock)
        #expect(next == at(2026, 10, 6, 10, 50))
    }

    @Test func smartWaitsUntilYouWouldFallBehind() {
        // 1400 of 2800 by 10:00 is well ahead; tolerance is 140 ml, so you'd
        // only be behind when the line reaches 1540 ml: 55% of 14 h = 15:42.
        let config = ReminderConfig(intervalMinutes: 60, smart: true, hours: hours)
        let next = ReminderPlanner.nextFire(now: at(2026, 10, 6, 10), lastSip: at(2026, 10, 6, 9, 50),
                                            consumed: 1400, goal: 2800, config: config, clock: clock)!
        #expect(abs(next.timeIntervalSince(at(2026, 10, 6, 15, 42))) < 1)
    }

    @Test func smartSkipsToTomorrowOnceTheGoalIsMet() {
        let config = ReminderConfig(intervalMinutes: 60, smart: true, hours: hours)
        let next = ReminderPlanner.nextFire(now: at(2026, 10, 6, 16), lastSip: at(2026, 10, 6, 15),
                                            consumed: 2800, goal: 2800, config: config, clock: clock)
        #expect(next == at(2026, 10, 7, 8, 15))
    }

    @Test func remindersStayInsideWakingHours() {
        let config = ReminderConfig(intervalMinutes: 90, smart: false, hours: hours)
        let late = ReminderPlanner.nextFire(now: at(2026, 10, 6, 21), lastSip: at(2026, 10, 6, 21),
                                            consumed: 1000, goal: 2800, config: config, clock: clock)
        #expect(late == at(2026, 10, 7, 8, 15))
        let early = ReminderPlanner.nextFire(now: at(2026, 10, 6, 5), lastSip: nil,
                                             consumed: 0, goal: 2800, config: config, clock: clock)
        #expect(early == at(2026, 10, 6, 9, 30))
    }

    @Test func snoozePushesTheReminderBack() {
        let config = ReminderConfig(intervalMinutes: 30, smart: false, hours: hours,
                                    snoozedUntil: at(2026, 10, 6, 11, 15))
        let next = ReminderPlanner.nextFire(now: at(2026, 10, 6, 10), lastSip: at(2026, 10, 6, 10),
                                            consumed: 500, goal: 2800, config: config, clock: clock)
        #expect(next == at(2026, 10, 6, 11, 15))
    }

    @Test func aShownReminderRestartsTheInterval() {
        // Last drink at 09:00, a reminder was shown at 10:00 and ignored:
        // the next comes at 11:00, not straight away.
        let config = ReminderConfig(intervalMinutes: 60, smart: false, hours: hours,
                                    lastReminder: at(2026, 10, 6, 10))
        let next = ReminderPlanner.nextFire(now: at(2026, 10, 6, 10, 0), lastSip: at(2026, 10, 6, 9),
                                            consumed: 500, goal: 2800, config: config, clock: clock)
        #expect(next == at(2026, 10, 6, 11))
    }

    @Test func disabledMeansNoReminder() {
        let config = ReminderConfig(enabled: false, hours: hours)
        #expect(ReminderPlanner.nextFire(now: at(2026, 10, 6, 10), lastSip: nil, consumed: 0, goal: 2000,
                                         config: config, clock: clock) == nil)
    }
}
