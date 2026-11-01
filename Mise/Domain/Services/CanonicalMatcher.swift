import Foundation

/// Resolves an ingredient name to a canonical grocery item.
///
/// This is where the alias table earns its place. Section 5.3 rule 2 sets the
/// ladder: exact name, then alias, then fuzzy, and whatever is left goes to
/// aisle `other` and is flagged so the user can categorise it once, which
/// teaches the table for next time.
///
/// Everything downstream depends on this being right. Two ingredients only
/// merge on the list if they resolve to the same item, so a miss shows up as a
/// duplicated row, which is the Mealime failure section 1a complains about, and
/// a wrong hit shows up as the shopper buying the wrong thing, which is worse.
/// When the two risks conflict this leans towards flagging.
///
/// Foundation only, so it is testable without a simulator.
enum MatchReason: String, Codable, Sendable, CaseIterable {
    /// The ingredient is a canonical item's name.
    case exactName
    /// It is one of that item's aliases.
    case alias
    /// The user taught us this one by categorising it.
    case learned
    /// It matched once punctuation, plurals and descriptor words were handled.
    case normalized
    /// The canonical name's words all appear in the ingredient, head noun last.
    case contained
    /// Nothing matched.
    case none
}

/// A canonical item as the matcher needs it: a value type, so this file does
/// not import SwiftData and the matching logic stays portable.
struct CanonicalCandidate: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let aliases: [String]
    let aisle: Aisle
    let isStaple: Bool
    let defaultUnit: Unit?

    init(id: UUID, name: String, aliases: [String] = [], aisle: Aisle, isStaple: Bool = false, defaultUnit: Unit? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.aisle = aisle
        self.isStaple = isStaple
        self.defaultUnit = defaultUnit
    }
}

struct CanonicalMatch: Equatable, Sendable {
    let item: CanonicalCandidate?
    let reason: MatchReason
    let confidence: ParseConfidence

    /// Section 5.3: an ingredient that resolves to nothing still has to land
    /// somewhere, and that somewhere is `other`.
    var aisle: Aisle { item?.aisle ?? .other }

    /// Whether this is worth putting in front of the user. Only a hit we are
    /// sure of goes through silently.
    var needsReview: Bool { confidence != .high }
}

struct CanonicalMatcher: Sendable {

    private struct Entry: Sendable {
        let item: CanonicalCandidate
        /// The phrase this key came from, so the reason can tell an exact hit
        /// from a plural or a stripped descriptor.
        let source: String
        let reason: MatchReason
    }

    private let items: [CanonicalCandidate]
    private let index: [String: Entry]

    /// - Parameter learnedAliases: phrases the user has already categorised,
    ///   mapped to the item they chose. Section 5.3 calls this teaching the
    ///   alias table.
    init(items: [CanonicalCandidate], learnedAliases: [String: UUID] = [:]) {
        self.items = items

        var index: [String: Entry] = [:]
        func add(_ phrase: String, _ item: CanonicalCandidate, _ reason: MatchReason) {
            for key in Self.keys(for: phrase) where index[key] == nil {
                index[key] = Entry(item: item, source: phrase, reason: reason)
            }
        }

        func addExact(_ phrase: String, _ item: CanonicalCandidate, _ reason: MatchReason) {
            let key = Self.normalize(phrase)
            if !key.isEmpty, index[key] == nil {
                index[key] = Entry(item: item, source: phrase, reason: reason)
            }
        }

        // Spellings that are written out come first, then the plurals and
        // singulars generated from them. Otherwise a plural derived from a name
        // claims the key before the alias that spells it out, and "lemons"
        // reports as a variant of "lemon" rather than as the alias it is.
        //
        // Names beat aliases at each stage. The resource linter already refuses
        // a table where the two overlap, so this only orders, never discards.
        for item in items { addExact(item.name, item, .exactName) }
        for item in items {
            for alias in item.aliases { addExact(alias, item, .alias) }
        }
        for item in items { add(item.name, item, .exactName) }
        for item in items {
            for alias in item.aliases { add(alias, item, .alias) }
        }

        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (phrase, id) in learnedAliases {
            guard let item = byID[id] else { continue }
            add(phrase, item, .learned)
        }

        self.index = index
    }

    /// Returns a matcher that also knows this phrase, for when the user has
    /// just categorised something. Value semantics, so nothing mutates under a
    /// caller that is mid-generation.
    func teaching(_ phrase: String, as itemID: UUID) -> CanonicalMatcher {
        var learned: [String: UUID] = [:]
        for (key, entry) in index where entry.reason == .learned {
            learned[entry.source] = entry.item.id
            _ = key
        }
        learned[phrase] = itemID
        return CanonicalMatcher(items: items, learnedAliases: learned)
    }

