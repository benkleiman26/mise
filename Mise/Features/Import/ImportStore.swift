import Foundation

/// Section 5.7's import, as the screen sees it.
///
/// `RecipeImporter` decides what the file means. This reads it, writes the
/// result through the repositories, and keeps the report so Settings can say
/// what happened.
@MainActor
@Observable
final class ImportStore {
    private let recipes: any RecipeRepository
    private let canonicalItems: any CanonicalItemRepository
    private let households: any HouseholdRepository

    private(set) var isWorking = false
    private(set) var report: RecipeImporter.Report?
    private(set) var problem: String?

    init(
        recipes: any RecipeRepository,
        canonicalItems: any CanonicalItemRepository,
        households: any HouseholdRepository
    ) {
        self.recipes = recipes
        self.canonicalItems = canonicalItems
        self.households = households
    }

    /// `url` comes from a file picker, so it is security scoped and has to be
    /// opened before it can be read.
    func importRecipes(from url: URL) {
        isWorking = true
        defer { isWorking = false }

        do {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            report = try run(on: try Data(contentsOf: url))
            problem = nil
        } catch {
            report = nil
            problem = (error as? LocalizedError)?.errorDescription ?? "The import failed. \(error)"
        }
    }

    // MARK: - Private

    private func run(on data: Data) throws -> RecipeImporter.Report {
        guard let household = try households.all().first else {
            throw RecipeImporter.ImportError.noHousehold
        }

        let document = try RecipeImporter.decode(data)
        let source = document.source ?? "import"

        let importer = RecipeImporter(
            householdID: household.id,
            matcher: CanonicalMatcher(items: try canonicalItems.all().map {
                CanonicalCandidate(
                    id: $0.id,
                    name: $0.name,
                    aliases: $0.aliases,
                    aisle: $0.aisle,
                    isStaple: $0.isStaple,
                    defaultUnit: $0.defaultUnit
                )
            })
        )

        var report = RecipeImporter.Report()
        report.source = source
        let existing = try recipes.existingIDs()

        // Importing the same library again replaces each recipe rather than
        // adding a second copy. Deleting first is simpler than reconciling the
        // ingredients and steps one by one, and the cascade rule takes the
        // children with it.
        //
        // The deletes are committed before the inserts, because a delete and an
        // insert of the same id inside one transaction is asking a unique
        // constraint to hold two rows at once.
        for imported in document.recipes {
            let id = importer.id(for: imported, source: source)
            if existing.contains(id) {
                if let old = try recipes.find(id: id) { recipes.delete(old) }
                report.recipesUpdated += 1
            } else {
                report.recipesInserted += 1
            }
        }
        try recipes.save()

        for imported in document.recipes {
            recipes.insert(importer.build(imported, source: source, into: &report))
        }
        try recipes.save()

        // The same name appearing in twenty recipes is one thing to categorise,
        // not twenty.
        report.unmatchedIngredients = Array(Set(report.unmatchedIngredients)).sorted()
        return report
    }
}
