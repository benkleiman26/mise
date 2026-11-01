import Foundation

/// Conversions between the unit set in spec section 4.
///
/// Two rules carry the weight, and both exist to stop the grocery list lying:
///
/// 1. Convert only inside a family. Volume to volume and mass to mass are safe
///    arithmetic. Cups to grams is not: it depends on what is in the cup, and a
///    list that says "400 g flour" when the recipes asked for three cups is
///    worse than one that says "3 cups".
/// 2. When two quantities cannot be added, keep both rather than picking one.
///    Section 4 spells the result out: "1 cup + 2 tbsp".
///
/// Foundation only, no SwiftData and no SwiftUI, so this stays testable without
/// a simulator and portable if the domain services ever move to a package.
enum UnitFamily: String, Codable, Sendable {
    /// Teaspoons through litres. Freely convertible among themselves.
    case volume
    /// Ounces through kilograms.
    case mass
    /// Things you count rather than measure: cans, bunches, cloves. A can is
    /// not half a bunch, so these only ever add to their own unit.
    case discrete
}

extension Unit {
    var family: UnitFamily {
        switch self {
        case .tsp, .tbsp, .cup, .floz, .ml, .l: .volume
        case .oz, .lb, .g, .kg: .mass
        case .count, .pinch, .clove, .can, .bunch, .package: .discrete
        }
    }

    /// How many of the family's base unit this is: millilitres for volume,
    /// grams for mass. Discrete units have no base, which is the point.
    ///
    /// US customary, since section 4 sets US as the default and these are the
    /// legal definitions rather than rounded kitchen approximations.
    var baseMultiplier: Double? {
        switch self {
        case .ml: 1
        case .l: 1000
        case .tsp: 4.928922
        case .tbsp: 14.786765
        case .floz: 29.573530
        case .cup: 236.588236
        case .g: 1
        case .kg: 1000
        case .oz: 28.349523
        case .lb: 453.592370
        case .count, .pinch, .clove, .can, .bunch, .package: nil
        }
    }

    /// What a shopper reads on the list. Discrete units are pluralized by
    /// `Quantity.formatted`, so these are the singular forms.
    var abbreviation: String {
        switch self {
        case .count: ""
        case .tsp: "tsp"
        case .tbsp: "tbsp"
        case .cup: "cup"
        case .floz: "fl oz"
        case .oz: "oz"
        case .lb: "lb"
        case .g: "g"
        case .kg: "kg"
        case .ml: "ml"
        case .l: "l"
        case .pinch: "pinch"
        case .clove: "clove"
        case .can: "can"
        case .bunch: "bunch"
        case .package: "package"
        }
    }

    /// Units that read naturally in the plural on a grocery list. "2 cups" and
    /// "2 cans" are right; "2 tbsps" and "2 gs" are not.
    var pluralizes: Bool {
        switch self {
        case .cup, .pinch, .clove, .can, .bunch, .package: true
        case .count, .tsp, .tbsp, .floz, .oz, .lb, .g, .kg, .ml, .l: false
        }
    }
}

/// A quantity with an optional unit. `unit` is nil for a line like "2 eggs",
/// where the number stands on its own.
struct Quantity: Equatable, Sendable {
    var quantity: Double
    var unit: Unit?

    init(_ quantity: Double, _ unit: Unit? = nil) {
        self.quantity = quantity
        self.unit = unit
    }
}

enum UnitConverter {
    /// Rounding floor. Quantities below this are treated as zero, so floating
    /// point noise from a chain of conversions never shows up as "0.0000001 g".
    static let epsilon = 1e-9

    // MARK: - Converting

    static func canConvert(from: Unit, to: Unit) -> Bool {
        from == to || (from.baseMultiplier != nil && from.family == to.family)
    }

    /// Returns nil when the conversion would be a guess: across families, or
    /// involving a discrete unit that is not the same unit.
    static func convert(_ quantity: Double, from: Unit, to: Unit) -> Double? {
        if from == to { return quantity }
        guard let fromBase = from.baseMultiplier,
              let toBase = to.baseMultiplier,
              from.family == to.family
        else { return nil }
        return quantity * fromBase / toBase
    }

    // MARK: - Combining

