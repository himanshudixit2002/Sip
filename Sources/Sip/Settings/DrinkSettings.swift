import AppKit
import SwiftUI
import SipCore

// MARK: - Drinks

struct DrinkSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach($settings.cups) { $cup in
                    CupEditor(cup: $cup, settings: settings,
                              isDefault: settings.defaultCup.id == cup.id,
                              makeDefault: { settings.defaultCupID = cup.id },
                              remove: settings.cups.count > 1 ? { settings.cups.removeAll { $0.id == cup.id } } : nil)
                }
                .onMove { settings.cups.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Button {
                        settings.cups.append(Cup(name: "Cup", amountML: 300, symbol: "cup.and.saucer.fill"))
                    } label: {
                        Label("Add Cup", systemImage: "plus")
                    }
                    .disabled(settings.cups.count >= 6)
                    Spacer()
                    Button("Restore Defaults") {
                        settings.cups = Cup.defaults
                        settings.defaultCupID = nil
                    }
                }
            } header: {
                Text("Quick-add cups")
            } footer: {
                FooterText("The medium and large widgets show the first three; the menu bar shows them all. The starred cup is used when you click the bottle, press the hotkey, or tap Log on a reminder.")
            }

            Section {
                LabeledContent("Bottle size") {
                    HStack {
                        Text(Volume.format(settings.bottleSizeML, settings.unit)).monospacedDigit()
                        Stepper("Bottle size", value: Binding(get: { settings.bottleSizeML },
                                                              set: { settings.bottleSizeML = Volume.snap($0, settings.unit) }),
                                in: 100...3000, step: settings.unit == .milliliters ? 50 : Volume.mlPerFluidOunce * 2)
                            .labelsHidden()
                    }
                }
                Toggle("Count refills on the widget", isOn: $settings.showRefills)
            } header: {
                Text("Your bottle")
            } footer: {
                FooterText("The widget counts bottles toward your goal, as in “2/4”. Click that count, or choose Finished My Bottle, to log a full one.")
            }

            Section {
                Toggle("Track caffeine", isOn: $settings.caffeineTracking)
                if settings.caffeineTracking {
                    CaffeineRateRow(title: "Coffee", drink: .coffee, settings: settings, range: 0.1...0.9)
                    CaffeineRateRow(title: "Tea", drink: .tea, settings: settings, range: 0.05...0.5)
                    MinutesPicker(title: "Gentle warning after", minutes: $settings.caffeineCutoffMinutes)
                    LabeledContent("Daily limit") {
                        HStack {
                            Text("\(Int(settings.caffeineLimitMG)) mg").monospacedDigit()
                            Stepper("Daily limit", value: $settings.caffeineLimitMG, in: 100...1000, step: 50).labelsHidden()
                        }
                    }
                    LabeledContent("Half-life") {
                        HStack {
                            Slider(value: Binding(get: { settings.caffeineHalfLifeHours },
                                                  set: { settings.caffeineHalfLifeHours = ($0 * 2).rounded() / 2 }),
                                   in: 3...8).frame(width: 180)
                            Text(String(format: "%.1f h", settings.caffeineHalfLifeHours)).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                    if let now = state.caffeineNow, now >= 1 {
                        LabeledContent("In you now") {
                            Text("~\(Int(now.rounded())) mg" + (state.caffeineClearTime.map { ", under 50 mg by \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Caffeine")
            } footer: {
                FooterText("Estimates: about 95 mg in a 240 ml coffee and 47 mg in a black tea. Caffeine leaves the body by half every few hours (about 5 for most adults); Sip uses that to show what's still in you and when it'll be low enough for sleep.")
            }

            Section {
                ForEach(DrinkKind.allCases) { drink in
                    DrinkRow(drink: drink, settings: settings)
                }
            } header: {
                Text("Drink types")
            } footer: {
                FooterText("The hydration factor is how much of a drink counts toward your goal. Defaults are conservative; adjust them to your own advice.")
            }
        }
    }
}

struct CaffeineRateRow: View {
    let title: String
    let drink: DrinkKind
    @Bindable var settings: SettingsStore
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent("\(title) per 100 ml") {
            HStack {
                Slider(value: Binding(get: { settings.caffeineRates[drink] },
                                      set: { settings.caffeineRates[drink] = ($0 * 100).rounded() / 100 }),
                       in: range)
                    .frame(width: 180)
                Text("\(Int((settings.caffeineRates[drink] * 100).rounded())) mg").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}

struct CupEditor: View {
    @Binding var cup: Cup
    let settings: SettingsStore
    var isDefault: Bool
    var makeDefault: () -> Void
    var remove: (() -> Void)?

    var body: some View {
        let unit = settings.unit
        HStack(spacing: 10) {
            Button(action: makeDefault) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isDefault ? "Default cup" : "Make this the default cup")

            Menu {
                ForEach(Cup.symbolChoices, id: \.self) { symbol in
                    Button { cup.symbol = symbol } label: { Label(symbol, systemImage: symbol) }
                }
            } label: {
                Image(systemName: cup.symbol)
                    .foregroundStyle(settings.theme.color(for: cup.drink))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)

            TextField("Name", text: $cup.name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 110)

            Text(Volume.format(cup.amountML, unit))
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
            Stepper("Amount", value: Binding(get: { Volume.toDisplay(cup.amountML, unit) },
                                             set: { cup.amountML = max(Volume.snap(Volume.fromDisplay($0, unit), unit), 10) }),
                    in: 1...3000, step: unit == .milliliters ? 10 : 1)
                .labelsHidden()

            Picker("", selection: $cup.drink) {
                ForEach(DrinkKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)

            Spacer(minLength: 0)
            if let remove {
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Remove this cup")
            }
        }
    }
}

struct DrinkRow: View {
    let drink: DrinkKind
    @Bindable var settings: SettingsStore

    var body: some View {
        let enabled = Binding(get: { !settings.disabledDrinks.contains(drink) }, set: { on in
            if on { settings.disabledDrinks.remove(drink) } else if settings.enabledDrinks.count > 1 { settings.disabledDrinks.insert(drink) }
        })
        let factor = Binding(get: { settings.factors[drink] }, set: { settings.factors[drink] = ($0 * 20).rounded() / 20 })
        HStack(spacing: 12) {
            Toggle("", isOn: enabled).labelsHidden()
            Circle()
                .fill(settings.theme.color(for: drink).gradient)
                .frame(width: 14, height: 14)
            Label(drink.title, systemImage: drink.symbol)
                .frame(width: 120, alignment: .leading)
            Slider(value: factor, in: 0.5...1.2)
                .disabled(!enabled.wrappedValue)
            Text("\(Int((factor.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
