import Foundation

/// Turns an ingredient line into quantity, unit, name and preparation.
///
/// This is the seam every recipe comes through: typed into the manual entry
/// form, pulled from NYT Cooking's `recipeIngredient` strings, or read out of a
/// Mealime export. Section 1a names the failure to avoid: Mealime kept lines
/// like "1 bunch (about 1 pound) asparagus, tough ends removed" as raw text,
/// so they landed in Other and never merged with the same item from another
/// recipe.
///
/// It is deliberately conservative. Section 5.1 shows every parsed line for
/// confirmation and section 1a asks us to query only what we are unsure about,
/// so `confidence` is part of the output: a wrong answer stated confidently is
/// worse than an honest "look at this one".
///
/// Foundation only, so it is testable without a simulator.
enum ParseConfidence: String, Codable, Sendable, CaseIterable {
    /// Save it. Every piece of the line was accounted for.
    case high
    /// Usable, but something was guessed at. Show it on the review screen.
    case medium
    /// We got something out of it and a person should look.
    case low
}

struct ParsedIngredient: Equatable, Sendable {
    var quantity: Double?
    var unit: Unit?
    /// As written, per section 4, minus the quantity, unit and preparation.
    var name: String
    /// Whatever followed the first comma, or a participle that led the name.
    var preparation: String?
    /// A bracketed aside, usually a package size: "2 (15 oz) cans chickpeas".
    var parenthetical: String?
    var isOptional: Bool
    var confidence: ParseConfidence
    /// The line exactly as it arrived, so a review screen can show it.
    var raw: String
}

enum IngredientParser {

    // MARK: - Vocabulary

    /// Every spelling of a unit we expect to meet, mapped to section 4's set.
    /// Plurals and abbreviations included, because recipe writers use all of them.
    static let unitSpellings: [String: Unit] = [
        "tsp": .tsp, "tsps": .tsp, "t": .tsp, "teaspoon": .tsp, "teaspoons": .tsp,
        "tbsp": .tbsp, "tbsps": .tbsp, "tbs": .tbsp, "tb": .tbsp, "tablespoon": .tbsp, "tablespoons": .tbsp,
        "cup": .cup, "cups": .cup, "c": .cup,
        "floz": .floz, "fl oz": .floz, "fluid ounce": .floz, "fluid ounces": .floz,
        "oz": .oz, "ozs": .oz, "ounce": .oz, "ounces": .oz,
        "lb": .lb, "lbs": .lb, "pound": .lb, "pounds": .lb,
        "g": .g, "gram": .g, "grams": .g, "gramme": .g, "grammes": .g,
        "kg": .kg, "kgs": .kg, "kilogram": .kg, "kilograms": .kg,
        "ml": .ml, "milliliter": .ml, "milliliters": .ml, "millilitre": .ml, "millilitres": .ml,
        "l": .l, "liter": .l, "liters": .l, "litre": .l, "litres": .l,
        "pinch": .pinch, "pinches": .pinch,
        "clove": .clove, "cloves": .clove,
        "can": .can, "cans": .can, "tin": .can, "tins": .can,
        "bunch": .bunch, "bunches": .bunch,
        "package": .package, "packages": .package, "pkg": .package, "pkgs": .package,
        "packet": .package, "packets": .package, "container": .package, "containers": .package,
    ]

    /// Words that measure something but are not one of our sixteen units. We
    /// keep them in the name rather than inventing a unit, and say so by
    /// dropping confidence: a "head" of garlic is a real amount we did not
    /// capture.
    static let unmeasuredWords: Set<String> = [
        "head", "heads", "sprig", "sprigs", "stalk", "stalks", "ear", "ears",
        "slice", "slices", "strip", "strips", "piece", "pieces", "knob", "knobs",
        "sheet", "sheets", "fillet", "fillets", "rib", "ribs", "jar", "jars",
        "bottle", "bottles", "box", "boxes", "bag", "bags", "loaf", "loaves",
    ]

    /// Words that make a quantity no quantity at all.
    static let vagueWords: Set<String> = ["handful", "handfuls", "splash", "drizzle", "dash", "few", "some"]

    /// Things the cook does at the board. A leading one of these is
    /// preparation, not part of the ingredient's name.
    ///
    /// Words that also name a product are left out on purpose. "Toasted sesame
    /// seeds" and "toasted sesame oil" are things you buy, so stripping
    /// "toasted" would ask the shopper for the wrong item.
    static let preparationVerbs: Set<String> = [
        "chopped", "minced", "diced", "sliced", "grated", "shredded", "crushed",
        "julienned", "cubed", "halved", "quartered", "peeled", "trimmed",
        "beaten", "melted", "softened", "divided", "drained", "rinsed", "zested",
    ]

    /// Container units. A leading participle after one of these belongs to the
    /// product's name: "1 can diced tomatoes" is a tin of diced tomatoes, not
    /// a tin of tomatoes you then dice.
    static let containerUnits: Set<Unit> = [.can, .package, .bunch]

