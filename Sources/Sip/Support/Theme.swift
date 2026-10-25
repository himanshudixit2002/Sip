import SwiftUI
import SipCore

extension Color {
    /// 0xRRGGBB, for handing a colour to the system widget.
    var hexValue: Int {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8)
            | Int((c.blueComponent * 255).rounded())
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(rgb: (Double, Double, Double), alpha: Double = 1) {
        self.init(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: alpha)
    }
}

// MARK: - Liquid themes

enum LiquidTheme: String, CaseIterable, Identifiable, Codable {
    case ocean, lagoon, glacier, mint, grape, sunset, daylight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .lagoon: return "Lagoon"
        case .glacier: return "Glacier"
        case .mint: return "Mint"
        case .grape: return "Grape"
        case .sunset: return "Sunset"
        case .daylight: return "Daylight"
        }
    }

    /// Light at the surface, saturated in the middle, dark at depth.
    private var hexes: (UInt32, UInt32, UInt32) {
        switch self {
        case .ocean: return (0x8BE8FF, 0x2E9BFF, 0x1238B8)
        case .lagoon: return (0x9AF8E6, 0x1FC8C0, 0x0A6A80)
        case .glacier: return (0xEAFBFF, 0x9ED8FF, 0x4A8FE0)
        case .mint: return (0xCBF8D8, 0x3DD68C, 0x138A57)
        case .grape: return (0xE6CFFF, 0x9B6BFF, 0x4B22A8)
        case .sunset: return (0xFFD9A3, 0xFF8A5C, 0xC2366E)
        case .daylight:
            switch DaylightPhase.current {
            case .dawn: return (0xFFDDBE, 0xFF9E80, 0xA8487A)
            case .day: return (0x8BE8FF, 0x2E9BFF, 0x1238B8)
            case .dusk: return (0xFFC890, 0xE0749A, 0x5A2F8F)
            case .night: return (0xC4C0FF, 0x5B5BD6, 0x221C68)
            }
        }
    }

    var surface: Color { Color(hex: hexes.0) }
    var mid: Color { Color(hex: hexes.1) }
    var deep: Color { Color(hex: hexes.2) }

    var gradient: LinearGradient {
        LinearGradient(colors: [surface, mid, deep], startPoint: .top, endPoint: .bottom)
    }

    /// A horizontal version for progress bars.
    var barGradient: LinearGradient {
        LinearGradient(colors: [mid, surface], startPoint: .leading, endPoint: .trailing)
    }

    func color(for drink: DrinkKind) -> Color {
        if let rgb = drink.rgb { return Color(rgb: rgb) }
        return drink == .sparkling ? surface : mid
    }
}

/// The Daylight liquid follows the time of day.
enum DaylightPhase: Int {
    case dawn, day, dusk, night

    static var current: DaylightPhase { at(Date()) }

    static func at(_ date: Date) -> DaylightPhase {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9: return .dawn
        case 9..<17: return .day
        case 17..<21: return .dusk
        default: return .night
        }
    }
}

// MARK: - Appearance enums

enum IceMode: String, CaseIterable, Identifiable, Codable {
    case never, hotDays, always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .hotDays: return "On hot days"
        case .always: return "Always"
        }
    }
}

enum BottleStyle: String, CaseIterable, Identifiable, Codable {
    case classic, sport, carafe, tumbler, flask, jar, jug, lab, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .sport: return "Sport"
        case .carafe: return "Carafe"
        case .tumbler: return "Glass"
        case .flask: return "Steel Flask"
        case .jar: return "Mason Jar"
        case .jug: return "Gallon Jug"
        case .lab: return "Lab Flask"
        case .custom: return "Your Design"
        }
    }
}

/// The shape of "Your Design", from the bottle designer. All in the 100 × 220
/// design space.
struct CustomBottleSpec: Codable, Equatable, Hashable {
    /// Width of the body, 56–94.
    var bodyWidth: Double = 80
    /// 0 is a square shoulder, 1 a long, gentle one.
    var shoulder: Double = 0.5
    /// How far the waist pinches in, 0–10.
    var waist: Double = 0
    var neckWidth: Double = 28
    var neckHeight: Double = 22
    /// Corner radius at the base, 4–30.
    var baseRound: Double = 16
    var cap: CustomCap = .screw

    var key: String {
        [bodyWidth, shoulder, waist, neckWidth, neckHeight, baseRound].map { String(format: "%.2f", $0) }
            .joined(separator: ",") + cap.rawValue
    }
}

enum CustomCap: String, Codable, CaseIterable, Identifiable {
    case screw, flip, cork, lid, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .screw: return "Screw cap"
        case .flip: return "Flip lid"
        case .cork: return "Cork"
        case .lid: return "Jar lid"
        case .none: return "Open"
        }
    }
}

