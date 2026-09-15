import Foundation
import SwiftData

/// One instruction. `ingredientRefs` points at the recipe's own ingredients so
/// cook mode can pin the right quantities to the step the cook is on, which is
/// the part of Mealime worth copying exactly. Sections 4 and 5.5.
///
/// Named `RecipeStep` rather than the spec's `Step` because `Step` is a common
/// enough word to collide with a SwiftUI or Foundation symbol later.
@Model
final class RecipeStep {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Recipe order. See `Recipe.orderedSteps`.
    var position: Int

    var text: String
    var timerSeconds: Int?
    var ingredientRefs: [UUID]

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        position: Int,
        text: String,
        timerSeconds: Int? = nil,
        ingredientRefs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.position = position
        self.text = text
        self.timerSeconds = timerSeconds
        self.ingredientRefs = ingredientRefs
    }
}
