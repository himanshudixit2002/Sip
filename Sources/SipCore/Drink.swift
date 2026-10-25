import Foundation

public enum DrinkKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case water
    case sparkling
    case tea
    case coffee
    case milk
    case juice
    case electrolyte

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: return "Water"
        case .sparkling: return "Sparkling"
        case .tea: return "Tea"
        case .coffee: return "Coffee"
        case .milk: return "Milk"
        case .juice: return "Juice"
        case .electrolyte: return "Electrolyte"
        }
    }

    /// How much of the volume counts toward hydration. These are conservative
    /// defaults, and every one of them can be changed in Settings.
    public var defaultHydrationFactor: Double {
        switch self {
        case .water, .sparkling, .electrolyte: return 1.0
        case .tea, .milk: return 0.9
        case .juice: return 0.85
        case .coffee: return 0.8
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .water: return "drop.fill"
        case .sparkling: return "bubbles.and.sparkles.fill"
        case .tea: return "cup.and.saucer.fill"
        case .coffee: return "mug.fill"
        case .milk: return "drop.halffull"
        case .juice: return "takeoutbag.and.cup.and.straw.fill"
        case .electrolyte: return "bolt.heart.fill"
        }
    }

    /// Water and sparkling take the liquid theme's colour; everything else has
    /// its own so a layered bottle reads at a glance.
    public var rgb: (Double, Double, Double)? {
        switch self {
        case .water, .sparkling: return nil
        case .tea: return (0.80, 0.55, 0.22)
        case .coffee: return (0.45, 0.29, 0.18)
        case .milk: return (0.95, 0.93, 0.89)
        case .juice: return (1.00, 0.62, 0.11)
        case .electrolyte: return (0.42, 0.92, 0.55)
        }
    }

    /// Carbonated drinks fizz more in the bottle.
    public var isCarbonated: Bool { self == .sparkling }
}

/// Per-drink hydration factors, with defaults for any kind not overridden.
public struct HydrationFactors: Codable, Equatable, Sendable {
    public var overrides: [DrinkKind: Double]

    public init(overrides: [DrinkKind: Double] = [:]) {
        self.overrides = overrides
    }

    public subscript(kind: DrinkKind) -> Double {
        get { overrides[kind] ?? kind.defaultHydrationFactor }
        set { overrides[kind] = min(max(newValue, 0), 1.5) }
    }
}

public struct Entry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var amountML: Double
    public var drink: DrinkKind

    public init(id: UUID = UUID(), date: Date, amountML: Double, drink: DrinkKind = .water) {
        self.id = id
        self.date = date
        self.amountML = amountML
        self.drink = drink
    }

    public func effectiveML(_ factors: HydrationFactors) -> Double {
        amountML * factors[drink]
    }
}
