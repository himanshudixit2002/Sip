import SwiftUI
import SipCore

// Controls that appear both in Settings and in onboarding. Each exists once,
// so the two can't drift apart (they used to offer different reminder
// intervals and step the goal differently).

struct UnitPicker: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Picker("Units", selection: $settings.unit) {
            ForEach(VolumeUnit.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// The daily goal, rounded to a tidy step in your unit.
struct GoalSlider: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let unit = settings.unit
        Slider(value: Binding(get: { settings.dailyGoalML },
                              set: { settings.dailyGoalML = unit == .milliliters ? ($0 / 50).rounded() * 50 : Volume.snap($0, unit) }),
               in: 1000...5000) {
            Text("Daily goal")
        } minimumValueLabel: {
            Text(Volume.formatCompact(1000, unit)).font(.caption)
        } maximumValueLabel: {
            Text(Volume.formatCompact(5000, unit)).font(.caption)
        }
    }
}

/// Weight, exercise and climate, and the goal they suggest.
struct GoalCalculatorFields: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        LabeledContent("Body weight") {
            HStack {
                Slider(value: Binding(get: { settings.weightKg }, set: { settings.weightKg = $0.rounded() }), in: 35...150)
                    .frame(minWidth: 140, maxWidth: 220)
                Text("\(Int(settings.weightKg)) kg").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
        LabeledContent("Exercise per day") {
            HStack {
                Slider(value: $settings.exerciseMinutes, in: 0...180, step: 15).frame(minWidth: 140, maxWidth: 220)
                Text("\(Int(settings.exerciseMinutes)) min").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
        Toggle("Hot or humid climate", isOn: $settings.hotClimate)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested: \(Volume.formatCompact(settings.suggestedGoalML, settings.unit))")
                    .font(.headline)
                    .contentTransition(.numericText(value: settings.suggestedGoalML))
                    .animation(.snappy, value: settings.suggestedGoalML)
                Text("35 ml per kg, plus 350 ml per 30 minutes of exercise, plus 500 ml in hot weather.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use This") { settings.dailyGoalML = settings.suggestedGoalML }
                .disabled(abs(settings.suggestedGoalML - settings.dailyGoalML) < 1)
        }
    }
}

struct ReminderIntervalPicker: View {
    @Bindable var settings: SettingsStore
    static let choices = [30, 45, 60, 90, 120, 180]

    var body: some View {
        Picker("Every", selection: $settings.reminderInterval) {
            ForEach(Self.choices, id: \.self) { Text(Self.label($0)).tag($0) }
        }
    }

    static func label(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        if minutes % 60 == 0 { return "\(minutes / 60) hour\(minutes == 60 ? "" : "s")" }
        return String(format: "%.1f hours", Double(minutes) / 60)
    }
}

/// Turning reminders on asks for notification permission the first time.
struct RemindersToggle: View {
    let state: AppState
    @Bindable var settings: SettingsStore
    var title = "Remind me to drink"

    var body: some View {
        Toggle(title, isOn: Binding(get: { settings.remindersEnabled }, set: { on in
            settings.remindersEnabled = on
            if on, state.reminders.authorization == .notDetermined {
                state.reminders.requestAuthorization { _ in }
            }
        }))
    }
}

/// Open at login, showing what macOS actually did.
struct LoginItemToggle: View {
    var title = "Open Sip when you log in"
    var showsStatus = true
    @StateObject private var status = Box(LoginItem.statusText)
    @StateObject private var error = Box<String?>(nil)
    @StateObject private var enabled = Box(LoginItem.isEnabled)

    var body: some View {
        Toggle(title, isOn: Binding(get: { enabled.value }, set: { on in
            error.value = LoginItem.set(on)
            status.value = LoginItem.statusText
            enabled.value = LoginItem.isEnabled
        }))
        if showsStatus || error.value != nil {
            Text(error.value ?? status.value)
                .font(.caption)
                .foregroundStyle(error.value == nil ? Color.secondary : Color.orange)
        }
    }
}
