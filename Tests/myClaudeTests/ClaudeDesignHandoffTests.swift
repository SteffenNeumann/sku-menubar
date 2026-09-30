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

    // MARK: Phase

    func testPhaseStartsWithoutRunningSessionOrBriefing() {
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: false, briefedAt: 1, lastArtifactIndex: 3), .start)
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: true, briefedAt: nil, lastArtifactIndex: 3), .start)
    }

    func testPhaseInProgressUntilArtifactAfterBriefing() {
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: true, briefedAt: 1, lastArtifactIndex: nil), .inProgress)
        // Älteres Artifact vor dem Briefing zählt nicht als Design
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: true, briefedAt: 5, lastArtifactIndex: 2), .inProgress)
    }

    func testPhaseReviseOnceArtifactPublishedSinceBriefing() {
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: true, briefedAt: 1, lastArtifactIndex: 1), .revise)
        XCTAssertEqual(ClaudeDesignHandoff.phase(sessionRunning: true, briefedAt: 1, lastArtifactIndex: 7), .revise)
    }

    func testMessagePerPhase() {
        XCTAssertEqual(ClaudeDesignHandoff.message(for: .start), ClaudeDesignHandoff.block)
        let prog = ClaudeDesignHandoff.message(for: .inProgress)
        for needle in ["Interview", "ein Thema pro Nachricht", "OK", "Kein Code"] {
            XCTAssertTrue(prog.contains(needle), needle)
        }
        // Design aus type_url erzeugt ggf. keine Karte → Phase bleibt „läuft": der Hinweis muss
        // dann selbst aufs Überarbeiten statt auf Neu-Recherche lenken.
        for needle in ["schon ein Design-Artifact", "per url", "read vor publish",
                       "keine neue Recherche", "kein neuer Artifact"] {
            XCTAssertTrue(prog.contains(needle), needle)
        }
        let rev = ClaudeDesignHandoff.message(for: .revise)
        for needle in ["per url", "read vor publish", "Keine neue Recherche", "kein Code"] {
            XCTAssertTrue(rev.contains(needle), needle)
        }
    }

    func testBlockStartsWithInterviewAndOkGate() {
        let b = ClaudeDesignHandoff.block
        XCTAssertTrue(ClaudeDesignHandoff.containsFullBlock(b))
        XCTAssertFalse(ClaudeDesignHandoff.containsFullBlock(ClaudeDesignHandoff.inProgressHint))
        XCTAssertFalse(ClaudeDesignHandoff.containsFullBlock(ClaudeDesignHandoff.followUp))
        for needle in ["NICHT sofort", "EIN Thema pro Nachricht", "Zielgruppe", "Ziel der Seite",
                       "Inhalte & Unterseiten", "Stil & Tonalität", "Vorhandenes", "Vorbilder",
                       "Technik", "Thema 3/7", "höchstens 2 Antwort-Vorschläge", "Empfehlung",
                       "überspringen", "ausdrückliches OK", "erst nach dem OK"] {
            XCTAssertTrue(b.contains(needle), needle)
        }
        // Interview kommt vor Dribbble
        XCTAssertLessThan(b.range(of: "Interview")!.lowerBound, b.range(of: "dribbble.com")!.lowerBound)
    }
}
