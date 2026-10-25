import Foundation

/// A quick-add cup as the parser sees it.
public struct QuickLogCup: Equatable, Sendable {
    public var name: String
    public var ml: Double
    public var drink: DrinkKind

    public init(name: String, ml: Double, drink: DrinkKind) {
        self.name = name
        self.ml = ml
        self.drink = drink
    }
}

public struct ParsedLog: Equatable, Sendable {
    public var ml: Double
    public var drink: DrinkKind?
}

/// Understands what you'd type into the quick-log box:
///
/// - `330`, `330 tea`, `tea 330` — a bare number is in your display unit
/// - `1.5l`, `500 ml`, `33 cl`, `12 oz coffee`
/// - `glass`, `bottle of juice`, `2 glasses`, `half a bottle`, `coffee`
public enum QuickLogParser {
    private static let drinkWords: [(String, DrinkKind)] = [
        ("sparkling", .sparkling), ("soda", .sparkling), ("fizzy", .sparkling),
        ("water", .water), ("tea", .tea), ("chai", .tea), ("coffee", .coffee), ("espresso", .coffee),
        ("latte", .coffee), ("milk", .milk), ("juice", .juice), ("electrolyte", .electrolyte),
        ("ors", .electrolyte), ("sports", .electrolyte),
    ]

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "half": 0.5, "quarter": 0.25,
    ]

    public static func parse(_ input: String, cups: [QuickLogCup], unit: VolumeUnit) -> ParsedLog? {
        let text = input.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Split "330ml" and "1.5l" into number and unit.
        var tokens: [String] = []
        for word in text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) {
            if let range = word.range(of: #"^[0-9]*\.?[0-9]+"#, options: .regularExpression), range.upperBound < word.endIndex {
                tokens.append(String(word[range]))
                tokens.append(String(word[range.upperBound...]))
            } else {
                tokens.append(word)
            }
        }

        var number: Double?
        var unitML: Double?
        var drink: DrinkKind?
        var cup: QuickLogCup?
        var multiplier: Double = 1

        for token in tokens {
            if let value = Double(token) {
                number = value
                continue
            }
            switch token {
            case "ml", "mls", "millilitre", "millilitres", "milliliter", "milliliters": unitML = 1; continue
            case "cl": unitML = 10; continue
            case "l", "lt", "litre", "litres", "liter", "liters": unitML = 1000; continue
            case "oz", "ounce", "ounces", "floz": unitML = Volume.mlPerFluidOunce; continue
            case "x", "of", "cup", "cups", "my", "the", "some", "and": continue
            default: break
            }
            if let word = numberWords[token] {
                // "a glass" is one glass; "half a bottle", "two glasses" scale it.
                if token != "a" && token != "an" { multiplier = word }
                continue
            }
            if let match = drinkWords.first(where: { token.hasPrefix($0.0) }) {
                drink = match.1
                continue
            }
            // "glasses" → "glass", "bottles" → "bottle".
            var forms = [token]
            if token.hasSuffix("es") { forms.append(String(token.dropLast(2))) }
            if token.hasSuffix("s") { forms.append(String(token.dropLast())) }
            if let found = cups.first(where: { forms.contains($0.name.lowercased()) }) {
                cup = found
                continue
            }
            return nil   // a word we don't understand
        }

        if let number {
            if let cup, unitML == nil {
                // "2 glasses": a count, not a volume.
                return ParsedLog(ml: cup.ml * number, drink: drink ?? cup.drink)
            }
            let perUnit = unitML ?? (unit == .milliliters ? 1 : Volume.mlPerFluidOunce)
            let ml = number * perUnit * multiplier
            guard ml >= 1, ml <= 5000 else { return nil }
            return ParsedLog(ml: ml, drink: drink)
        }
        if let cup {
            return ParsedLog(ml: cup.ml * multiplier, drink: drink ?? cup.drink)
        }
        if let drink {
            // "coffee": the first cup of that drink, else a standard 250 ml.
            let match = cups.first { $0.drink == drink }
            return ParsedLog(ml: (match?.ml ?? 250) * multiplier, drink: drink)
        }
        return nil
    }
}
