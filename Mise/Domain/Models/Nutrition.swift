import Foundation

/// Per serving nutrition, stored only when a source provides it. Section 4 is
/// explicit that v1 never computes these itself, so every field is optional and
/// an absent value means "the source did not say", not zero.
struct Nutrition: Codable, Hashable, Sendable {
    var calories: Double?
    var fatGrams: Double?
    var carbGrams: Double?
    var proteinGrams: Double?
    var fiberGrams: Double?

    init(
        calories: Double? = nil,
        fatGrams: Double? = nil,
        carbGrams: Double? = nil,
        proteinGrams: Double? = nil,
        fiberGrams: Double? = nil
    ) {
        self.calories = calories
        self.fatGrams = fatGrams
        self.carbGrams = carbGrams
        self.proteinGrams = proteinGrams
        self.fiberGrams = fiberGrams
    }
}
