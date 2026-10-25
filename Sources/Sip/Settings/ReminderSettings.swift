import AppKit
import SwiftUI
import SipCore

// MARK: - Reminders

struct ReminderSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore
    let reminders: Reminders

    var body: some View {
        Form {
            Section {
                RemindersToggle(state: state, settings: settings)
                authorizationRow
            }
            Section {
                ReminderIntervalPicker(settings: settings)
                Toggle(isOn: $settings.smartReminders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart timing")
                        Text("Wait until you'd actually fall behind your even pace, stop once the goal is met, and restart the timer whenever you drink.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Play a sound", isOn: $settings.reminderSound)
                LabeledContent("Next reminder") {
                    Text(nextText).foregroundStyle(.secondary)
                }
            } header: {
                Text("Timing")
            } footer: {
                FooterText("Reminders only arrive between your wake-up time and bedtime (Goal → Your day). Each one has Log and Snooze buttons.")
            }
            .disabled(!settings.remindersEnabled)

            Section {
                Toggle(isOn: $settings.windDown) {
                    HStack {
                        Text("Wind down before bed")
                        Spacer()
                        Picker("", selection: $settings.windDownMinutes) {
                            ForEach([30, 60, 90, 120], id: \.self) { Text(ReminderIntervalPicker.label($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        .disabled(!settings.windDown)
                    }
                }
                DetailToggle("Last call", detail: "Two and a half hours before bed, if you're behind: what's left, in glasses.",
                             isOn: $settings.lastCall)
                DetailToggle("Morning glass", detail: "An hour after you wake, if you haven't had anything yet.",
                             isOn: $settings.morningGlass)
            } header: {
                Text("Morning and evening")
            } footer: {
                FooterText("Winding down stops reminders that long before bedtime, so you're not up at night.")
            }
            .disabled(!settings.remindersEnabled)

            Section {
                calendarToggle("Plan my sips around meetings", detail: "Spreads what's left of today into the free gaps in your calendar, more in the morning. Reminders come at those times.",
                               isOn: $settings.calendarPlanner)
                calendarToggle("A heads-up before long meetings", detail: "Ten minutes before a meeting of 45 minutes or more: grab some water.",
                               isOn: $settings.preMeetingNudges)
                calendarToggle("Workouts on my calendar", detail: "A rehydrate reminder 15 minutes after an event like “Gym” or “Run”, and the workout bonus on your goal (Goal → Weekly schedule).",
                               isOn: $settings.workoutFromCalendar)
                if settings.calendarPlanner, !state.derived.plan.isEmpty {
                    LabeledContent("Today's plan") {
                        Text(state.derived.plan.prefix(8).map { $0.date.formatted(date: .omitted, time: .shortened) }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                FooterText("Sip reads today's events on this Mac to find free time, meetings and workouts. Nothing is stored or sent anywhere.")
            }
            .disabled(!settings.remindersEnabled)

            Section {
                Toggle("On calls (when the microphone is in use)", isOn: $settings.quietInCalls)
                Toggle("In calendar meetings", isOn: Binding(get: { settings.quietInMeetings }, set: { on in
                    settings.quietInMeetings = on
                    if on, !state.calendar.hasAccess {
                        state.calendar.requestAccess { granted in if !granted { settings.quietInMeetings = false } }
                    }
                }))
                Toggle("When you're away from the Mac", isOn: $settings.quietWhenAway)
                Toggle("While presenting or watching full screen", isOn: $settings.quietFullScreen)
                if let reason = reminders.waitingReason {
                    Label("Holding the next reminder because \(reason).", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Quiet times")
            } footer: {
                FooterText("A held reminder is tried again every 5 minutes. To pause reminders in a Focus, add Sip's filter in System Settings → Focus → (a Focus) → Focus Filters.")
            }
            .disabled(!settings.remindersEnabled)

            Section {
                Toggle("Sunday summary at 7 PM", isOn: $settings.weeklySummary)
                if settings.weeklySummary, let next = reminders.nextWeekly {
                    LabeledContent("Next") { Text(next.formatted(.dateTime.weekday(.wide).hour().minute())).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Weekly summary")
            }

            Section {
                Toggle(isOn: $settings.nudgeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wobble the bottle when it's been a while")
                        Text("A quiet nudge on the widget itself, with no notification.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Send a Test Reminder") { state.sendTestReminder() }
                    .disabled(reminders.authorization != .authorized && reminders.authorization != .provisional)
            }
        }
        .onAppear { reminders.refreshAuthorization() }
    }

    @ViewBuilder
    private var authorizationRow: some View {
        switch reminders.authorization {
        case .denied:
            HStack {
                Label("Notifications are turned off for Sip.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Settings…") { reminders.openSystemSettings() }
            }
        case .notDetermined:
            HStack {
                Text("macOS will ask for permission the first time.").foregroundStyle(.secondary)
                Spacer()
                Button("Allow Notifications…") { reminders.requestAuthorization { _ in } }
            }
        default:
            Label("Notifications allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func calendarToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        DetailToggle(title, detail: detail, isOn: Binding(get: { isOn.wrappedValue }, set: { on in
            isOn.wrappedValue = on
            if on, !state.calendar.hasAccess {
                state.calendar.requestAccess { granted in
                    if granted { state.calendarChanged() } else { isOn.wrappedValue = false }
                }
            }
        }))
    }

    private var nextText: String {
        guard settings.remindersEnabled, let next = reminders.nextFire else { return "None scheduled" }
        let sameDay = Calendar.current.isDateInToday(next)
        return sameDay ? next.formatted(date: .omitted, time: .shortened)
                       : next.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
