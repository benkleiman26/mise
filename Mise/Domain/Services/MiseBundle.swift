import Foundation

/// The bundle that carries `canonical_items.json` and `seed_recipes.json`.
///
/// `Bundle.main` is not it when the unit tests are running, because a hosted
/// test bundle's main bundle is the host app only by accident of how it is
/// launched. Resolving through a class defined in this module is the reliable
/// way to find the app's own resources from either side.
enum MiseBundle {
    static let resources = Bundle(for: BundleToken.self)
}

private final class BundleToken {}