    private static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "¼": 0.25, "¾": 0.75,
        "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 1.0 / 6.0, "⅚": 5.0 / 6.0,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
    ]

    // MARK: - Parsing

    static func parse(_ line: String) -> ParsedIngredient {
        let raw = line
        var working = line.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var confidence = ParseConfidence.high

        guard !working.isEmpty else {
            return ParsedIngredient(quantity: nil, unit: nil, name: "", preparation: nil,
                                    parenthetical: nil, isOptional: false, confidence: .low, raw: raw)
        }

        let optional = stripOptional(&working)
        let parenthetical = stripParenthetical(&working)
        var preparation = stripTrailingPreparation(&working)

        var quantity: Double?
        if let reading = readQuantity(from: working) {
            quantity = reading.value
            working = String(working[reading.end...]).trimmingCharacters(in: .whitespaces)
            if reading.wasRange { confidence = confidence.lowered(to: .medium) }
        }

        var unit: Unit?
        if quantity != nil {
            let reading = readUnit(from: working)
            unit = reading.unit
            working = reading.remainder
            if reading.skippedTokens > 0 { confidence = confidence.lowered(to: .medium) }
            if reading.sawUnmeasuredWord { confidence = confidence.lowered(to: .medium) }
        }

        // A participle leading the name is preparation, unless the unit is a
        // container, where it is part of what you buy.
        if preparation == nil, !containerUnits.contains(unit ?? .count) {
            if let leading = stripLeadingPreparation(&working) {
                preparation = leading
                confidence = confidence.lowered(to: .medium)
            }
        }

        let name = working.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")).trimmingCharacters(in: .whitespaces)
        confidence = confidence.lowered(to: judge(name: name, quantity: quantity))

        return ParsedIngredient(
            quantity: quantity,
            unit: unit,
            name: name,
            preparation: preparation,
            parenthetical: parenthetical,
            isOptional: optional,
            confidence: confidence,
            raw: raw
        )
    }

    // MARK: - Pieces

    private static func stripOptional(_ text: inout String) -> Bool {
        var found = false
        let lower = text.lowercased()

        if lower.hasPrefix("optional:") || lower.hasPrefix("optional -") {
            text = String(text.dropFirst(lower.hasPrefix("optional:") ? 9 : 10)).trimmingCharacters(in: .whitespaces)
            found = true
        }
        for suffix in ["(optional)", ", optional", " optional"] where text.lowercased().hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            found = true
            break
        }
        return found
    }

    /// Takes the first bracketed aside out of the line so it cannot confuse the
    /// quantity or unit reading. "2 (15 oz) cans" becomes "2 cans" plus "15 oz".
    private static func stripParenthetical(_ text: inout String) -> String? {
        guard let open = text.firstIndex(of: "("),
              let close = text[open...].firstIndex(of: ")")
        else { return nil }

        let inside = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        text = (String(text[text.startIndex..<open]) + String(text[text.index(after: close)...]))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return inside.isEmpty ? nil : inside
    }

    /// Everything after the first comma. NYT writes preparation that way, and
    /// section 5.6a says so, so the whole tail is kept commas and all.
    private static func stripTrailingPreparation(_ text: inout String) -> String? {
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let tail = String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        text = String(text[text.startIndex..<comma]).trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? nil : tail
    }

    private static func stripLeadingPreparation(_ text: inout String) -> String? {
        var tokens = text.split(separator: " ").map(String.init)
        guard tokens.count > 1,
              preparationVerbs.contains(tokens[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",")))
        else { return nil }
        let verb = tokens.removeFirst()
        text = tokens.joined(separator: " ")
        return verb
    }

    private struct QuantityReading {
        let value: Double
        let end: String.Index
        let wasRange: Bool
    }

    /// Reads a leading quantity: 2, 1.5, 1/2, 1 1/2, ½, 1½, or a range.
    ///
    /// A range takes its lower bound. Buying too little is recoverable at the
    /// stove; buying too much is waste, and section 2 puts the shopper first.
    private static func readQuantity(from text: String) -> QuantityReading? {
        var index = text.startIndex
        var whole: Double?
        var total: Double?

        func skipSpaces() {
            while index < text.endIndex, text[index] == " " { index = text.index(after: index) }
        }

        // A leading vulgar fraction, possibly after a whole number.
        func readVulgar() -> Double? {
            guard index < text.endIndex, let value = vulgarFractions[text[index]] else { return nil }
            index = text.index(after: index)
            return value
        }

        func readDigits() -> Double? {
            var digits = ""
            // ASCII only. `Character.isNumber` is true for "½" too, so a
            // permissive loop swallows "1½" whole and then fails to read it,
            // which is how "1½ cups white rice" came back with no quantity.
            while index < text.endIndex, (text[index].isASCII && text[index].isNumber) || text[index] == "." {
                digits.append(text[index])
                index = text.index(after: index)
            }
            return digits.isEmpty ? nil : Double(digits)
        }

        if let fraction = readVulgar() {
            total = fraction
        } else if let first = readDigits() {
            whole = first
            if let fraction = readVulgar() {
                total = first + fraction
            } else {
                let afterWhole = index
                skipSpaces()
                if let numerator = readDigits() {
                    skipSpaces()
                    if index < text.endIndex, text[index] == "/" {
                        index = text.index(after: index)
                        skipSpaces()
                        if let denominator = readDigits(), denominator != 0 {
                            total = first + numerator / denominator
                        } else {
                            index = afterWhole
                            total = first
                        }
                    } else {
                        index = afterWhole
                        total = first
                    }
                } else if index < text.endIndex, text[index] == "/" {
                    index = text.index(after: index)
                    skipSpaces()
                    if let denominator = readDigits(), denominator != 0 {
                        total = first / denominator
                    } else {
                        index = afterWhole
                        total = first
                    }
                } else {
                    index = afterWhole
                    total = first
                }
            }
        }

        guard let value = total ?? whole else { return nil }

        // A range: keep the lower bound and step past the rest.
        var wasRange = false
        let afterNumber = index
        skipSpaces()
        let remainder = text[index...]
        for separator in ["-", "–", "—", "to "] where remainder.hasPrefix(separator) {
            var probe = text.index(index, offsetBy: separator.count)
            while probe < text.endIndex, text[probe] == " " { probe = text.index(after: probe) }
            var digits = ""
            var scan = probe
            while scan < text.endIndex,
                  (text[scan].isASCII && text[scan].isNumber) || text[scan] == "." || vulgarFractions[text[scan]] != nil {
                digits.append(text[scan])
                scan = text.index(after: scan)
            }
            if !digits.isEmpty {
                index = scan
                wasRange = true
            }
            break
        }
        if !wasRange { index = afterNumber }

        return QuantityReading(value: value, end: index, wasRange: wasRange)
    }

    private struct UnitReading {
        let unit: Unit?
        let remainder: String
        let skippedTokens: Int
        let sawUnmeasuredWord: Bool
    }

    /// Looks for a unit in the next few tokens. "2 15-ounce cans black beans"
    /// hides the unit behind a package size, so a strictly adjacent match would
    /// miss it, but wandering too far would swallow the name.
    private static func readUnit(from text: String) -> UnitReading {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return UnitReading(unit: nil, remainder: text, skippedTokens: 0, sawUnmeasuredWord: false) }

        // "fl oz" is the only two word spelling we accept.
        if tokens.count >= 2, unitSpellings["\(tokens[0].lowercased()) \(tokens[1].lowercased())"] != nil {
            let unit = unitSpellings["\(tokens[0].lowercased()) \(tokens[1].lowercased())"]
            return UnitReading(unit: unit, remainder: tokens.dropFirst(2).joined(separator: " "),
                               skippedTokens: 0, sawUnmeasuredWord: false)
        }

        let searchDepth = min(3, tokens.count)
        for position in 0..<searchDepth {
            let word = tokens[position].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if let unit = unitSpellings[word] {
                return UnitReading(unit: unit, remainder: tokens.dropFirst(position + 1).joined(separator: " "),
                                   skippedTokens: position, sawUnmeasuredWord: false)
            }
            // Stop at the first word that reads like part of the name, so a
            // unit further along belongs to something else.
            if position == 0, unmeasuredWords.contains(word) {
                return UnitReading(unit: nil, remainder: text, skippedTokens: 0, sawUnmeasuredWord: true)
            }
            if position > 0, !looksLikeSize(tokens[position - 1]) { break }
        }

        return UnitReading(unit: nil, remainder: text, skippedTokens: 0, sawUnmeasuredWord: false)
    }

    /// "15-ounce" and "14.5" read as package sizes rather than as the name.
    private static func looksLikeSize(_ token: String) -> Bool {
        token.contains(where: \.isNumber)
    }

    /// The last word on confidence, from what the name ended up being.
    private static func judge(name: String, quantity: Double?) -> ParseConfidence {
        if name.isEmpty { return .low }
        let lower = name.lowercased()

        // A number still in the name means the split went wrong somewhere.
        if name.contains(where: \.isNumber) { return .low }
        // Two ingredients on one line. We keep it whole rather than guess.
        if lower.contains(" and ") { return .low }
        if lower.split(separator: " ").contains(where: { vagueWords.contains(String($0)) }) { return .low }

        return .high
    }
}

private extension ParseConfidence {
    /// Confidence only ever falls. Any single doubt is the answer.
    func lowered(to other: ParseConfidence) -> ParseConfidence {
        let rank: [ParseConfidence: Int] = [.high: 2, .medium: 1, .low: 0]
        return (rank[self] ?? 0) <= (rank[other] ?? 0) ? self : other
    }
}