/// A faint colour in the glass itself.
enum GlassTint: String, Codable, CaseIterable, Identifiable {
    case clear, aqua, amber, rose, smoke, emerald
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color? {
        switch self {
        case .clear: return nil
        case .aqua: return Color(hex: 0x6FE3FF)
        case .amber: return Color(hex: 0xFFB347)
        case .rose: return Color(hex: 0xFF8FB1)
        case .smoke: return Color(hex: 0x8A93A6)
        case .emerald: return Color(hex: 0x4BE38B)
        }
    }
}

enum CardBackground: String, CaseIterable, Identifiable, Codable {
    case glass, clearGlass, frosted, solid, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "Liquid Glass"
        case .clearGlass: return "Clear Glass"
        case .frosted: return "Frosted"
        case .solid: return "Solid"
        case .none: return "None"
        }
    }

    static var systemDefault: CardBackground {
        if #available(macOS 26.0, *) { return .glass }
        return .frosted
    }

    /// Liquid Glass needs macOS 26; older systems fall back to Frosted.
    static var available: [CardBackground] {
        if #available(macOS 26.0, *) { return allCases }
        return [.frosted, .solid, .none]
    }
}

enum WidgetSize: String, CaseIterable, Identifiable, Codable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Card size before scaling, the same as the macOS widget sizes.
    var cardSize: CGSize {
        switch self {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 356, height: 170)
        case .large: return CGSize(width: 356, height: 376)
        case .extraLarge: return CGSize(width: 732, height: 376)
        }
    }
}

enum MotionLevel: String, CaseIterable, Identifiable, Codable {
    case full, calm, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full"
        case .calm: return "Calm"
        case .minimal: return "Minimal"
        }
    }

    var detail: String {
        switch self {
        case .full: return "Waves, bubbles, pours and splashes."
        case .calm: return "Gentler waves and fewer particles."
        case .minimal: return "Still water. Only the level moves."
        }
    }
}

enum Placement: String, CaseIterable, Identifiable, Codable {
    case desktop, floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "On desktop"
        case .floating: return "Floating"
        }
    }

    var detail: String {
        switch self {
        case .desktop: return "Sits on the wallpaper, behind your windows, like a system widget."
        case .floating: return "Stays above your windows."
        }
    }
}

enum ClickAction: String, CaseIterable, Identifiable, Codable {
    case addDefault, openPopover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addDefault: return "Log the default cup"
        case .openPopover: return "Open the quick-add menu"
        }
    }
}

// MARK: - Cups

struct Cup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amountML: Double
    var drink: DrinkKind
    var symbol: String

    init(id: UUID = UUID(), name: String, amountML: Double, drink: DrinkKind = .water, symbol: String) {
        self.id = id
        self.name = name
        self.amountML = amountML
        self.drink = drink
        self.symbol = symbol
    }

    static let defaults: [Cup] = [
        Cup(name: "Sip", amountML: 150, symbol: "drop.fill"),
        Cup(name: "Glass", amountML: 250, symbol: "cup.and.saucer.fill"),
        Cup(name: "Bottle", amountML: 500, symbol: "waterbottle.fill"),
        Cup(name: "Coffee", amountML: 200, drink: .coffee, symbol: "mug.fill"),
    ]

    static let symbolChoices = [
        "drop.fill", "cup.and.saucer.fill", "mug.fill", "waterbottle.fill",
        "wineglass.fill", "takeoutbag.and.cup.and.straw.fill", "bubbles.and.sparkles.fill",
        "bolt.heart.fill", "leaf.fill", "carrot.fill",
    ]
}

// MARK: - Streak flame tiers

enum FlameTier {
    case none, ember, gold, blue, cosmic

    init(streak: Int) {
        switch streak {
        case ..<1: self = .none
        case 1..<7: self = .ember
        case 7..<30: self = .gold
        case 30..<100: self = .blue
        default: self = .cosmic
        }
    }

    var colors: [Color] {
        switch self {
        case .none: return [Color.gray.opacity(0.6), Color.gray.opacity(0.4)]
        case .ember: return [Color(hex: 0xFFC94A), Color(hex: 0xFF6A2B), Color(hex: 0xE5342B)]
        case .gold: return [Color(hex: 0xFFF2A8), Color(hex: 0xFFC233), Color(hex: 0xFF8A1F)]
        case .blue: return [Color(hex: 0xD8F6FF), Color(hex: 0x5FD3FF), Color(hex: 0x2F6BFF)]
        case .cosmic: return [Color(hex: 0xFFD6FF), Color(hex: 0xC774FF), Color(hex: 0x6A3BFF)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var name: String {
        switch self {
        case .none: return "No streak"
        case .ember: return "Ember"
        case .gold: return "Gold flame"
        case .blue: return "Blue flame"
        case .cosmic: return "Cosmic flame"
        }
    }
}

/// Whether the menu bar icon shows. It's a small ring rather than a second
/// bottle, so by default it's always there as the way in to Sip.
enum MenuBarIconMode: String, CaseIterable, Identifiable, Codable {
    case always, automatic, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always"
        case .automatic: return "Only when the widget is hidden"
        case .never: return "Never"
        }
    }
}
