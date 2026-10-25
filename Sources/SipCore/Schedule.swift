import Foundation

/// Goals that follow the week: a different goal on given weekdays, and extra
/// water on workout days.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public static let defaultWorkoutKeywords = [
        "gym", "workout", "run", "running", "yoga", "cycling", "swim", "football", "cricket", "badminton",
        "tennis", "hiit", "pilates",
    ]

    /// 1 = Sunday … 7 = Saturday. A missing weekday uses the base goal.
    public var goalsByWeekday: [Int: Double]
    /// Weekdays (1–7) that always get the workout bonus.
    public var workoutWeekdays: Set<Int>
    public var workoutBonusML: Double
    /// Calendar event titles containing one of these words count as workouts.
    public var workoutKeywords: [String]

    public init(goalsByWeekday: [Int: Double] = [:], workoutWeekdays: Set<Int> = [], workoutBonusML: Double = 500,
                workoutKeywords: [String] = WeeklySchedule.defaultWorkoutKeywords) {
        self.goalsByWeekday = goalsByWeekday
        self.workoutWeekdays = workoutWeekdays
        self.workoutBonusML = workoutBonusML
        self.workoutKeywords = workoutKeywords
    }

    private enum CodingKeys: String, CodingKey { case goalsByWeekday, workoutWeekdays, workoutBonusML, workoutKeywords }

    // Every field is optional on disk, so settings saved before a field
    // existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalsByWeekday = try c.decodeIfPresent([Int: Double].self, forKey: .goalsByWeekday) ?? [:]
        workoutWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workoutWeekdays) ?? []
        workoutBonusML = try c.decodeIfPresent(Double.self, forKey: .workoutBonusML) ?? 500
        workoutKeywords = try c.decodeIfPresent([String].self, forKey: .workoutKeywords)
            ?? WeeklySchedule.defaultWorkoutKeywords
    }

    /// Whether `day` gets the workout bonus: a workout weekday, or a workout
    /// in the calendar.
    public func isWorkoutDay(_ day: DayKey, hasWorkoutEvent: Bool) -> Bool {
        hasWorkoutEvent || workoutWeekdays.contains(day.weekday)
    }

    /// The goal for `day`: that weekday's own goal (else `base`), plus the
    /// workout bonus once, whether it's a workout weekday, a calendar workout,
    /// or both.
    public func goal(for day: DayKey, base: Double, hasWorkoutEvent: Bool = false) -> Double {
        let goal = goalsByWeekday[day.weekday] ?? base
        return goal + (isWorkoutDay(day, hasWorkoutEvent: hasWorkoutEvent) ? max(workoutBonusML, 0) : 0)
    }

    /// Whether a calendar event title looks like a workout.
    public func isWorkout(title: String) -> Bool {
        workoutKeywords.contains { TextMatch.containsWord(title, keyword: $0) }
    }
}
