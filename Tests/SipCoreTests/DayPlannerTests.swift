import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()

private func at(_ h: Int, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: h, minute: min))!
}

private let wake = at(7)
private let sleep = at(23)

private func plan(now: Date = at(7), goal: Double = 2500, consumed: Double = 0, busy: [DateInterval] = [],
                  sipML: Double = 250) -> [PlannedSip] {
    DayPlanner.plan(now: now, wake: wake, sleep: sleep, goal: goal, consumed: consumed, busy: busy, sipML: sipML)
}

private func busy(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> DateInterval {
    DateInterval(start: at(h1, m1), end: at(h2, m2))
}

@Suite("Day planner")
struct DayPlannerTests {
    @Test func spreadsTheRemainderThroughTheWindow() {
        let sips = plan()
        #expect(sips.count == 10)
        #expect(sips.reduce(0) { $0 + $1.ml } == 2500)
        #expect(sips.allSatisfy { $0.ml == 250 })
        #expect(sips.first!.date >= at(7, 10))
        #expect(sips.last!.date <= at(22))
        #expect(zip(sips, sips.dropFirst()).allSatisfy { $1.date.timeIntervalSince($0.date) >= 20 * 60 })
        // Every sip lands on a quarter hour.
        #expect(sips.allSatisfy { calendar.component(.minute, from: $0.date) % 15 == 0 })
    }

    @Test func frontLoadsTheMorning() {
        let sips = plan()
        let middle = at(7, 10).addingTimeInterval(at(22).timeIntervalSince(at(7, 10)) / 2)
        let early = sips.filter { $0.date < middle }.count
        #expect(early > sips.count - early)
    }

    @Test func avoidsMeetings() {
        let meetings = [busy(9, 0, 11, 0), busy(14, 0, 15, 30)]
        let sips = plan(busy: meetings)
        #expect(sips.count == 10)
        for sip in sips {
            #expect(!(sip.date > at(8, 55) && sip.date < at(11, 5)))
            #expect(!(sip.date > at(13, 55) && sip.date < at(15, 35)))
        }
    }

    @Test func fewerLargerSipsWhenTimeIsShort() {
        // Free only from 12:00 to 13:00.
        let sips = plan(goal: 2000, busy: [busy(6, 0, 11, 50), busy(13, 10, 23, 0)])
        #expect(sips.map(\.date) == [at(12), at(12, 30), at(13)])
        #expect(sips.map(\.ml) == [670, 670, 660])
    }

    @Test func roundsToTenAndTheLastSipAbsorbsTheRest() {
        let sips = plan(goal: 1010, sipML: 250)
        #expect(sips.map(\.ml) == [200, 200, 200, 200, 210])
    }

    @Test func nothingWhenDoneLateOrBooked() {
        #expect(plan(consumed: 2500).isEmpty)
        #expect(plan(consumed: 3000).isEmpty)
        #expect(plan(now: at(21, 55)).isEmpty)           // window closes at 22:00
        #expect(plan(busy: [busy(0, 0, 23, 59)]).isEmpty)
    }

    @Test func startsAfterWakingEvenIfPlannedEarly() {
        let sips = plan(now: at(5))
        #expect(sips.first!.date >= wake)
    }

    @Test func preMeetingNudges() {
        let events = [busy(10, 0, 11, 0), busy(10, 20, 11, 20), busy(13, 0, 13, 30), busy(15, 0, 16, 0), busy(8, 0, 9, 0)]
        #expect(DayPlanner.preMeetingNudges(events: events, now: at(8, 30)) == [at(9, 50), at(14, 50)])
    }

    @Test func workoutEndsMatchWholeWords() {
        let events: [(DateInterval, String)] = [
            (busy(6, 0, 7, 0), "Morning Run"), (busy(11, 0, 12, 0), "Brunch with Sam"),
            (busy(18, 0, 19, 0), "HIIT class"), (busy(19, 0, 20, 0), "Team sync"),
        ]
        #expect(DayPlanner.workoutEnds(events: events, keywords: WeeklySchedule.defaultWorkoutKeywords) == [at(7), at(19)])
        #expect(DayPlanner.workoutEnds(events: events, keywords: []).isEmpty)
    }
}
