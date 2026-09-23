import XCTest
@testable import myClaude

/// Kurznamen (Persona-Frontmatter `model: sonnet`) müssen auf eine ECHTE, neueste ID zeigen —
/// früher standen erfundene IDs (claude-sonnet-4-6-20250514) im Code → API 404.
@MainActor
final class ModelCatalogTests: XCTestCase {
    private let apiOrder = [
        "claude-opus-5-5", "claude-fable-5-1", "claude-opus-5", "claude-sonnet-5", "claude-fable-5",
        "claude-opus-4-8", "claude-opus-4-7", "claude-sonnet-4-6", "claude-opus-4-6",
        "claude-opus-4-5-20251101", "claude-haiku-4-5-20251001", "claude-sonnet-4-5-20250929",
    ]

    func testLatestIDPerTier() {
        XCTAssertEqual(ModelCatalog.latestID(tier: "sonnet", discovered: apiOrder), "claude-sonnet-5")
        XCTAssertEqual(ModelCatalog.latestID(tier: "Opus",   discovered: apiOrder), "claude-opus-5-5")
        XCTAssertEqual(ModelCatalog.latestID(tier: "haiku",  discovered: apiOrder), "claude-haiku-4-5-20251001")
        XCTAssertEqual(ModelCatalog.latestID(tier: "fable",  discovered: apiOrder), "claude-fable-5-1")
    }

    func testLatestIDWithoutDiscoveredUsesCatalog() {
        XCTAssertEqual(ModelCatalog.latestID(tier: "sonnet", discovered: []), "claude-sonnet-5")
    }

    func testFullIDIsNotATier() {
        XCTAssertNil(ModelCatalog.latestID(tier: "claude-opus-4-8", discovered: apiOrder))
        XCTAssertNil(ModelCatalog.latestID(tier: "llama3.2", discovered: apiOrder))
    }

    func testCatalogHasNoInventedIDs() {
        for m in ModelCatalog.anthropicBundled {
            XCTAssertTrue(apiOrder.contains(m.apiName), "\(m.apiName) fehlt in der Live-Liste")
        }
    }
}
