import Foundation

/// Reads a recipe out of a web page, the way Mealime's "import from a link"
/// did.
///
/// Almost every recipe site publishes schema.org Recipe as JSON-LD in the page,
/// because Google requires it to show the rich result. That is the contract
/// this leans on, and it is the same one `tools/nyt-import` uses for the NYT
/// library. Scraping the rendered page is deliberately not attempted: it
/// produces something that looks like a recipe and is full of navigation text,
/// which is the exact failure the owner's Mealime library already carries
/// twenty lines of.
///
/// Parsing is separate from fetching so the hard part is testable without a
/// network.
enum RecipeWebImporter {

    enum LinkError: LocalizedError {
        case notAWebAddress
        case couldNotReach(String)
        case noRecipeInPage
        case emptyRecipe

        var errorDescription: String? {
            switch self {
            case .notAWebAddress:
                return "That does not look like a web address."
            case .couldNotReach(let detail):
                return "That page could not be opened. \(detail)"
            case .noRecipeInPage:
                return "No recipe was found on that page. Sites behind a paywall or a sign in usually will not work, and neither will a link to a list of recipes rather than to one."
            case .emptyRecipe:
                return "That page has a recipe on it with no ingredients and no method."
            }
        }
    }

    // MARK: - Fetching

    static func load(_ address: String, using session: URLSession = .shared) async throws -> RecipeImporter.ImportedRecipe {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: withScheme), let host = url.host(), host.contains(".") else {
            throw LinkError.notAWebAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        // Some sites serve a stub to anything that does not look like a
        // browser. This is the same request Safari would make.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LinkError.couldNotReach(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinkError.couldNotReach("The site answered \(http.statusCode).")
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        guard let recipe = parse(html: html, from: url) else { throw LinkError.noRecipeInPage }
        guard !recipe.ingredientLines.isEmpty || !recipe.steps.isEmpty else { throw LinkError.emptyRecipe }
        return recipe
    }

    // MARK: - Parsing

