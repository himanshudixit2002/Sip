import AppKit
import SwiftUI
import SipCore

// MARK: - Widget

struct WidgetSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Show the widget", isOn: $settings.widgetVisible)
                Picker("Placement", selection: $settings.placement) {
                    ForEach(Placement.allCases) { placement in
                        VStack(alignment: .leading) {
                            Text(placement.title)
                            Text(placement.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(placement)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Size") {
                Picker("Size", selection: $settings.widgetSize) {
                    ForEach(WidgetSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Scale") {
                    HStack {
                        Slider(value: Binding(get: { settings.widgetScale }, set: { settings.widgetScale = ($0 * 20).rounded() / 20 }),
                               in: 0.8...1.4).frame(width: 200)
                        Text("\(settings.widgetScale.percent)%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Position") {
                if NSScreen.screens.count > 1 {
                    Picker("Display", selection: $settings.widgetDisplay) {
                        Text("Follow the main display").tag("main")
                        ForEach(NSScreen.screens, id: \.localizedName) { screen in
                            Text(screen.localizedName).tag(screen.localizedName)
                        }
                    }
                }
                Toggle("Lock position", isOn: $settings.lockPosition)
                Toggle("Snap to screen edges", isOn: $settings.snapToEdges)
                Toggle("Show on every Space", isOn: $settings.allSpaces)
                Button("Move to Top-Right Corner") { state.widget?.resetPosition() }
            }

            Section {
                Picker("Clicking the bottle", selection: $settings.clickAction) {
                    ForEach(ClickAction.allCases) { Text($0.title).tag($0) }
                }
                DetailToggle("Drag down from the neck to pour out the last drink",
                             detail: "The bottle tips over and empties what you logged last. Same as Undo.",
                             isOn: $settings.pourOutUndo)
            } header: {
                Text("Interaction")
            } footer: {
                FooterText("Drag up on the bottle to pour any amount. Drag the card itself to move it. Point at it for the ⋯ menu, or right-click it. \(settings.toggleHotKey.display) brings a buried widget forward for a moment.")
            }

            Section {
                Picker("Menu bar icon", selection: $settings.menuBarIcon) {
                    ForEach(MenuBarIconMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show the percentage next to it", isOn: $settings.showPercentInMenuBar)
                    .disabled(settings.menuBarIcon == .never)
                DetailToggle("Show a HUD when you log out of sight",
                             detail: "A small card at the top of the screen when you log from a hotkey, Siri, the command line or your phone while the widget is covered.",
                             isOn: $settings.hudEnabled)
            } header: {
                Text("Menu bar & HUD")
            } footer: {
                if settings.menuBarIcon == .never {
                    FooterText("With no menu bar icon, reach Sip from the ⋯ on the widget, by opening it from Spotlight, or with \(settings.toggleHotKey.display).")
                }
            }
        }
    }
}
