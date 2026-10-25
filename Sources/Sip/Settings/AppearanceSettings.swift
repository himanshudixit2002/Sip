import AppKit
import SwiftUI
import SipCore

// MARK: - Appearance

struct AppearanceSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Bottle") {
                StylePicker(settings: settings)
                    .padding(.vertical, 4)
                Toggle(isOn: $settings.layeredDrinks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Layer drinks by colour")
                        Text("Coffee, tea and juice settle as their own bands under the water.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if settings.bottleStyle == .custom {
                BottleDesigner(settings: settings)
            }

            Section {
                TextField("Label", text: Binding(get: { settings.bottleLabel },
                                                 set: { settings.bottleLabel = String($0.prefix(16)) }),
                          prompt: Text("e.g. Himanshu's bottle"))
                Picker("Glass tint", selection: $settings.glassTint) {
                    ForEach(GlassTint.allCases) { tint in
                        HStack {
                            Circle().fill(tint.color ?? .white.opacity(0.3)).frame(width: 10, height: 10)
                            Text(tint.title)
                        }
                        .tag(tint)
                    }
                }
            } header: {
                Text("Make it yours")
            } footer: {
                FooterText("The label is printed across the bottle. Up to 16 characters.")
            }

            Section("Liquid") {
                ThemePicker(settings: settings, columns: 7)
                    .padding(.vertical, 4)
            }

            Section {
                DetailToggle("Fish", detail: "One lives in your water; another joins at 7, 30 and 100 days in a row. They sleep at night and slow down when you're behind.",
                             isOn: $settings.companionFish)
                DetailToggle("A plant beside the bottle", detail: "Grows a leaf for each good day of the last two weeks and flowers on a 7-day streak. Medium sizes and up.",
                             isOn: $settings.companionPlant)
                DetailToggle("Time markers", detail: "Gold marks on the glass for where you'd ideally be by each time of day. The next one lights up.",
                             isOn: $settings.timeMarkers)
                Picker("Ice cubes", selection: $settings.iceMode) {
                    ForEach(IceMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Lemon slice", isOn: $settings.lemonSlice)
                Toggle("Steam after tea or coffee", isOn: $settings.steamEnabled)
            } header: {
                Text("In the bottle")
            } footer: {
                FooterText("“On hot days” uses the forecast from Goal → Weather (28° or warmer). Daylight liquid changes colour through the day: dawn, day, dusk and night.")
            }

            Section {
                DetailToggle("Weather on the glass", detail: "Frost when it's cold, rain running down when it's raining, heat haze on hot days. Uses your city from Goal → Weather.",
                             isOn: $settings.livingGlass)
                DetailToggle("Festivals and seasons", detail: "Diwali lights, Holi colours, monsoon rain, winter frost, Christmas snow and New Year fireworks, on their days.",
                             isOn: $settings.seasonalPacks)
                DetailToggle("Playful water", detail: "Ripples where the cursor brushes the surface; shake the widget to stir it up.",
                             isOn: $settings.playfulWater)
                DetailToggle("Dim at night", detail: "After bedtime the water darkens, the fish sleep and the bottle draws less often.",
                             isOn: $settings.nightDim)
                Picker("Reaching your goal", selection: $settings.celebrationStyle) {
                    ForEach(CelebrationStyle.allCases) { Text($0.title).tag($0) }
                }
                Button("Preview Celebration") {
                    SipEvents.post(SipEvents.celebrate, ["style": settings.celebrationStyle.resolved().rawValue])
                }
            } header: {
                Text("Alive")
            } footer: {
                FooterText("Streak milestones always get fireworks, and a level-up gets a rainbow.")
            }

            Section {
                Picker("Motion", selection: $settings.motion) {
                    ForEach(MotionLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.motion.detail).font(.caption).foregroundStyle(.secondary)
                Picker("Frame rate while pouring", selection: $settings.maxFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                Toggle("Bubbles", isOn: $settings.showBubbles)
                Toggle("Measuring marks", isOn: $settings.showTicks)
                Toggle("Condensation on the glass", isOn: $settings.showCondensation)
            } header: {
                Text("Animation")
            } footer: {
                FooterText("At rest the bottle draws at 30 fps or less, and stops entirely when it's covered by a window or the display sleeps.")
            }

            Section("Card") {
                Picker("Background", selection: $settings.cardBackground) {
                    ForEach(CardBackground.available) { Text($0.title).tag($0) }
                }
                LabeledContent("Opacity") {
                    Slider(value: $settings.cardOpacity, in: 0.3...1)
                        .frame(width: 240)
                }
                .disabled(settings.cardBackground == .glass || settings.cardBackground == .clearGlass || settings.cardBackground == .none)
            }

            Section {
                Button("Reset Appearance") { settings.resetAppearance() }
            }
        }
    }
}

struct StyleCard: View {
    let style: BottleStyle
    let selected: Bool
    let settings: SettingsStore
    let action: () -> Void

    var body: some View {
        var look = BottleAppearance(settings)
        look.style = style
        look.showTicks = false
        return Button(action: action) {
            VStack(spacing: 6) {
                BottleView(progress: 0.62, appearance: look)
                    .frame(width: 64, height: 110)
                Text(style.title)
                    .font(.system(size: 11, weight: selected ? .bold : .medium, design: .rounded))
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? settings.theme.mid.opacity(0.18) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? settings.theme.mid : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// Sliders for "Your Design", with a live bottle beside them.
struct BottleDesigner: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let spec = Binding(get: { settings.customBottle }, set: { settings.customBottle = $0 })
        Section {
            HStack(alignment: .top, spacing: 18) {
                BottleView(progress: 0.6, appearance: BottleAppearance(settings))
                    .frame(width: 96, height: 180)
                VStack(alignment: .leading, spacing: 8) {
                    slider("Body width", spec.bodyWidth, 56...94)
                    slider("Shoulder", spec.shoulder, 0...1)
                    slider("Waist", spec.waist, 0...10)
                    slider("Neck width", spec.neckWidth, 16...44)
                    slider("Neck height", spec.neckHeight, 8...60)
                    slider("Rounded base", spec.baseRound, 4...30)
                    Picker("Top", selection: spec.cap) {
                        ForEach(CustomCap.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Start Over") { settings.customBottle = CustomBottleSpec() }
            }
        } header: {
            Text("Your design")
        } footer: {
            FooterText("Shape a bottle like the one on your desk. Set its real size in Drinks → Your bottle so refills count right.")
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 96, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = (($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * 40).rounded() / 40
                                         * (range.upperBound - range.lowerBound) + range.lowerBound }),
                   in: range)
        }
    }
}

/// Every bottle style as a live card. Shared with onboarding.
struct StylePicker: View {
    @Bindable var settings: SettingsStore
    var columns = 5

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(BottleStyle.allCases) { style in
                StyleCard(style: style, selected: settings.bottleStyle == style, settings: settings) {
                    settings.bottleStyle = style
                }
            }
        }
    }
}

/// Every liquid theme as a swatch. Shared with onboarding.
struct ThemePicker: View {
    @Bindable var settings: SettingsStore
    var columns = 7

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 10) {
            ForEach(LiquidTheme.allCases) { theme in
                ThemeSwatch(theme: theme, selected: settings.theme == theme) { settings.theme = theme }
            }
        }
    }
}

struct ThemeSwatch: View {
    let theme: LiquidTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(theme.gradient)
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .center))
                        .padding(4)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2).padding(-4))
                Text(theme.title).font(.system(size: 10.5, weight: selected ? .bold : .regular))
            }
        }
        .buttonStyle(PressableStyle())
    }
}
