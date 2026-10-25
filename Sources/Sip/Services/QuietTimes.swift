import AppKit
import CoreAudio

/// Decides whether now is a bad moment for a reminder. Every check is cheap
/// and runs only when a reminder is due, never on a timer of its own.
@MainActor
final class QuietTimes {
    enum Reason: String {
        case inCall = "you're on a call"
        case inMeeting = "you're in a meeting"
        case away = "you're away from the Mac"
        case fullScreen = "you're presenting or watching full screen"
        case locked = "the screen is locked"
        case focus = "a Focus you chose is on"
    }

    /// Checks whether a calendar event is on right now (only asked when
    /// "in meetings" is on).
    var inMeeting: () -> Bool = { false }

    func reason(settings: SettingsStore) -> Reason? {
        if Self.screenLocked() { return .locked }
        if settings.focusQuiet { return .focus }
        if settings.quietWhenAway, Self.idleSeconds() > 5 * 60 { return .away }
        if settings.quietInCalls, Self.microphoneInUse() { return .inCall }
        if settings.quietFullScreen, Self.frontmostIsFullScreen() { return .fullScreen }
        if settings.quietInMeetings, inMeeting() { return .inMeeting }
        return nil
    }

    // MARK: System state

    private static func screenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Any audio input device in use by any app: a call, a recording, dictation.
    /// Reading this needs no microphone permission.
    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return false }
        for device in devices {
            // Only devices with input streams.
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == noErr, value != 0 {
                return true
            }
        }
        return false
    }

    /// Apps whose full-screen mode means a presentation or something you're
    /// watching. Plenty of people work in full-screen editors and browsers all
    /// day, so those alone don't count.
    private static let presentingApps: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "com.apple.QuickTimePlayerX", "com.apple.TV",
        "com.apple.Music", "org.videolan.vlc", "com.colliderli.iina", "us.zoom.xos", "com.microsoft.teams2",
        "com.microsoft.teams", "com.cisco.webexmeetingsapp", "com.netflix.Netflix", "com.amazon.aiv.AIVApp",
        "com.apple.FaceTime", "com.hnc.Discord",
    ]

    /// A presentation, video or call app has a window filling a whole display.
    static func frontmostIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              presentingApps.contains(app.bundleIdentifier ?? "") else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return WindowList.onScreen().contains { window in
            window.ownerPID == app.processIdentifier && window.layer == 0
                && screens.contains { abs($0.width - window.bounds.width) < 1 && abs($0.height - window.bounds.height) < 1 }
        }
    }
}