    /// The recipe in a page, or nil. Pure, so the awkward cases are tests
    /// rather than a site that has to be live to try.
    static func parse(html: String, from url: URL?) -> RecipeImporter.ImportedRecipe? {
        for block in jsonLDBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let recipe = findRecipe(in: any)
            else { continue }
            return build(from: recipe, url: url)
        }
        return nil
    }

    /// The contents of every `<script type="application/ld+json">`.
    static func jsonLDBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var remainder = Substring(html)

        while let openTag = remainder.range(of: "<script", options: .caseInsensitive) {
            let afterOpen = remainder[openTag.upperBound...]
            guard let headEnd = afterOpen.firstIndex(of: ">") else { break }

            let attributes = afterOpen[..<headEnd].lowercased()
            let body = afterOpen[afterOpen.index(after: headEnd)...]

            guard let closeTag = body.range(of: "</script", options: .caseInsensitive) else { break }

            if attributes.contains("application/ld+json") {
                blocks.append(String(body[..<closeTag.lowerBound]))
            }
            remainder = body[closeTag.upperBound...]
        }
        return blocks
    }

    /// A Recipe node, wherever it is: on its own, inside an array, or inside
    /// the `@graph` that most content management systems publish.
    static func findRecipe(in node: Any) -> [String: Any]? {
        if let array = node as? [Any] {
            for child in array {
                if let found = findRecipe(in: child) { return found }
            }
            return nil
        }
        guard let object = node as? [String: Any] else { return nil }

        let types = (object["@type"] as? String).map { [$0] } ?? (object["@type"] as? [String]) ?? []
        if types.contains(where: { $0.caseInsensitiveCompare("Recipe") == .orderedSame }) {
            return object
        }
        if let graph = object["@graph"] { return findRecipe(in: graph) }
        return nil
    }

    private static func build(from recipe: [String: Any], url: URL?) -> RecipeImporter.ImportedRecipe {
        let title = text(recipe["name"])
        let ingredients = strings(recipe["recipeIngredient"]).filter { !$0.isEmpty }
        let steps = instructions(recipe["recipeInstructions"])

        let prep = minutes(from: recipe["prepTime"])
        let cook = minutes(from: recipe["cookTime"])
        let total = minutes(from: recipe["totalTime"])

        return RecipeImporter.ImportedRecipe(
            externalID: url?.absoluteString,
            title: title.isEmpty ? (url?.host() ?? "Untitled") : title,
            summary: text(recipe["description"]),
            sourceURL: url?.absoluteString,
            prepMinutes: prep,
            // When only a total is published, prep plus cook still has to add
            // up to what the site said rather than to double it.
            cookMinutes: cook > 0 ? cook : max(0, total - prep),
            baseServings: servings(from: recipe["recipeYield"]),
            tags: strings(recipe["recipeCategory"]) + strings(recipe["recipeCuisine"]),
            cookware: [],
            ingredientLines: ingredients,
            steps: steps,
            imageURLs: imageURLs(recipe["image"]),
            imageFile: nil,
            notes: "",
            isFavorite: false,
            timesCooked: 0
        )
    }

    // MARK: - Reading the pieces

    /// "PT1H30M" is ninety minutes.
    static func minutes(from value: Any?) -> Int {
        let raw = text(value).uppercased()
        guard raw.hasPrefix("P") else { return 0 }

        var total = 0.0
        var number = ""
        var inTime = false

        for character in raw.dropFirst() {
            if character == "T" { inTime = true; continue }
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            let amount = Double(number) ?? 0
            number = ""
            switch character {
            case "D": total += amount * 1440
            case "H": total += amount * 60
            case "M": total += inTime ? amount : amount * 43200
            case "S": total += amount / 60
            default: break
            }
        }
        return total > 0 ? Int(total.rounded()) : 0
    }

    /// "4 servings", "4 to 6", 4. Four when it cannot tell, which is the same
    /// guess the file importers make and is correctable on the recipe screen.
    static func servings(from value: Any?) -> Int {
        for candidate in flatten(value) {
            if let number = candidate as? NSNumber, number.intValue > 0, number.intValue < 100 {
                return number.intValue
            }
            let written = text(candidate)
            if let found = written.split(whereSeparator: { !$0.isNumber }).first,
               let number = Int(found), number > 0, number < 100 {
                return number
            }
        }
        return 4
    }

    /// Strings, HowToStep objects, and HowToSections with the steps nested
    /// inside them. All three are in the wild.
    static func instructions(_ value: Any?) -> [String] {
        var out: [String] = []

        func walk(_ node: Any?) {
            guard let node else { return }
            if let array = node as? [Any] { return array.forEach(walk) }
            if let string = node as? String {
                let line = clean(string)
                if !line.isEmpty { out.append(line) }
                return
            }
            guard let object = node as? [String: Any] else { return }
            if let nested = object["itemListElement"] { return walk(nested) }
            let line = clean(text(object["text"] ?? object["name"]))
            if !line.isEmpty { out.append(line) }
        }

        walk(value)
        return out
    }

    static func imageURLs(_ value: Any?) -> [String] {
        flatten(value).compactMap { node -> String? in
            if let string = node as? String, string.hasPrefix("http") { return string }
            if let object = node as? [String: Any] {
                let inner = text(object["url"] ?? object["contentUrl"])
                return inner.hasPrefix("http") ? inner : nil
            }
            return nil
        }
    }

    private static func flatten(_ value: Any?) -> [Any] {
        guard let value else { return [] }
        if let array = value as? [Any] { return array.flatMap { flatten($0) } }
        return [value]
    }

    private static func strings(_ value: Any?) -> [String] {
        flatten(value).map { clean(text($0)) }.filter { !$0.isEmpty }
    }

    private static func text(_ value: Any?) -> String {
        switch value {
        case let string as String: return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    /// Markup and entities out of a field that is meant to be plain text. Some
    /// sites put `<p>` tags inside the JSON-LD.
    static func clean(_ value: String) -> String {
        var text = value
        while let open = text.firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            text.replaceSubrange(open...close, with: " ")
        }
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&frac12;", "1/2"),
            ("&frac14;", "1/4"), ("&frac34;", "3/4"),
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
