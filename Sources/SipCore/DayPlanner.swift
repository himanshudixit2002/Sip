import Foundation

public struct PlannedSip: Equatable, Sendable, Codable {
    public var date: Date
    public var ml: Double

    public init(date: Date, ml: Double) {
        self.date = date
        self.ml = ml
    }
}

/// Spreads what's left of today's goal across free time in the calendar, a
/// little heavier in the morning, never inside a meeting.
public enum DayPlanner {
    public static let slotMinutes = 15
    /// Kept clear either side of a busy block, so a sip isn't planned for the
    /// minute a meeting starts.
    public static let busyMarginMinutes = 5
    /// The plan starts this long from now, giving time to read it.
    public static let startDelayMinutes = 10
    public static let maxSips = 16
    public static let minimumSipML = 50.0

    /// The plan for the rest of the day.
    ///
    /// - The window runs from 10 minutes from now (or wake time, if later) to
    ///   `windDownMinutes` before sleep.
    /// - Candidate times are the quarter hours in the window that aren't within
    ///   5 minutes of a busy block.
    /// - Sips are aimed at evenly spaced points of a density `frontLoad` higher
    ///   at the start of the window than the middle (and as much lower at the
    ///   end), then snapped to the nearest free slot at least
    ///   `minSpacingMinutes` from any other sip.
    /// - Each sip is the remainder over the count, rounded to 10 ml, with the
    ///   last absorbing the rounding. If there aren't enough free slots, there
    ///   are fewer, larger sips.
    public static func plan(now: Date, wake: Date, sleep: Date, goal: Double, consumed: Double, busy: [DateInterval],
                            sipML: Double, windDownMinutes: Int = 60, frontLoad: Double = 0.25,
                            minSpacingMinutes: Int = 20) -> [PlannedSip] {
        let remaining = max(goal - consumed, 0)
        guard remaining >= 1 else { return [] }
        let start = max(now.addingTimeInterval(Double(startDelayMinutes * 60)), wake)
        let end = sleep.addingTimeInterval(-Double(max(windDownMinutes, 0) * 60))
        guard end > start else { return [] }

        let slots = freeSlots(from: start, to: end, busy: busy)
        guard !slots.isEmpty else { return [] }
        let spacing = Double(max(minSpacingMinutes, 0) * 60)
        let size = max(sipML, minimumSipML)
        var count = min(max(Int((remaining / size).rounded(.up)), 1), maxSips)

        while count > 0 {
            let targets = (0..<count).map { i -> Date in
                let x = frontLoadedPosition(quantile: (Double(i) + 0.5) / Double(count), frontLoad: frontLoad)
                return start.addingTimeInterval(x * end.timeIntervalSince(start))
            }
            let placed = place(targets: targets, slots: slots, spacing: spacing)
            if placed.count == count { return amounts(remaining, at: placed.sorted()) }
            if placed.isEmpty { return [] }
            count = placed.count
        }
        return []
    }

    /// Reminders shortly before long meetings: `leadMinutes` before each event
    /// of at least `minDurationMinutes`, only those still ahead, and only the
    /// first of any that fall within 30 minutes of each other.
    public static func preMeetingNudges(events: [DateInterval], now: Date, leadMinutes: Int = 10,
                                        minDurationMinutes: Int = 45) -> [Date] {
        let candidates = events
            .filter { $0.duration >= Double(minDurationMinutes * 60) }
            .map { $0.start.addingTimeInterval(-Double(leadMinutes * 60)) }
            .filter { $0 > now }
            .sorted()
        var result: [Date] = []
        for date in candidates {
            if let last = result.last, date.timeIntervalSince(last) <= 30 * 60 { continue }
            result.append(date)
        }
        return result
    }

    /// When workouts end, for a "time to rehydrate" nudge: events whose title
    /// contains one of `keywords` as a whole word ("Morning run" but not
    /// "Brunch"), case-insensitively. Sorted, without duplicates.
    public static func workoutEnds(events: [(DateInterval, String)], keywords: [String]) -> [Date] {
        let ends = events
            .filter { event in keywords.contains { TextMatch.containsWord(event.1, keyword: $0) } }
            .map { $0.0.end }
        return Array(Set(ends)).sorted()
    }

    // MARK: - Steps

    /// Quarter hours in [start, end] that are clear of every busy block.
    static func freeSlots(from start: Date, to end: Date, busy: [DateInterval]) -> [Date] {
        let step = Double(slotMinutes * 60)
        let margin = Double(busyMarginMinutes * 60)
        // Every time zone in use is offset by a multiple of 15 minutes, so
        // rounding absolute time lands on local quarter hours.
        var slot = Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        var result: [Date] = []
        while slot <= end {
            let blocked = busy.contains { slot > $0.start.addingTimeInterval(-margin) && slot < $0.end.addingTimeInterval(margin) }
            if !blocked { result.append(slot) }
            slot = slot.addingTimeInterval(step)
        }
        return result
    }

    /// Where the `quantile` falls, 0–1 through the window, under a density
    /// that runs from 1 + a at the start to 1 − a at the end.
    static func frontLoadedPosition(quantile q: Double, frontLoad: Double) -> Double {
        let a = min(max(frontLoad, 0), 0.9)
        let q = min(max(q, 0), 1)
        guard a > 1e-9 else { return q }
        // Inverse of F(x) = (1 + a)x − a·x².
        let b = 1 + a
        return min(max((b - (b * b - 4 * a * q).squareRoot()) / (2 * a), 0), 1)
    }

    /// Greedily snaps each target to the nearest unused slot that keeps the
    /// spacing; targets with no such slot are dropped.
    static func place(targets: [Date], slots: [Date], spacing: Double) -> [Date] {
        var placed: [Date] = []
        for target in targets {
            var best: Date?
            for slot in slots where !placed.contains(where: { abs($0.timeIntervalSince(slot)) < max(spacing, 1) }) {
                if let current = best {
                    if abs(slot.timeIntervalSince(target)) < abs(current.timeIntervalSince(target)) { best = slot }
                } else {
                    best = slot
                }
            }
            if let best { placed.append(best) }
        }
        return placed
    }

    static func amounts(_ remaining: Double, at dates: [Date]) -> [PlannedSip] {
        let n = dates.count
        guard n > 0 else { return [] }
        var each = (remaining / Double(n) / 10).rounded() * 10
        // Rounding up many small sips could leave nothing for the last one.
        if each * Double(n - 1) >= remaining { each = (remaining / Double(n) / 10).rounded(.down) * 10 }
        return dates.enumerated().map { i, date in
            PlannedSip(date: date, ml: i == n - 1 ? remaining - each * Double(n - 1) : each)
        }
    }
}

/// Whole-word matching for calendar titles and keywords.
enum TextMatch {
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// True when `keyword`'s words appear together, in order, in `text`.
    static func containsWord(_ text: String, keyword: String) -> Bool {
        let haystack = words(text)
        let needle = words(keyword)
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<(i + needle.count)]) == needle {
            return true
        }
        return false
    }
}
