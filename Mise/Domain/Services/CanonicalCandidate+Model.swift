import Foundation

/// The one place a stored `CanonicalItem` becomes the value type the matcher
/// takes. Three screens needed this and each had written its own copy, which is
/// three places to forget a field: `learnedAliases` would have been added to
/// two of them.
extension CanonicalCandidate {
    init(_ item: CanonicalItem) {
        self.init(
            id: item.id,
            name: item.name,
            aliases: item.aliases,
            learnedAliases: item.learnedAliases,
            aisle: item.aisle,
            isStaple: item.isStaple,
            defaultUnit: item.defaultUnit
        )
    }
}
