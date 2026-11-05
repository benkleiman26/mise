import Foundation

/// What kind of dish a recipe is: pasta, soup, sheet pan, a bowl.
///
/// The imported tags are the owner's NYT folders and Mealime collections,
/// which are whatever he happened to file things under. They are useful and
/// they are not the same question as "what are we in the mood for". This is
/// that question, worked out from the recipe itself.
///
/// Rules rather than a model, for three reasons: it has to run on 427 recipes
/// at launch without a network, a wrong answer has to be explainable, and the
/// vocabulary of home cooking is small enough that keywords get most of the way.
/// A recipe can be more than one thing. Chicken noodle soup is a soup; a baked
/// ziti is pasta and a bake.
enum DishType: String, CaseIterable, Codable, Sendable, Identifiable {
    case pasta
    case noodles
    case soup
    case stew
    case sheetPan
    case bowl
    case salad
    case sandwich
    case taco
    case pizza
    case curry
    case stirFry
    case riceAndGrains
    case beansAndLentils
    case roast
    case bake
    case grill
    case eggs
    case breakfast
    case dessert
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pasta: "Pasta"
        case .noodles: "Noodles"
        case .soup: "Soups"
        case .stew: "Stews and braises"
        case .sheetPan: "Sheet pan"
        case .bowl: "Bowls"
        case .salad: "Salads"
        case .sandwich: "Sandwiches and burgers"
        case .taco: "Tacos and wraps"
        case .pizza: "Pizza and flatbreads"
        case .curry: "Curries"
        case .stirFry: "Stir fries"
        case .riceAndGrains: "Rice and grains"
        case .beansAndLentils: "Beans and lentils"
        case .roast: "Roasts"
        case .bake: "Bakes and casseroles"
        case .grill: "Grilled"
        case .eggs: "Eggs"
        case .breakfast: "Breakfast"
        case .dessert: "Desserts"
        case .snack: "Snacks and sides"
        }
    }

    var systemImage: String {
        switch self {
        case .pasta, .noodles: "fork.knife"
        case .soup, .stew, .curry: "takeoutbag.and.cup.and.straw"
        case .sheetPan, .bake, .roast: "oven"
        case .bowl, .riceAndGrains, .beansAndLentils: "bowl"
        case .salad: "leaf"
        case .sandwich, .taco, .pizza: "square.stack"
        case .stirFry, .grill: "flame"
        case .eggs, .breakfast: "sun.horizon"
        case .dessert, .snack: "birthday.cake"
        }
    }
}

enum DishTypeClassifier {

    /// A word in the title is worth far more than the same word further in.
    /// "Pasta with Roasted Tomatoes" is pasta; "serve with pasta" at the end of
    /// a chicken recipe is a suggestion.
    private struct Rule {
        let type: DishType
        /// Decides it on its own when it appears in the title.
        let title: [String]
        /// Only counts alongside a title hit, or two of them together.
        let supporting: [String]
        /// Longer title phrases that take the keyword back, because the longer
        /// name is the dish. Without these, "Burrito Bowls" comes back a wrap
        /// and "Sheet Pan Salmon and Green Beans" comes back a beans dish.
        let unless: [String]

        init(_ type: DishType, title: [String], supporting: [String] = [], unless: [String] = []) {
            self.type = type
            self.title = title
            self.supporting = supporting
            self.unless = unless
        }
    }

