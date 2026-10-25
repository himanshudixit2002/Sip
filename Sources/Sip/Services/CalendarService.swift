import EventKit
import Foundation

/// Today's calendar, for the day planner, meeting nudges, workout days and
/// quiet times. It's only read when one of those is switched on, cached, and
/// re-read when the calendar changes or at most every 15 minutes.
@MainActor
final class CalendarService {
    struct Event {
        var interval: DateInterval
        var title: String
        /// Marked busy, not declined, not all-day.
        var busy: Bool
    }

    private let store = EKEventStore()
    private var cache: (day: Date, fetched: Date, events: [Event])?
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    var access: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var hasAccess: Bool { access == .fullAccess }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    /// Starts listening for calendar edits (only once access is granted).
    func startWatching() {
        guard observer == nil, hasAccess else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache = nil
                self?.onChange?()
            }
        }
    }

    /// Timed events between `start` and `end`.
    func events(from start: Date, to end: Date) -> [Event] {
        guard hasAccess else { return [] }
        if let cache, cache.day == start, Date().timeIntervalSince(cache.fetched) < 15 * 60 { return cache.events }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .map { Event(interval: DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)),
                         title: $0.title ?? "", busy: $0.availability != .free) }
            .sorted { $0.interval.start < $1.interval.start }
        cache = (start, Date(), events)
        return events
    }

    /// An event you're busy in is happening now.
    func inMeeting(now: Date = Date(), dayStart: Date, dayEnd: Date) -> Bool {
        events(from: dayStart, to: dayEnd).contains { $0.busy && $0.interval.contains(now) && $0.interval.end > now }
    }
}
