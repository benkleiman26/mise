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
    /// Import files sitting in the app's own Documents folder, newest first.
    private(set) var waiting: [WaitingFile] = []

    struct WaitingFile: Identifiable, Equatable {
        let url: URL
        let name: String
        let sizeText: String
        var id: URL { url }
    }

    init(
        recipes: any RecipeRepository,
        canonicalItems: any CanonicalItemRepository,
        households: any HouseholdRepository
    ) {
        self.recipes = recipes
        self.canonicalItems = canonicalItems
        self.households = households
    }

    /// The app's own Documents folder, which is where a file copied in with
    /// `xcrun simctl get_app_container` lands, and where a file dropped into
    /// Mise's folder from a Mac lands on a real phone.
    ///
    /// Looking here is not a shortcut around the file picker. Files would not
    /// show the folder at all on 2026-11-02, and a working import is worth more
    /// than a tidy one. The picker stays for everything outside this folder.
    static var documentsDirectory: URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    func findWaitingFiles() {
        guard let directory = Self.documentsDirectory else {
            waiting = []
            return
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []

        waiting = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { left, right in
                let a = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            .map { url in
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return WaitingFile(
                    url: url,
                    name: url.lastPathComponent,
                    sizeText: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                )
            }
    }

    /// `url` may come from a file picker, in which case it is security scoped
    /// and has to be opened before it can be read. A file in our own Documents
    /// folder is not, and `startAccessingSecurityScopedResource` says so by
    /// returning false, which is why the result is checked rather than assumed.
    func importRecipes(from url: URL) {
        guard !isWorking else { return }
        isWorking = true

        // 2436 ingredient lines through the parser and the matcher takes a few
        // seconds, and it has to run on the main actor because the store does.
        // Yielding once first lets the row redraw as "Importing" rather than
        // the app looking frozen with no explanation.
        Task {
            await Task.yield()
            work(on: url)
            isWorking = false
        }
    }

    private func work(on url: URL) {
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
