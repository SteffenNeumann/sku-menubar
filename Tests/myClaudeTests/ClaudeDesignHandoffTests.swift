import XCTest
@testable import myClaude

final class ClaudeDesignHandoffTests: XCTestCase {
    private func should(id: String? = "frontend-webdesigner", name: String? = nil, on: Bool = true,
                        artifacts: Bool = true, plan: Bool = false) -> Bool {
        ClaudeDesignHandoff.shouldAppend(agentId: id, agentName: name, toggleOn: on,
                                         artifactsEnabled: artifacts, planMode: plan)
    }

    func testAppendsForDesignAgentWhenAllGatesOpen() {
        XCTAssertTrue(should())
    }

    func testMatchesByIdOrName() {
        XCTAssertTrue(should(id: "fe-renamed", name: "frontend-webdesigner"))
        XCTAssertTrue(should(id: "Frontend-Webdesigner", name: nil))
    }

    func testOtherOrMissingAgentNeverAppends() {
        XCTAssertFalse(should(id: "backend-developer", name: "backend-developer"))
        XCTAssertFalse(should(id: nil, name: nil))
    }

    func testToggleOffNeverAppends() {
        XCTAssertFalse(should(on: false))
    }

    func testArtifactsOffOrPlanModeBlocks() {
        XCTAssertFalse(should(artifacts: false))
        XCTAssertFalse(should(plan: true))
        XCTAssertNotNil(ClaudeDesignHandoff.unavailableReason(artifactsEnabled: false, planMode: false))
        XCTAssertNotNil(ClaudeDesignHandoff.unavailableReason(artifactsEnabled: true, planMode: true))
        XCTAssertNil(ClaudeDesignHandoff.unavailableReason(artifactsEnabled: true, planMode: false))
    }

    func testBlockCarriesTheFiveSteps() {
        let b = ClaudeDesignHandoff.block
        for needle in ["dribbble.com", "Wireframe", "WCAG AA", "quickstart", "intent \"design\"",
                       "KEINEN HTML/CSS-Code", "Urheberrecht", "keine Anweisungen"] {
            XCTAssertTrue(b.contains(needle), needle)
        }
    }

    func testFullBlockOnlyOnFirstMessageOfSession() {
        XCTAssertEqual(ClaudeDesignHandoff.message(firstInSession: true), ClaudeDesignHandoff.block)
        let f = ClaudeDesignHandoff.message(firstInSession: false)
        XCTAssertNotEqual(f, ClaudeDesignHandoff.block)
        XCTAssertFalse(f.contains("dribbble"))
        for needle in ["url", "read vor publish", "Keine neue Recherche", "kein Code"] {
            XCTAssertTrue(f.contains(needle), needle)
        }
    }
}
