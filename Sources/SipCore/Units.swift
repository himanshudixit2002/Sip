import Foundation

public enum VolumeUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case milliliters
    case fluidOunces

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .milliliters: return "ml"
        case .fluidOunces: return "oz"
        }
    }

    public var title: String {
        switch self {
        case .milliliters: return "Millilitres"
        case .fluidOunces: return "US fluid ounces"
        }
    }
}

/// Everything is stored in millilitres. Conversion happens only at the edges,
/// when a number is shown or typed.
public enum Volume {
    public static let mlPerFluidOunce = 29.5735295625

    public static func toDisplay(_ ml: Double, _ unit: VolumeUnit) -> Double {
        unit == .milliliters ? ml : ml / mlPerFluidOunce
    }

    public static func fromDisplay(_ value: Double, _ unit: VolumeUnit) -> Double {
        unit == .milliliters ? value : value * mlPerFluidOunce
    }

    /// The rounded number shown for an amount: whole millilitres, or ounces to
    /// the nearest whole ounce.
    public static func displayNumber(_ ml: Double, _ unit: VolumeUnit) -> Int {
        Int(toDisplay(ml, unit).rounded())
    }

    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let litres: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// "1,250 ml" or "42 oz".
    public static func format(_ ml: Double, _ unit: VolumeUnit) -> String {
        let n = NSNumber(value: displayNumber(ml, unit))
        return "\(grouped.string(from: n) ?? "\(n)") \(unit.label)"
    }

    /// Compact form for tight spaces: "1.25 L", "750 ml", "42 oz".
    public static func formatCompact(_ ml: Double, _ unit: VolumeUnit) -> String {
        if unit == .milliliters, abs(ml) >= 1000 {
            let value = (ml / 10).rounded() / 100
            return "\(litres.string(from: NSNumber(value: value)) ?? "\(value)") L"
        }
        return format(ml, unit)
    }

    /// Graduation label on the bottle: "500", "1L", "1.5L", "16".
    public static func tickLabel(_ ml: Double, _ unit: VolumeUnit) -> String {
        if unit == .fluidOunces { return "\(displayNumber(ml, unit))" }
        if ml >= 1000 {
            let value = (ml / 100).rounded() / 10
            return value == value.rounded() ? "\(Int(value))L" : "\(value)L"
        }
        return "\(Int(ml.rounded()))"
    }

    /// Rounds a typed or dragged amount to a pleasant step: 10 ml, or 1 oz.
    public static func snap(_ ml: Double, _ unit: VolumeUnit) -> Double {
        switch unit {
        case .milliliters: return (ml / 10).rounded() * 10
        case .fluidOunces: return fromDisplay(toDisplay(ml, unit).rounded(), unit)
        }
    }
}
