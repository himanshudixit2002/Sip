import AppKit
import Observation
import SipCore
import UserNotifications

/// Drink reminders as local notifications. Only one is ever pending: it's
/// re-planned after every drink, settings change and wake, so the next one
/// always reflects where you actually are.
@MainActor
@Observable
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let category = "SIP_REMINDER"
    static let logAction = "SIP_LOG"
    static let snoozeAction = "SIP_SNOOZE"
    private static let requestID = "sip.next"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var nextFire: Date?
    /// Why the due reminder is being held back, if it is.
    private(set) var waitingReason: String?
    private(set) var nextWeekly: Date?

    /// Called when a reminder falls due. The owner checks whether now is a
    /// good moment, then either `deliver`s it or `schedule`s a retry.
    @ObservationIgnored var onDue: (() -> Void)?
    @ObservationIgnored private var dueTimer: Timer?
    /// Called for the notification's "Log" action.
    @ObservationIgnored var onLog: (() -> Void)?
    /// Called for "Snooze".
    @ObservationIgnored var onSnooze: (() -> Void)?
    /// Called when the notification itself is clicked.
    @ObservationIgnored var onOpen: (() -> Void)?
    /// Called when a notification sent with a `route` is clicked (the recap, a buddy).
    @ObservationIgnored var onRoute: ((String) -> Void)?

    /// Notifications need a real bundle; running the bare binary from a shell
    /// would crash in `UNUserNotificationCenter.current()`.
    @ObservationIgnored private let available = Bundle.main.bundleIdentifier != nil
        && Bundle.main.bundlePath.hasSuffix(".app")

    private var center: UNUserNotificationCenter? { available ? .current() : nil }

    func start(logLabel: String) {
        guard let center else { return }
        center.delegate = self
        registerCategory(logLabel: logLabel)
        refreshAuthorization()
        // Earlier versions handed the next reminder to the system in advance.
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    func registerCategory(logLabel: String) {
        let log = UNNotificationAction(identifier: Self.logAction, title: logLabel, options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 15 min", options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [log, snooze],
                                              intentIdentifiers: [], options: [])
        center?.setNotificationCategories([category])
    }

    func refreshAuthorization() {
        center?.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self.authorization = status }
        }
    }

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        guard let center else { return done(false) }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.refreshAuthorization()
                done(granted)
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Sets when the next reminder falls due. Sip times reminders itself rather
    /// than handing them to the system in advance, so that at the moment one
    /// is due it can check whether you're on a call, away or presenting.
    func schedule(at date: Date?, waiting reason: String? = nil) {
        nextFire = date
        waitingReason = reason
        dueTimer?.invalidate()
        dueTimer = nil
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDue?() }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
    }

    /// Shows a reminder now.
    func deliver(title: String, body: String, sound: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.category
        content.threadIdentifier = "sip"
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: "sip.reminder", content: content, trigger: nil))
    }

    /// A one-off notification (the monthly recap, a nudge from a buddy).
    /// Clicking it calls `onRoute` with `route`.
    func notify(id: String, title: String, body: String, route: String?, sound: Bool = true) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "sip.extra"
        if let route { content.userInfo = ["route": route] }
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// The Sunday summary, replaced whenever the numbers change so it's
    /// current when it arrives.
    func scheduleWeekly(at date: Date?, title: String, body: String) {
        nextWeekly = date
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["sip.weekly"])
        guard let date else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "sip.weekly"
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: "sip.weekly", content: content, trigger: trigger))
    }

    func sendTest(title: String, body: String, sound: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.category
        if sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        center.add(UNNotificationRequest(identifier: "sip.test.\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let route = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in
            switch action {
            case Self.logAction: self.onLog?()
            case Self.snoozeAction: self.onSnooze?()
            default:
                if let route { self.onRoute?(route) } else { self.onOpen?() }
            }
            completionHandler()
        }
    }
}

/// Notification wording. Varied, and always built from the real numbers.
enum ReminderCopy {
    static func make(consumed: Double, goal: Double, unit: VolumeUnit, lastSip: Date?, now: Date,
                     expectedFraction: Double, cupLabel: String) -> (title: String, body: String) {
        let percent = goal > 0 ? Int((consumed / goal * 100).rounded()) : 0
        let goalText = Volume.formatCompact(goal, unit)
        if consumed <= 0 {
            return ("Good morning", "Start with a glass — your goal today is \(goalText).")
        }
        let behind = goal * expectedFraction - consumed
        if behind > 0 {
            let options = [
                ("You're \(Volume.format(behind, unit)) behind", "\(cupLabel) now gets you back on pace for \(goalText)."),
                ("Bottle's at \(percent)%", "A drink now keeps today's \(goalText) within reach."),
            ]
            return options.randomElement()!
        }
        if let lastSip {
            let minutes = Int(now.timeIntervalSince(lastSip) / 60)
            let since = minutes >= 90 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
            return ("It's been \(since)", "You're at \(percent)% of \(goalText). Time for a sip.")
        }
        return ("Time for a sip", "You're at \(percent)% of \(goalText).")
    }
}
