import XCTest
@testable import Mise

/// UnitConverter, driven from `Fixtures/unit_conversion.json`.
///
/// The fixture is the specification rather than a convenience: every expected
/// value in it is recomputed from its own multiplier table by
/// `tools/resource-lint`, which runs without a Swift toolchain. So the numbers
/// here were checked before this file ever compiled, and a failure below means
/// the Swift disagrees with a verified expectation rather than that two
/// unverified things disagree.
final class UnitConverterTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Conversion: Decodable {
            let note: String?
            let quantity: Double
            let from: Unit
            let to: Unit
            let expected: Double?
        }

        struct Combination: Decodable {
            let note: String?
            let input: [[Part]]
            let expected: [[Part]]
            let formatted: String?
        }

        struct Fraction: Decodable {
            let value: Double
            let expected: String
        }

        /// A `[quantity, unit]` pair, where the unit may be null.
        enum Part: Decodable {
            case number(Double)
            case unit(Unit?)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .unit(nil)
                } else if let value = try? container.decode(Double.self) {
                    self = .number(value)
                } else {
                    self = .unit(try container.decode(Unit.self))
                }
            }
        }

        let multipliers: [String: Double]
        let families: [String: [Unit]]
        let baseUnits: [String: Unit]
        let conversions: [Conversion]
        let combinations: [Combination]
        let fractions: [Fraction]
    }

    private static let fixtures: Fixtures = {
        let bundle = Bundle(for: UnitConverterTests.self)
        guard let url = bundle.url(forResource: "unit_conversion", withExtension: "json") else {
            fatalError("unit_conversion.json is not in the test bundle. Check that MiseTests/Fixtures is in the test target's resources.")
        }
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }()

    private func measurements(from parts: [[Fixtures.Part]]) -> [Measurement] {
        parts.map { pair in
            var quantity = 0.0
            var unit: Unit?
            for part in pair {
                switch part {
                case .number(let value): quantity = value
                case .unit(let value): unit = value
                }
            }
            return Measurement(quantity, unit)
        }
    }

    // MARK: - The table itself

    /// If these drift, every other expectation in the fixture is measuring the
    /// wrong thing, so check it first.
    func testMultipliersMatchTheFixture() {
        for (name, expected) in Self.fixtures.multipliers {
            guard let unit = Unit(rawValue: name) else {
                XCTFail("The fixture has a multiplier for \"\(name)\", which is not a Unit")
                continue
            }
            XCTAssertEqual(unit.baseMultiplier ?? .nan, expected, accuracy: 1e-6, "multiplier for \(name)")
        }
    }

    func testFamiliesMatchTheFixture() {
        for (name, units) in Self.fixtures.families {
            guard let family = UnitFamily(rawValue: name) else {
                XCTFail("The fixture has a family \"\(name)\" that does not exist")
                continue
            }
            for unit in units {
                XCTAssertEqual(unit.family, family, "\(unit.rawValue) should be \(name)")
            }
        }
    }

    func testDiscreteUnitsHaveNoMultiplier() {
        for unit in Unit.allCases where unit.family == .discrete {
            XCTAssertNil(unit.baseMultiplier, "\(unit.rawValue) is discrete and must not convert")
        }
    }

    func testEveryUnitIsCovered() {
        let covered = Set(Self.fixtures.families.values.flatMap { $0 })
        XCTAssertEqual(covered, Set(Unit.allCases), "the fixture must place every unit in a family")
    }

    // MARK: - Conversion

    func testConversions() {
        for entry in Self.fixtures.conversions {
            let actual = UnitConverter.convert(entry.quantity, from: entry.from, to: entry.to)
            let label = entry.note ?? "\(entry.quantity) \(entry.from.rawValue) to \(entry.to.rawValue)"

            guard let expected = entry.expected else {
                XCTAssertNil(actual, "\(label): should refuse to convert")
                continue
            }
            guard let actual else {
                XCTFail("\(label): expected \(expected) but the conversion was refused")
                continue
            }
            XCTAssertEqual(actual, expected, accuracy: 1e-3, label)
        }
    }

    func testCanConvertAgreesWithConvert() {
        for from in Unit.allCases {
            for to in Unit.allCases {
                XCTAssertEqual(
                    UnitConverter.canConvert(from: from, to: to),
                    UnitConverter.convert(1, from: from, to: to) != nil,
                    "canConvert and convert disagree for \(from.rawValue) to \(to.rawValue)"
                )
            }
        }
    }

    /// Converting out and back should land where it started, for every pair the
    /// converter claims to handle. This catches a multiplier that is wrong in a
    /// way the fixture's chosen examples happen to miss.
    func testConversionRoundTrips() {
        for from in Unit.allCases {
            for to in Unit.allCases where UnitConverter.canConvert(from: from, to: to) {
                guard let there = UnitConverter.convert(7.5, from: from, to: to),
                      let back = UnitConverter.convert(there, from: to, to: from)
                else {
                    XCTFail("round trip refused for \(from.rawValue) to \(to.rawValue)")
                    continue
                }
                XCTAssertEqual(back, 7.5, accuracy: 1e-6, "\(from.rawValue) to \(to.rawValue) and back")
            }
        }
    }

    func testNeverConvertsAcrossFamilies() {
        for from in Unit.allCases {
            for to in Unit.allCases where from.family != to.family {
                XCTAssertNil(
                    UnitConverter.convert(1, from: from, to: to),
                    "\(from.rawValue) to \(to.rawValue) crosses families and must be refused"
                )
            }
        }
    }

    // MARK: - Combining

    func testCombinations() {
        for entry in Self.fixtures.combinations {
            let input = measurements(from: entry.input)
            let expected = measurements(from: entry.expected)
            let actual = UnitConverter.combine(input)
            let label = entry.note ?? "combine \(input)"

            XCTAssertEqual(actual.count, expected.count, "\(label): wrong number of measurements")
            guard actual.count == expected.count else { continue }

            for (index, pair) in zip(actual, expected).enumerated() {
                XCTAssertEqual(pair.0.unit, pair.1.unit, "\(label): part \(index + 1) unit")
                XCTAssertEqual(pair.0.quantity, pair.1.quantity, accuracy: 1e-3, "\(label): part \(index + 1) quantity")
            }

            if let formatted = entry.formatted {
                XCTAssertEqual(UnitConverter.format(input), formatted, "\(label): formatted output")
            }
        }
    }

    /// Section 2 calls the grocery list the hero, and this is the property that
    /// makes it trustworthy: merging may change how a quantity is written, but
    /// never how much of it there is.
    func testCombiningConservesTheTotal() {
        let input = [Measurement(3, .tbsp), Measurement(2, .tsp), Measurement(0.25, .cup)]
        let combined = UnitConverter.combine(input)
        XCTAssertEqual(combined.count, 1)

        let before = input.reduce(0.0) { $0 + $1.quantity * ($1.unit?.baseMultiplier ?? 0) }
        let after = combined.reduce(0.0) { $0 + $1.quantity * ($1.unit?.baseMultiplier ?? 0) }
        XCTAssertEqual(after, before, accuracy: 0.5, "merging changed how much there is")
    }

    func testCombiningIsOrderStable() {
        let combined = UnitConverter.combine([Measurement(100, .g), Measurement(1, .cup)])
        XCTAssertEqual(combined.map(\.unit), [.g, .cup], "the first measurement should still lead")
    }

    // MARK: - Reading

    func testFractions() {
        for entry in Self.fixtures.fractions {
            XCTAssertEqual(UnitConverter.fraction(entry.value), entry.expected, "fraction of \(entry.value)")
        }
    }

    func testPluralizesOnlyWhereItReadsWell() {
        XCTAssertEqual(UnitConverter.format(Measurement(2, .cup)), "2 cups")
        XCTAssertEqual(UnitConverter.format(Measurement(1, .cup)), "1 cup")
        XCTAssertEqual(UnitConverter.format(Measurement(2, .tbsp)), "2 tbsp")
        XCTAssertEqual(UnitConverter.format(Measurement(2, .g)), "2 g")
        XCTAssertEqual(UnitConverter.format(Measurement(2, .can)), "2 cans")
        XCTAssertEqual(UnitConverter.format(Measurement(2, .count)), "2")
        XCTAssertEqual(UnitConverter.format(Measurement(2, nil)), "2")
    }
}
