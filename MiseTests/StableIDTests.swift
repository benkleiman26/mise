import Foundation
import XCTest
@testable import Mise

/// The seed loader's idempotency rests entirely on these being stable, so this
/// checks the implementation against the published RFC 4122 test vector rather
/// than only against itself.
final class StableIDTests: XCTestCase {
    /// RFC 4122 appendix: version 5 of the DNS namespace with the name
    /// "www.example.org".
    func testMatchesThePublishedVersion5Vector() {
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let id = StableID.uuid(namespace: dns, name: "www.example.org")
        XCTAssertEqual(id.uuidString, "74738FF5-5367-5958-9AEE-98FFFDCD1876")
    }

    func testTheMiseNamespaceIsVersion5OfItsDomain() {
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        XCTAssertEqual(StableID.uuid(namespace: dns, name: "mise.benkleiman.com"), StableID.namespace)
    }

    func testTheSameKeyAlwaysGivesTheSameID() {
        XCTAssertEqual(
            StableID.canonicalItem(name: "kosher salt"),
            StableID.canonicalItem(name: "kosher salt")
        )
        XCTAssertEqual(
            StableID.recipe(seedID: "seed-sheet-pan-salmon"),
            StableID.recipe(seedID: "seed-sheet-pan-salmon")
        )
    }

    func testDifferentKindsOfKeyDoNotCollide() {
        XCTAssertNotEqual(StableID.canonicalItem(name: "salmon"), StableID.recipe(seedID: "salmon"))
        XCTAssertNotEqual(
            StableID.ingredient(recipeSeedID: "r", position: 0),
            StableID.step(recipeSeedID: "r", position: 0)
        )
        XCTAssertNotEqual(
            StableID.ingredient(recipeSeedID: "r", position: 0),
            StableID.ingredient(recipeSeedID: "r", position: 1)
        )
    }

    func testEveryGeneratedIDIsAVersion5UUID() {
        let id = StableID.household()
        // Byte 6 high nibble is the version, byte 8 top two bits are the variant.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        XCTAssertEqual(bytes[6] & 0xF0, 0x50)
        XCTAssertEqual(bytes[8] & 0xC0, 0x80)
    }
}
