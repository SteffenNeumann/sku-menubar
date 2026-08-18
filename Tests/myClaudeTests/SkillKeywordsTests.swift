import XCTest
@testable import myClaude

final class SkillKeywordsTests: XCTestCase {
    private let all: Set<String> = ["10k-website-checklist", "ui-ux-pro-max",
                                    "web-design-guidelines", "excel-vba", "shadcn"]

    func testMatchesGermanWebsiteKeyword() {
        XCTAssertEqual(SkillKeywords.match(in: "Die Startseite hat eine Doppelung", availableSkills: all),
                       "10k-website-checklist")
    }

    func testRespectsWordBoundaries() {
        // "excel" darf nicht in "excellent" anschlagen
        XCTAssertNil(SkillKeywords.match(in: "Das Ergebnis ist excellent", availableSkills: all))
        XCTAssertEqual(SkillKeywords.match(in: "Makro für die Arbeitsmappe", availableSkills: all), "excel-vba")
    }

    func testSkipsSkillsThatAreNotInstalled() {
        XCTAssertNil(SkillKeywords.match(in: "Bau mir eine Landingpage", availableSkills: []))
    }

    func testNoMatchWithoutKeyword() {
        XCTAssertNil(SkillKeywords.match(in: "Bitte fahre dort fort wo du aufgehört hast", availableSkills: all))
    }

    func testHintNamesTheSkillAndTool() {
        let h = SkillKeywords.hint(for: "shadcn")
        XCTAssertTrue(h.contains("shadcn") && h.contains("Skill-Tool"))
    }
}