    func match(_ ingredientName: String) -> CanonicalMatch {
        let normalized = Self.normalize(ingredientName)
        guard !normalized.isEmpty else {
            return CanonicalMatch(item: nil, reason: .none, confidence: .low)
        }

        // 1 and 2: the ingredient is a name, an alias, or something the user
        // already taught us.
        if let entry = index[normalized] {
            // A hit through a plural or a variant spelling is still a hit, but
            // it is not the same claim as the phrase being written out.
            let wroteItOut = normalized == Self.normalize(entry.source)
            return CanonicalMatch(
                item: entry.item,
                reason: wroteItOut ? entry.reason : .normalized,
                confidence: .high
            )
        }

        // 3: the same thing with the descriptor words taken off.
        let stripped = Self.withoutDescriptors(ingredientName)
        if !stripped.isEmpty, stripped != normalized, let entry = index[stripped] {
            return CanonicalMatch(item: entry.item, reason: .normalized, confidence: .high)
        }

        // 4: the fuzzy rung.
        if let contained = bestContainment(for: ingredientName) {
            return CanonicalMatch(item: contained, reason: .contained, confidence: .medium)
        }

        return CanonicalMatch(item: nil, reason: .none, confidence: .low)
    }

    /// Resolves a batch, which is what the list generator actually needs.
    func match(all names: [String]) -> [CanonicalMatch] {
        names.map(match)
    }

    // MARK: - Containment

    /// Every word of the canonical name appears in the ingredient, and both end
    /// on the same word.
    ///
    /// The head noun check is the whole guard. Without it "milk chocolate"
    /// resolves to milk, because the word is right there, and the shopper comes
    /// home with the wrong thing. English food names put the thing last.
    private func bestContainment(for ingredientName: String) -> CanonicalCandidate? {
        let inputWords = Self.tokens(ingredientName)
        guard let inputLast = inputWords.last else { return nil }

        let inputForms = Set(inputWords.flatMap(Self.variants))
        let lastForms = Set(Self.variants(inputLast))

        var best: CanonicalCandidate?
        var bestWordCount = 0
        var bestExtra = Int.max

        for item in items {
            let nameWords = Self.tokens(item.name)
            guard let nameLast = nameWords.last, !nameWords.isEmpty else { continue }
            guard Self.variants(nameLast).contains(where: lastForms.contains) else { continue }
            guard nameWords.allSatisfy({ word in Self.variants(word).contains(where: inputForms.contains) }) else { continue }

            // Prefer the most specific item, so "coconut milk" beats "milk".
            let extra = inputWords.count - nameWords.count
            if nameWords.count > bestWordCount || (nameWords.count == bestWordCount && extra < bestExtra) {
                best = item
                bestWordCount = nameWords.count
                bestExtra = extra
            }
        }

        return best
    }

    // MARK: - Normalizing

    /// Words that describe a thing without changing which thing it is. A large
    /// lemon is a lemon.
    static let descriptors: Set<String> = [
        "large", "medium", "small", "extra", "jumbo", "mini", "baby",
        "fresh", "freshly", "ripe", "good", "quality", "organic", "raw",
        // State, not identity. A recipe calling for cooked rice still sends
        // you to the shelf for rice.
        "cooked", "uncooked", "leftover",
    ]

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Naive singular and plural, enough to bridge "carrot" and "carrots"
    /// without pulling in a stemmer that would also turn "molasses" into
    /// "molasse".
    static func variants(_ word: String) -> [String] {
        var out: Set<String> = [word]
        if word.hasSuffix("ies"), word.count > 4 { out.insert(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("es"), word.count > 3 { out.insert(String(word.dropLast(2))) }
        if word.hasSuffix("s"), word.count > 2 { out.insert(String(word.dropLast())) }
        out.insert(word + "s")
        out.insert(word + "es")
        return Array(out)
    }

    /// Every spelling of a phrase we treat as the same phrase. Only the last
    /// word is varied, because that is the one carrying the plural.
    static func keys(for phrase: String) -> [String] {
        let words = tokens(phrase)
        guard let last = words.last else { return [] }
        let head = words.dropLast()
        return variants(last).map { (head + [$0]).joined(separator: " ") }
    }

    static func withoutDescriptors(_ phrase: String) -> String {
        tokens(phrase).filter { !descriptors.contains($0) }.joined(separator: " ")
    }
}