    /// Adds up what can be added and keeps the rest.
    ///
    /// This is what section 5.3 rule 3 asks for: merge identical canonical items
    /// across recipes, summing when the units are in one family and listing both
    /// when they are not. The result is ordered so the biggest measurement leads,
    /// because that is the one the shopper acts on.
    static func combine(_ measurements: [Quantity]) -> [Quantity] {
        guard !measurements.isEmpty else { return [] }

        // One bucket per thing that can legally be added together: each volume
        // group merges, each mass group merges, and every discrete unit stands
        // alone. A nil unit is its own bucket too.
        var buckets: [BucketKey: [Quantity]] = [:]
        var order: [BucketKey] = []
        for measurement in measurements {
            let key = BucketKey(measurement.unit)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(measurement)
        }

        return order.compactMap { key in
            guard let group = buckets[key] else { return nil }
            return merge(group)
        }
    }

    /// Renders a combined result the way section 4 asks: "1 cup + 2 tbsp".
    static func format(_ measurements: [Quantity]) -> String {
        combine(measurements).map(format).joined(separator: " + ")
    }

    static func format(_ measurement: Quantity) -> String {
        let amount = fraction(measurement.quantity)
        guard let unit = measurement.unit, unit != .count else { return amount }
        let name = unit.abbreviation
        let plural = unit.pluralizes && measurement.quantity > 1 + epsilon ? "\(name)s" : name
        return "\(amount) \(plural)"
    }

    // MARK: - Private

    private struct BucketKey: Hashable {
        let family: UnitFamily?
        /// Set only for discrete units, so a can never merges with a bunch.
        let discreteUnit: Unit?

        init(_ unit: Unit?) {
            guard let unit else {
                family = nil
                discreteUnit = nil
                return
            }
            family = unit.family
            discreteUnit = unit.family == .discrete ? unit : nil
        }
    }

    /// Sums one bucket into a single measurement, expressed in the largest unit
    /// present that still leaves a quantity of at least one. A shopper reading
    /// "1 1/4 cups" is better served than one reading "20 tbsp".
    private static func merge(_ group: [Quantity]) -> Quantity {
        guard let first = group.first else { return Quantity(0) }
        guard group.count > 1 else { return first }

        guard let unit = first.unit, let _ = unit.baseMultiplier else {
            // Discrete, or no unit: every member shares the unit by construction.
            return Quantity(group.reduce(0) { $0 + $1.quantity }, first.unit)
        }

        let total = group.reduce(0.0) { sum, measurement in
            guard let measurementUnit = measurement.unit,
                  let base = measurementUnit.baseMultiplier
            else { return sum }
            return sum + measurement.quantity * base
        }

        let candidates = group
            .compactMap(\.unit)
            .filter { $0.baseMultiplier != nil }
            .sorted { ($0.baseMultiplier ?? 0) > ($1.baseMultiplier ?? 0) }

        for candidate in candidates {
            guard let base = candidate.baseMultiplier else { continue }
            let amount = total / base
            if amount >= 1 - epsilon { return Quantity(round(amount), candidate) }
        }

        // Everything rounds below one, so use the smallest unit present.
        let smallest = candidates.last ?? unit
        let base = smallest.baseMultiplier ?? 1
        return Quantity(round(total / base), smallest)
    }

    /// Rounds away floating point dust without rounding away real quantities.
    private static func round(_ value: Double) -> Double {
        let scaled = (value * 10_000).rounded() / 10_000
        return abs(scaled) < epsilon ? 0 : scaled
    }

    // MARK: - Reading

    /// Cooking fractions, so a list says "1 1/2 lb" rather than "1.5 lb".
    /// Only the fractions a measuring cup actually has.
    private static let fractions: [(value: Double, text: String)] = [
        (1.0 / 8.0, "1/8"), (1.0 / 4.0, "1/4"), (1.0 / 3.0, "1/3"), (1.0 / 2.0, "1/2"),
        (2.0 / 3.0, "2/3"), (3.0 / 4.0, "3/4"),
    ]

    static func fraction(_ quantity: Double) -> String {
        let rounded = round(quantity)
        guard rounded > 0 else { return "0" }

        let whole = floor(rounded + epsilon)
        let remainder = rounded - whole

        if remainder < 0.01 {
            return String(Int(whole))
        }
        for candidate in fractions where abs(remainder - candidate.value) < 0.02 {
            return whole > 0 ? "\(Int(whole)) \(candidate.text)" : candidate.text
        }
        // Not a kitchen fraction, so show a decimal rather than invent one.
        let text = String(format: "%.2f", rounded)
        return text.hasSuffix("0") ? String(text.dropLast()) : text
    }
}
