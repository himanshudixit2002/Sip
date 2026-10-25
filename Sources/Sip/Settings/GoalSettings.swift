import AppKit
import SwiftUI
import SipCore

// MARK: - Goal

struct GoalSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore
    @StateObject private var cityQuery = Box("")

    var body: some View {
        let unit = settings.unit
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    BottleView(progress: min(state.store.progress, 1.2), layers: state.store.todayLayers,
                               appearance: BottleAppearance(settings), fizz: state.store.fizz)
                        .frame(width: 64, height: 116)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Volume.formatCompact(settings.dailyGoalML, unit))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: settings.dailyGoalML))
                            .animation(.snappy, value: settings.dailyGoalML)
                        Text("Your daily goal. Changing it applies from today; past days keep the goal they had.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                GoalSlider(settings: settings)
                UnitPicker(settings: settings)
            }

            Section {
                GoalCalculatorFields(settings: settings)
            } header: {
                Text("Calculate for me")
            } footer: {
                FooterText("A starting point, not medical advice. Food, health conditions and medication all change what you need.")
            }

            weatherSection

            WeeklyScheduleSection(settings: settings)

            Section("Your day") {
                Picker("A new day starts at", selection: $settings.dayStartHour) {
                    ForEach(0..<9) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
                }
                MinutesPicker(title: "Wake up", minutes: $settings.wakeMinutes)
                MinutesPicker(title: "Bedtime", minutes: $settings.sleepMinutes)
                Text("Waking hours set the even pace the widget compares you against, and when reminders may arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.streakFreezes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streak freezes")
                        Text("Earn a freeze every 7 days in a row (hold up to 2). A freeze covers one missed day so the streak survives.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Streaks")
            }
        }
    }
}

extension GoalSettings {
    @ViewBuilder
    var weatherSection: some View {
        let weather = state.weather
        let unit = settings.unit
        Section {
            Toggle("Raise my goal on hot days", isOn: $settings.weatherAdjust)
            if settings.weatherAdjust {
                LabeledContent("City") {
                    HStack {
                        TextField("Search for your city", text: $cityQuery.value)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit { weather.search(cityQuery.value) }
                        Button("Search") { weather.search(cityQuery.value) }
                    }
                }
                ForEach(weather.searchResults) { place in
                    Button {
                        settings.weatherCity = place.name
                        settings.weatherLatitude = place.latitude
                        settings.weatherLongitude = place.longitude
                        cityQuery.value = ""
                        weather.search("")
                    } label: {
                        Label("\(place.name), \(place.region)", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.borderless)
                }
                if settings.hasWeatherLocation {
                    LabeledContent("Today in \(settings.weatherCity)") {
                        if let t = weather.maxTemperatureC {
                            Text("High of \(Int(t.rounded()))° · " + (weather.bonusML > 0 ? "+\(Volume.format(weather.bonusML, unit))" : "no change"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(weather.error ?? "Checking…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            FooterText("Adds 250 ml from a high of 25°, 500 ml from 30° and 750 ml from 35°, for that day only. The forecast comes from Open-Meteo: only your city's coordinates are sent, once a day.")
        }
    }
}

/// Edits minutes-past-midnight with a time picker.
struct MinutesPicker: View {
    var title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(get: {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }), displayedComponents: .hourAndMinute)
    }
}


/// A different goal on some weekdays, and workout days with a bonus.
struct WeeklyScheduleSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let unit = settings.unit
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        // Weekdays in the order this Mac shows them (1 = Sunday).
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        Section {
            ForEach(order, id: \.self) { weekday in
                let custom = settings.weeklySchedule.goalsByWeekday[weekday]
                HStack(spacing: 10) {
                    Text(symbols[weekday - 1]).frame(width: 40, alignment: .leading)
                    Toggle("", isOn: Binding(get: { custom != nil }, set: { on in
                        settings.weeklySchedule.goalsByWeekday[weekday] = on ? settings.dailyGoalML : nil
                    }))
                    .labelsHidden()
                    .controlSize(.small)
                    if let custom {
                        Text(Volume.formatCompact(custom, unit)).monospacedDigit().frame(width: 64, alignment: .trailing)
                        Stepper("", value: Binding(get: { custom }, set: { settings.weeklySchedule.goalsByWeekday[weekday] = min(max($0, 500), 8000) }),
                                step: unit == .milliliters ? 250 : Volume.fromDisplay(8, .fluidOunces))
                            .labelsHidden()
                    } else {
                        Text("Usual goal").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Workout", isOn: Binding(get: { settings.weeklySchedule.workoutWeekdays.contains(weekday) }, set: { on in
                        if on { settings.weeklySchedule.workoutWeekdays.insert(weekday) } else { settings.weeklySchedule.workoutWeekdays.remove(weekday) }
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            LabeledContent("Workout bonus") {
                HStack {
                    Text("+" + Volume.format(settings.weeklySchedule.workoutBonusML, unit)).monospacedDigit()
                    Stepper("", value: $settings.weeklySchedule.workoutBonusML, in: 0...1500, step: unit == .milliliters ? 250 : Volume.fromDisplay(8, .fluidOunces))
                        .labelsHidden()
                }
            }
            TextField("Workout words", text: Binding(get: { settings.weeklySchedule.workoutKeywords.joined(separator: ", ") },
                                                     set: { settings.weeklySchedule.workoutKeywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
        } header: {
            Text("Weekly schedule")
        } footer: {
            FooterText("Give some days their own goal, and tick your workout days for the bonus. With Reminders → Calendar → Workouts on, an event containing one of the workout words gets the bonus too.")
        }
    }
}
