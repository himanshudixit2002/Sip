import AppKit
import SwiftUI
import SipCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case goal, drinks, appearance, widget, reminders, play, sound, integrations, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: return "Goal"
        case .drinks: return "Drinks"
        case .appearance: return "Appearance"
        case .widget: return "Widget"
        case .reminders: return "Reminders"
        case .play: return "Coach & Play"
        case .sound: return "Sound & Keys"
        case .integrations: return "Siri, iPhone & More"
        case .data: return "Data"
        }
    }

    var symbol: String {
        switch self {
        case .goal: return "target"
        case .drinks: return "cup.and.saucer.fill"
        case .appearance: return "paintpalette.fill"
        case .widget: return "rectangle.on.rectangle"
        case .reminders: return "bell.badge.fill"
        case .play: return "trophy.fill"
        case .sound: return "speaker.wave.2.fill"
        case .integrations: return "point.3.connected.trianglepath.dotted"
        case .data: return "externaldrive.fill"
        }
    }

    var tint: Color {
        switch self {
        case .goal: return Color(hex: 0x2E9BFF)
        case .drinks: return Color(hex: 0xC98B3C)
        case .appearance: return Color(hex: 0x9B6BFF)
        case .widget: return Color(hex: 0x1FC8C0)
        case .reminders: return Color(hex: 0xFF6A4D)
        case .play: return Color(hex: 0xF5B400)
        case .sound: return Color(hex: 0xFF4D8D)
        case .integrations: return Color(hex: 0x34C77B)
        case .data: return Color(hex: 0x7A8699)
        }
    }

    /// Words that find this tab from the search field.
    var keywords: String {
        switch self {
        case .goal: return "goal target weight exercise weather heat city day wake bedtime streak freeze schedule weekday workout gym"
        case .drinks: return "cups quick add bottle size refill caffeine coffee tea half-life drink types hydration factor"
        case .appearance: return "bottle style designer custom theme colour color liquid ice lemon steam fish aquarium plant time markers frost rain season festival motion fps bubbles condensation card background glass opacity"
        case .widget: return "widget placement desktop floating size scale display position lock snap spaces menu bar icon percent click hud peek pour out"
        case .reminders: return "reminders notifications interval smart quiet calls meetings away full screen wind down last call morning planner calendar meeting summary sunday nudge focus"
        case .play: return "coach tips levels xp challenges achievements badges buddies friends recap year month"
        case .sound: return "sound volume chime haptics hotkeys shortcuts keyboard login startup"
        case .integrations: return "siri shortcuts spotlight focus filter iphone health inbox icloud sync command line cli terminal raycast alfred links url"
        case .data: return "history export import csv backup restore edit day erase"
        }
    }
}

@Observable
final class SettingsNavigation {
    var tab: SettingsTab? = .goal
    var search = ""
}

struct SettingsView: View {
    let state: AppState
    @Bindable var nav: SettingsNavigation

    private var tabs: [SettingsTab] {
        let query = nav.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return SettingsTab.allCases }
        let words = query.split(separator: " ")
        return SettingsTab.allCases.filter { tab in
            let haystack = (tab.title + " " + tab.keywords).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(tabs, selection: $nav.tab) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab.tint.gradient))
                }
                .tag(tab)
                .padding(.vertical, 2)
            }
            .searchable(text: $nav.search, placement: .sidebar, prompt: "Search settings")
            .onChange(of: nav.search) { _, _ in
                if let first = tabs.first, !tabs.contains(nav.tab ?? .goal) { nav.tab = first }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 214, max: 250)
        } detail: {
            Group {
                switch nav.tab ?? .goal {
                case .goal: GoalSettings(state: state, settings: state.settings)
                case .drinks: DrinkSettings(state: state, settings: state.settings)
                case .appearance: AppearanceSettings(state: state, settings: state.settings)
                case .widget: WidgetSettings(state: state, settings: state.settings)
                case .reminders: ReminderSettings(state: state, settings: state.settings, reminders: state.reminders)
                case .play: PlaySettings(state: state, settings: state.settings)
                case .sound: SoundKeySettings(state: state, settings: state.settings)
                case .integrations: IntegrationSettings(state: state, settings: state.settings)
                case .data: DataSettings(state: state, store: state.store)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((nav.tab ?? .goal).title)
        }
        .frame(minWidth: 720, minHeight: 540)
    }
}

/// Section footnotes read as body text, left-aligned.
struct FooterText: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A toggle with a second, smaller line explaining it.
struct DetailToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
