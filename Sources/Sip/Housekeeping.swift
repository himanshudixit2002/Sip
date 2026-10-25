import AppKit
import SwiftUI
import SipCore

extension AppState {
    /// Once a day (and at launch): a backup, and the monthly recap on the 1st.
    func dailyHousekeeping() {
        guard !DebugHooks.demo || DebugHooks.has("housekeeping") else { return }
        if settings.backupsEnabled {
            let source = store.fileURL, today = store.today
            DispatchQueue.global(qos: .utility).async {
                _ = try? Backups.run(historyURL: source, folder: SipPaths.backupsFolder, today: today)
            }
        }
        offerRecapIfDue()
    }

    /// On the first days of a month, once: "Your September in water".
    private func offerRecapIfDue() {
        guard settings.recapOffer, store.today.day <= 3 else { return }
        let month = "\(store.today.year)-\(store.today.month)"
        guard settings.lastRecapShown != month else { return }
        let recap = Recap.previousMonth(of: store.today, history: store.history, summaries: store.summaries,
                                        clock: store.clock, bottleML: settings.bottleSizeML)
        guard recap.daysLogged >= 5 else { return }
        settings.lastRecapShown = month
        reminders.notify(id: "sip.recap.\(month)", title: "Your \(recap.title) in water",
                         body: "\(Volume.formatCompact(recap.totalML, settings.unit)) over \(recap.daysLogged) days. Tap to see your recap.",
                         route: "recap")
    }

    func openRoute(_ route: String) {
        switch route {
        case "recap": showRecap()
        case "insights": openInsights()
        default: showPopover()
        }
    }

    func showRecap(year: Int? = nil) {
        present(&recapWindow, title: "Your Recap", size: NSSize(width: 620, height: 720), resizable: false) {
            RecapView(state: self, year: year)
        }
    }

    func showWhatsNew() {
        settings.lastSeenVersion = Self.version
        present(&whatsNewWindow, title: "What's New in Sip", size: NSSize(width: 560, height: 640), resizable: false) {
            WhatsNewView(state: self)
        }
    }

    /// The calendar changed: re-plan and reschedule.
    func calendarChanged() {
        applyWorkoutDay()
        recomputeDerived(announce: false)
        rescheduleReminder()
    }

    /// A workout on today's calendar raises today's goal (when that's on).
    func applyWorkoutDay() {
        guard settings.workoutFromCalendar, calendar.hasAccess else {
            store.setWorkoutToday(false)
            return
        }
        let events = calendar.events(from: store.clock.start(of: store.today), to: store.clock.end(of: store.today))
        store.setWorkoutToday(events.contains { settings.weeklySchedule.isWorkout(title: $0.title) })
    }

    /// Takes the coach's goal suggestion.
    func acceptGoalSuggestion() {
        guard let suggestion = derived.goalSuggestion else { return }
        settings.dailyGoalML = suggestion.goalML
        showToast(Toast(icon: "target", text: "Goal set to \(Volume.formatCompact(suggestion.goalML, settings.unit))",
                        tint: settings.theme.surface), duration: 2.5)
    }

    func dismissGoalSuggestion() {
        settings.dismissedGoalSuggestion = Date()
        recomputeDerived(announce: false)
    }
}
