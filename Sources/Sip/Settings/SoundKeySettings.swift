import AppKit
import SwiftUI
import SipCore

// MARK: - Sound & keys

struct SoundKeySettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Pouring and bubbles", isOn: $settings.pourSound)
                Toggle("Chime when you reach your goal", isOn: $settings.goalSound)
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $settings.volume, in: 0...1).frame(width: 200)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        Button("Test") {
                            state.sounds.playPour(fraction: 0.12)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { state.sounds.playChime() }
                        }
                    }
                }
                Toggle("Trackpad feedback when logging", isOn: $settings.haptics)
            }
            Section {
                Toggle("Global keyboard shortcuts", isOn: $settings.hotKeysEnabled)
                LabeledContent("Log the default cup") {
                    HotKeyRecorder(hotKey: $settings.logHotKey, state: state)
                }
                LabeledContent("Bring the widget forward, or show and hide it") {
                    HotKeyRecorder(hotKey: $settings.toggleHotKey, state: state)
                }
                LabeledContent("Open the quick-log box") {
                    HotKeyRecorder(hotKey: $settings.quickLogHotKey, state: state)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                FooterText("Shortcuts work from any app. They need at least one of ⌃, ⌥ or ⌘.")
            }
            .disabled(!settings.hotKeysEnabled)

            Section {
                LoginItemToggle()
            } header: {
                Text("Startup")
            }
        }
    }
}

struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    let state: AppState
    @StateObject private var recording = Box(false)
    @StateObject private var monitor = Box<Any?>(nil)

    var body: some View {
        Button {
            recording.value ? stop() : start()
        } label: {
            Text(recording.value ? "Press a shortcut…" : hotKey.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(recording.value ? .accentColor : nil)
    }

    private func start() {
        recording.value = true
        // Don't let the current shortcut fire while it's being replaced.
        state.hotKeys.unregister()
        monitor.value = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Escape cancels
            if let key = HotKey(event: event) {
                hotKey = key
                stop()
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private func stop() {
        if let m = monitor.value { NSEvent.removeMonitor(m) }
        monitor.value = nil
        recording.value = false
        state.applyHotKeys()
    }
}
