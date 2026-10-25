import AppKit
import SwiftUI
import SipCore

struct PlaySettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        let derived = state.derived
        Form {
            Section {
                DetailToggle("Coach tips", detail: "Patterns from your last four weeks, one at a time, in the popover and the large widgets.",
                             isOn: $settings.coachEnabled)
                if settings.coachEnabled {
                    if let suggestion = derived.goalSuggestion {
                        HStack(alignment: .top) {
                            Image(systemName: "target").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Try \(Volume.formatCompact(suggestion.goalML, settings.unit)) a day").font(.headline)
                                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Not Now") { state.dismissGoalSuggestion() }
                            Button("Use It") { state.acceptGoalSuggestion() }.buttonStyle(.borderedProminent)
                        }
                    }
                    ForEach(derived.tips) { tip in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                Text(tip.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: tip.symbol)
                        }
                    }
                    if derived.tips.isEmpty, derived.goalSuggestion == nil {
                        Text("Nothing to suggest yet. Tips appear after a week of logging.").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Coach")
            }

            Section {
                DetailToggle("Levels", detail: "XP for every drink, with bonuses for reaching your goal, streaks, an early start and challenges. 30 levels, from Droplet to Poseidon.",
                             isOn: $settings.levelsEnabled)
                if settings.levelsEnabled {
                    LevelBar(level: derived.level, theme: settings.theme)
                    LabeledContent("Today", value: "+\(derived.todayXP) XP")
                }
                DetailToggle("Daily challenge", detail: "One small goal a day, sized to you: a litre before noon, six separate drinks, no coffee after 2 PM…",
                             isOn: $settings.challengesEnabled)
                if let challenge = derived.challenge {
                    ChallengeCard(progress: challenge, theme: settings.theme)
                }
            } header: {
                Text("Levels and challenges")
            } footer: {
                FooterText("Missed a day? Drink 110% of your goal the next day and the streak is repaired (once a month). Badges are in Insights.")
            }

            BuddiesSection(state: state, settings: settings)

            Section {
                Toggle("Offer a recap on the first of each month", isOn: $settings.recapOffer)
                HStack {
                    Button("Show This Month's Recap") { state.showRecap() }
                    Button("Year in Water \(String(state.store.today.year))") { state.showRecap(year: state.store.today.year) }
                }
            } header: {
                Text("Recaps")
            }
        }
    }
}

/// Sharing today's progress with friends through a shared folder.
private struct BuddiesSection: View {
    let state: AppState
    @Bindable var settings: SettingsStore
    @StateObject private var copied = Box(false)

    var body: some View {
        Section {
            Toggle("Share with buddies", isOn: $settings.buddiesEnabled)
            if settings.buddiesEnabled {
                TextField("Your name", text: $settings.buddyName)
                LabeledContent("Shared folder") {
                    HStack {
                        Text(settings.buddiesFolderPath.isEmpty ? "None chosen"
                             : URL(fileURLWithPath: settings.buddiesFolderPath).abbreviatedPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let url = Modal.chooseFolder(prompt: "Use This Folder") { settings.buddiesFolderPath = url.path }
                        }
                    }
                }
                if state.buddies.cards.isEmpty {
                    Text(settings.buddiesFolderPath.isEmpty ? "Choose a folder to start." : "No buddies have shared anything in the last day and a half.")
                        .foregroundStyle(.secondary)
                } else {
                    BuddiesRow(cards: state.buddies.cards, theme: settings.theme, style: settings.bottleStyle) { state.buddies.poke($0) }
                }
            }
        } header: {
            Text("Buddies")
        } footer: {
            FooterText("""
            Make a folder in iCloud Drive (say, “Sip Buddies”), right-click it in Finder and choose Share → Collaborate, and invite your friends. Everyone running Sip picks that folder here. Each Mac shares only today's percent, streak and level, never your history. Click a buddy to nudge them.
            """)
        }
    }
}