    private static let rules: [Rule] = [
        Rule(.pasta, title: [
            "pasta", "spaghetti", "linguine", "fettuccine", "tagliatelle", "rigatoni",
            "penne", "macaroni", "lasagna", "lasagne", "orzo", "farfalle", "fusilli",
            "gnocchi", "tortellini", "ravioli", "carbonara", "bolognese", "cacio e pepe",
            "ziti", "orecchiette", "bucatini", "angel hair", "shells", "cavatappi",
        ], supporting: ["pasta water", "al dente"]),

        Rule(.noodles, title: [
            "noodle", "noodles", "ramen", "pho", "udon", "soba", "pad thai", "lo mein",
            "chow mein", "rice noodle", "glass noodle", "dan dan",
        ]),

        Rule(.soup, title: [
            "soup", "broth", "bisque", "chowder", "minestrone", "gazpacho", "consomme",
        ], supporting: ["simmer until the vegetables are tender"]),

        Rule(.stew, title: [
            "stew", "braise", "braised", "chili", "ragu", "ragù", "goulash", "tagine",
            "pot roast", "cassoulet", "gumbo",
        ], supporting: ["braise", "simmer, covered", "until falling apart"]),

        Rule(.sheetPan, title: [
            "sheet pan", "sheet-pan", "tray bake", "traybake", "one pan", "one-pan",
        ], supporting: ["sheet pan", "rimmed baking sheet", "baking sheet"]),

        Rule(.bowl, title: [
            "bowl", "bowls", "burrito bowl", "grain bowl", "poke", "bibimbap",
        ]),

        Rule(.salad, title: [
            "salad", "slaw", "coleslaw", "tabbouleh", "panzanella", "caprese",
        ], supporting: ["toss the greens", "vinaigrette"]),

        Rule(.sandwich, title: [
            "sandwich", "burger", "sliders", "melt", "toastie", "banh mi", "panini",
            "grilled cheese", "sub", "hoagie", "wrap", "roll-up",
        ]),

        // Plurals are spelled out because a keyword only matches a whole word:
        // "quesadilla" never finds "Black Bean Quesadillas".
        Rule(.taco, title: [
            "taco", "tacos", "quesadilla", "quesadillas", "burrito", "enchilada",
            "tostada", "fajita", "nachos", "tostadas",
        ], unless: ["burrito bowl", "burrito bowls"]),

        Rule(.pizza, title: [
            "pizza", "focaccia", "flatbread", "calzone", "pide", "manakish",
        ], supporting: ["pizza dough", "pizza stone"]),

        Rule(.curry, title: [
            "curry", "masala", "korma", "vindaloo", "dal", "daal", "dhal", "rogan josh",
            "butter chicken", "tikka",
        ], supporting: ["garam masala", "curry powder", "curry paste"]),

        Rule(.stirFry, title: [
            "stir fry", "stir-fry", "stir-fried", "fried rice", "teriyaki",
        ], supporting: ["wok", "stir-fry", "over high heat, stirring"]),

        Rule(.riceAndGrains, title: [
            "rice", "risotto", "pilaf", "paella", "quinoa", "farro", "couscous",
            "polenta", "congee", "jambalaya", "bulgur", "barley",
        ]),

        // Green beans are a vegetable alongside the main thing, not a legume
        // dish, so they do not make a sheet pan salmon dinner a beans recipe.
        Rule(.beansAndLentils, title: [
            "beans", "lentil", "lentils", "chickpea", "chickpeas", "hummus", "falafel",
            "black bean", "white bean", "refried",
        ], unless: ["green bean", "green beans"]),

        Rule(.roast, title: [
            "roast", "roasted", "porchetta", "prime rib", "spatchcock",
        ], supporting: ["roast until", "heat the oven to 4", "heat the oven to 5"]),

        Rule(.bake, title: [
            "bake", "baked", "casserole", "gratin", "pot pie", "shepherd's pie",
            "cottage pie", "strata", "enchilada bake",
        ], supporting: ["baking dish", "9-by-13", "casserole dish"]),

        Rule(.grill, title: [
            "grill", "grilled", "kebab", "kebabs", "skewers", "satay", "barbecue", "bbq",
        ], supporting: ["grill pan", "over the coals", "preheat the grill"]),

        Rule(.eggs, title: [
            "egg", "eggs", "omelet", "omelette", "frittata", "shakshuka", "quiche",
            "scramble", "scrambled", "poached egg",
        ]),

        Rule(.breakfast, title: [
            "pancake", "pancakes", "waffle", "waffles", "granola", "oatmeal", "porridge",
            "french toast", "muffin", "muffins", "smoothie", "overnight oats", "breakfast",
        ]),

        Rule(.dessert, title: [
            "cake", "cookie", "cookies", "brownie", "brownies", "pie", "tart", "crumble",
            "cobbler", "pudding", "ice cream", "sorbet", "mousse", "cheesecake",
            "shortbread", "biscotti", "scone", "scones", "dessert",
        ]),

        Rule(.snack, title: [
            "dip", "snack", "crostini", "bruschetta", "popcorn", "guacamole", "salsa",
            "side", "sides",
        ]),
    ]

    /// Types that describe a whole dish well enough that a weaker one is not
    /// worth adding alongside. A baked ziti is pasta first.
    private static let leading: [DishType] = [.pasta, .noodles, .soup, .stew, .curry, .taco, .pizza, .sandwich]

    /// Works out what a recipe is. Returns nothing rather than guessing when
    /// nothing fits, because an empty answer is honest and a wrong facet sends
    /// the cook looking in the wrong place.
    static func classify(
        title: String,
        ingredients: [String] = [],
        steps: [String] = [],
        cookware: [String] = []
    ) -> [DishType] {
        let titleText = " \(normalize(title)) "
        let bodyText = " \(normalize((ingredients + steps + cookware).joined(separator: " "))) "

        var found: [DishType] = []
        var fromTitle: Set<DishType> = []

        for rule in rules {
            // The longer name in the title wins outright. A burrito bowl is a
            // bowl and green beans are a vegetable, so the rule drops out here
            // rather than being outvoted later.
            // Parenthesised and labelled rather than a trailing closure: the
            // condition of an `if` does not accept one, so `{ ... }` would be
            // read as the body and the test left as an unapplied method.
            if rule.unless.contains(where: { titleText.contains(" \(normalize($0)) ") }) {
                continue
            }

            let inTitle = rule.title.contains { titleText.contains(" \(normalize($0)) ") }
            if inTitle {
                fromTitle.insert(rule.type)
                if !found.contains(rule.type) { found.append(rule.type) }
                continue
            }

            // Away from the title it takes more: either the name of the dish
            // appears in the method, or two separate supporting signs do.
            let bodyHits = rule.title.filter { bodyText.contains(" \(normalize($0)) ") }.count
                + rule.supporting.filter { bodyText.contains(normalize($0)) }.count
            if bodyHits >= 2, !found.contains(rule.type) {
                found.append(rule.type)
            }
        }

        // A dish that is plainly one thing does not also need the weaker
        // labels the method happened to mention.
        if let lead = found.first(where: { leading.contains($0) && fromTitle.contains($0) }) {
            let weaker: Set<DishType> = [.bake, .roast, .riceAndGrains, .beansAndLentils, .snack, .bowl, .grill]
            found = found.filter { $0 == lead || !weaker.contains($0) }
        }

        // Three labels is a description; six is noise.
        return Array(found.prefix(3))
    }

    static func classify(_ recipe: Recipe) -> [DishType] {
        classify(
            title: recipe.title,
            ingredients: recipe.ingredients.map(\.name),
            steps: recipe.steps.map(\.text),
            cookware: recipe.cookware
        )
    }

    /// Lowercased, punctuation to spaces, so "sheet-pan" and "sheet pan" are
    /// the same thing and a word is never found inside another word.
    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
