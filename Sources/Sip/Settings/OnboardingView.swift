import SwiftUI
import SipCore

final class OnboardingModel: ObservableObject {
    @Published var step = 0
}

/// Three steps on first launch: a goal, a look, and reminders.
struct OnboardingView: View {
    let state: AppState
    @StateObject private var model = OnboardingModel()

    var body: some View {
        let settings = state.settings
        VStack(spacing: 0) {
            ZStack {
                switch model.step {
                case 0: GoalStep(settings: settings).transition(.push(from: .trailing))
                case 1: LookStep(settings: settings).transition(.push(from: .trailing))
                default: ReminderStep(state: state, settings: settings).transition(.push(from: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.step)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == model.step ? settings.theme.mid : Color.primary.opacity(0.15))
                            .frame(width: i == model.step ? 20 : 7, height: 7)
                    }
                }
                .animation(.spring, value: model.step)
                Spacer()
                if model.step > 0 {
                    Button("Back") { model.step -= 1 }
                }
                Button(model.step == 2 ? "Start Sipping" : "Continue") {
                    if model.step == 2 { state.finishOnboarding() } else { model.step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.theme.mid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 560, height: 600)
    }
}

private struct StepHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
    }
}

private struct GoalStep: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Welcome to Sip",
                       subtitle: "A bottle on your desktop that fills as you drink. First, how much should you aim for each day?")
                .padding(.top, 34)
            HStack(spacing: 28) {
                BottleView(progress: 0.68, appearance: BottleAppearance(settings))
                    .frame(width: 92, height: 170)
                VStack(alignment: .leading, spacing: 12) {
                    GoalCalculatorFields(settings: settings)
                    Divider()
                    HStack {
                        Text("Your goal").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Volume.formatCompact(settings.dailyGoalML, settings.unit))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: settings.dailyGoalML))
                            .animation(.snappy, value: settings.dailyGoalML)
                    }
                    GoalSlider(settings: settings)
                        .labelsHidden()
                    UnitPicker(settings: settings)
                        .labelsHidden()
                }
                .frame(width: 290)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LookStep: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Pick your bottle",
                       subtitle: "Change any of this later in Settings → Appearance, or right-click the widget.")
                .padding(.top, 34)
            StylePicker(settings: settings, columns: 5)
                .padding(.horizontal, 30)
            ThemePicker(settings: settings, columns: 7)
                .padding(.horizontal, 40)
            Picker("Widget size", selection: $settings.widgetSize) {
                ForEach(WidgetSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            Spacer(minLength: 0)
        }
    }
}

private struct ReminderStep: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Stay on pace",
                       subtitle: "Sip can nudge you when you'd otherwise fall behind, and stays quiet once you're done for the day.")
                .padding(.top, 34)
            VStack(alignment: .leading, spacing: 14) {
                RemindersToggle(state: state, settings: settings, title: "Send me reminders")
                ReminderIntervalPicker(settings: settings)
                    .disabled(!settings.remindersEnabled)
                HStack {
                    MinutesPicker(title: "Awake from", minutes: $settings.wakeMinutes)
                    MinutesPicker(title: "to", minutes: $settings.sleepMinutes)
                }
                LoginItemToggle(title: "Open Sip when I log in", showsStatus: false)
            }
            .frame(width: 360)

            VStack(alignment: .leading, spacing: 9) {
                Tip(symbol: "hand.tap.fill", text: "Click the bottle to log your default cup.")
                Tip(symbol: "arrow.up.circle.fill", text: "Drag up on the bottle to pour any amount.")
                Tip(symbol: "keyboard", text: "Press \(settings.logHotKey.display) from any app to log a glass.")
                Tip(symbol: "ellipsis.circle", text: "Point at the widget for its ⋯ menu, or click the ring in the menu bar. Opening Sip from Spotlight shows Settings.")
            }
            .padding(16)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
            Spacer(minLength: 0)
        }
    }
}

private struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            Text(text).font(.callout)
        }
    }
}
