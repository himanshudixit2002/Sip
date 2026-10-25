import AppKit
import SwiftUI
import SipCore

/// A square image of your week to share: the bottle, your streak, the last
/// seven days and a few numbers. Rendered off-screen, then saved or copied.
struct ShareCardView: View {
    let state: AppState

    var body: some View {
        let store = state.store
        let settings = state.settings
        let theme = settings.theme
        let unit = settings.unit
        let days = store.recentDays(7)
        let week = WeeklySummary(summaries: store.summaries, last: store.today, streak: store.streak.current)
        let tier = FlameTier(streak: store.streak.current)

        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1A3D), theme.deep.opacity(0.9), Color(hex: 0x050B1C)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.mid.opacity(0.45), .clear], center: .init(x: 0.28, y: 0.42),
                           startRadius: 10, endRadius: 520)

            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 14) {
                    Image(systemName: "drop.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(theme.gradient)
                    Text("My week in water")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(Date().formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack(alignment: .center, spacing: 48) {
                    // The week's average, so an early-morning card isn't an empty bottle.
                    MiniBottle(style: settings.bottleStyle, fraction: min(week.averageML / max(store.goal, 1), 1),
                               theme: theme, highlighted: true, custom: settings.customBottle)
                        .frame(width: 230, height: 470)
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 14) {
                            Image(systemName: "flame.fill").font(.system(size: 64)).foregroundStyle(tier.gradient)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(store.streak.current)")
                                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                                Text("day streak")
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        stat("Goal hit", "\(week.metDays) of 7 days")
                        stat("Per day", Volume.formatCompact(week.averageML, unit))
                        stat("This week", Volume.formatCompact(week.totalML, unit))
                    }
                }

                HStack(alignment: .bottom, spacing: 22) {
                    ForEach(days) { day in
                        VStack(spacing: 10) {
                            MiniBottle(style: settings.bottleStyle, fraction: day.progress, theme: theme,
                                       highlighted: day.key == store.today, custom: settings.customBottle)
                                .frame(width: 70, height: 128)
                            Text(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(day.key.weekday - 1) % 7])
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                            Image(systemName: day.met ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(day.met ? Palette.goal : .white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Text("Tracked with Sip")
                    Spacer()
                    Text("Best streak \(store.streak.best)")
                }
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(70)
            .foregroundStyle(.white)
        }
        .frame(width: 1080, height: 1080)
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
        }
    }

    // MARK: Export

    @MainActor
    static func pngData(state: AppState) -> Data? { ImageExport.png(ShareCardView(state: state)) }

    /// Asks where to save, then reveals the file.
    @MainActor
    static func save(state: AppState) {
        ImageExport.save(ShareCardView(state: state),
                         name: "Sip week \(Date().formatted(.dateTime.day().month(.abbreviated))).png")
    }

    @MainActor
    static func copy(state: AppState) -> Bool { ImageExport.copy(ShareCardView(state: state)) }
}

/// Saving and copying the shareable images (the week card and the recap).
@MainActor
enum ImageExport {
    static func png<V: View>(_ view: V) -> Data? {
        guard let cg = renderCGImage(view, scale: 1) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    static func save<V: View>(_ view: V, name: String) {
        guard let data = png(view) else { return }
        Modal.save(name: name, types: [.png]) { try data.write(to: $0) }
    }

    static func copy<V: View>(_ view: V) -> Bool {
        guard let cg = renderCGImage(view, scale: 1) else { return false }
        Clipboard.copy(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        return true
    }
}
