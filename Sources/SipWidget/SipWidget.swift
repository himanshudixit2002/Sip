import AppIntents
import SwiftUI
import WidgetKit
import SipCore

// Sip's system widgets (desktop and Notification Center) and Control Center
// buttons. The animated widget is the app itself; these are its still
// companions. They read the summary the app writes and hand every action back
// to the app as a sip:// link, so a drink logged here pours, sounds and counts
// exactly like one logged anywhere else.

struct SipEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct SipProvider: TimelineProvider {
    func placeholder(in context: Context) -> SipEntry { SipEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SipEntry) -> Void) {
        completion(SipEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SipEntry>) -> Void) {
        let entry = SipEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .sample)
        // The app asks for a reload whenever the numbers change; this is only
        // a fallback so a new day shows up even if the app isn't running.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

private extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A still bottle filled to `progress`.
struct StillBottle: View {
    var progress: Double
    var colors: [Color]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let body = RoundedRectangle(cornerRadius: w * 0.24, style: .continuous)
            let bodyRect = CGRect(x: 0, y: h * 0.2, width: w, height: h * 0.8)
            ZStack(alignment: .top) {
                // Cap and neck.
                RoundedRectangle(cornerRadius: w * 0.08)
                    .fill(LinearGradient(colors: [colors.last ?? .blue, colors.first ?? .cyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.42, height: h * 0.1)
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: w * 0.32, height: h * 0.12)
                    .offset(y: h * 0.09)
                ZStack(alignment: .bottom) {
                    body.fill(.white.opacity(0.1))
                    Rectangle()
                        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                        .frame(height: bodyRect.height * min(max(progress, 0), 1))
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.65)).frame(height: 1.5) }
                }
                .clipShape(body)
                .overlay(body.strokeBorder(.white.opacity(0.55), lineWidth: 1.2))
                .frame(width: w, height: bodyRect.height)
                .offset(y: bodyRect.minY)
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
    }
}

struct SipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SipEntry

    var body: some View {
        let s = entry.snapshot
        let colors = s.colors.map(Color.init(hex:))
        Group {
            switch family {
            case .systemSmall: small(s, colors)
            case .systemMedium: medium(s, colors)
            default: large(s, colors)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(hex: 0x16233F), Color(hex: 0x0A1122)], startPoint: .top, endPoint: .bottom)
        }
        .widgetURL(URL(string: "sip://peek"))
        .foregroundStyle(.white)
    }

    private func small(_ s: WidgetSnapshot, _ colors: [Color]) -> some View {
        HStack(spacing: 10) {
            StillBottle(progress: s.progress, colors: colors)
            VStack(alignment: .leading, spacing: 2) {
                streak(s)
                Spacer(minLength: 0)
                Text("\(Int((s.progress * 100).rounded()))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("\(s.consumedText) of \(s.goalText)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let cup = s.cups.first { cupLink(cup) }
            }
        }
    }

    private func medium(_ s: WidgetSnapshot, _ colors: [Color]) -> some View {
        HStack(spacing: 14) {
            StillBottle(progress: s.progress, colors: colors)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TODAY").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    streak(s)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.consumedText).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("/ \(s.goalText)").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
                ProgressView(value: min(s.progress, 1)).tint(colors.dropFirst().first ?? .blue)
                Text("Level \(s.level) · \(s.levelTitle)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFC233))
                HStack(spacing: 6) { ForEach(s.cups.prefix(3), id: \.name) { cupLink($0) } }
            }
        }
    }

    private func large(_ s: WidgetSnapshot, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            medium(s, colors).frame(height: 140)
            if let challenge = s.challenge {
                Label(challenge, systemImage: s.challengeDone ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(s.challengeDone ? Color(hex: 0x4BE38B) : .white)
            }
            Text("THIS WEEK").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(s.week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        StillBottle(progress: day.progress, colors: colors).frame(height: 54)
                        Text(day.letter).font(.system(size: 10, weight: day.isToday ? .heavy : .semibold, design: .rounded))
                        Image(systemName: day.met ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(day.met ? Color(hex: 0x4BE38B) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func streak(_ s: WidgetSnapshot) -> some View {
        Label("\(s.streak)", systemImage: "flame.fill")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0xFFB347))
    }

    private func cupLink(_ cup: WidgetSnapshot.Cup) -> some View {
        let name = cup.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cup.name
        return Link(destination: URL(string: "sip://log?cup=\(name)")!) {
            Label(cup.label, systemImage: cup.symbol)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
    }
}

struct SipStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.himanshudixit.sip.today", provider: SipProvider()) { entry in
            SipWidgetView(entry: entry)
        }
        .configurationDisplayName("Sip")
        .description("Today's water, your streak, and quick-add cups.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Control Center

/// Hands the action to Sip as a link; the app logs it (with its HUD).
@available(macOS 26.0, *)
struct OpenSipLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Sip Link"
    static let isDiscoverable = false

    @Parameter(title: "Link") var link: String

    init() {}
    init(_ link: String) { self.link = link }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: link) ?? URL(string: "sip://peek")!))
    }
}

@available(macOS 26.0, *)
struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.himanshudixit.sip.control.log") {
            ControlWidgetButton(action: OpenSipLinkIntent("sip://log")) {
                Label("Log Water", systemImage: "drop.fill")
            }
        }
        .displayName("Log Water")
        .description("Logs your default cup in Sip.")
    }
}

@available(macOS 26.0, *)
struct QuickLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.himanshudixit.sip.control.quicklog") {
            ControlWidgetButton(action: OpenSipLinkIntent("sip://quicklog")) {
                Label("Quick Log", systemImage: "text.cursor")
            }
        }
        .displayName("Sip Quick Log")
        .description("Opens Sip's quick-log box.")
    }
}

@main
struct SipWidgets: WidgetBundle {
    var body: some Widget {
        SipStatusWidget()
        if #available(macOS 26.0, *) {
            LogWaterControl()
            QuickLogControl()
        }
    }
}
