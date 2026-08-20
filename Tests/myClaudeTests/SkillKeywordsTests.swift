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

// MARK: - Skill-Quellen (Plugin + eingebaut), ergänzt 20.08.2026

extension SkillKeywordsTests {

    /// Der Kern des Fehlers: ein Scan von ~/.claude/skills kennt nur 9 der 25 Skills.
    func testInstalledSkillsUmfasstPluginUndEingebauteSkills() {
        let all = SkillKeywords.installedSkills()
        XCTAssertTrue(all.contains("code-review"), "eingebauter Skill fehlt")
        XCTAssertTrue(all.contains("deep-research"), "eingebauter Skill fehlt")
        XCTAssertTrue(all.isSuperset(of: SkillKeywords.localSkills()),
                      "lokale Skills müssen enthalten bleiben")
        XCTAssertFalse(all.contains("debug"),
                       "debug ist disable-model-invocation und darf nicht angeboten werden")
    }

    /// Plugin-Skills heißen `plugin:name` — sonst greift der Filter in `match` nicht.
    func testPluginSkillsTragenDasPluginPräfix() {
        for skill in SkillKeywords.pluginSkills() {
            XCTAssertTrue(skill.contains(":"), "Plugin-Skill ohne Präfix: \(skill)")
        }
    }

    /// Vorher wurde „docuseal" stumm weggefiltert, weil der Skill nicht auf der Platte lag.
    func testDocusealStichwortTrifftPluginSkill() {
        let treffer = SkillKeywords.match(in: "Bau die DocuSeal-Anbindung",
                                          availableSkills: SkillKeywords.installedSkills())
        XCTAssertEqual(treffer, "docuseal:docuseal-code")
    }

    /// Jeder Skill in der Tabelle muss auch wirklich aufrufbar sein.
    func testAlleGemapptenSkillsSindVerfügbar() {
        let verfügbar = SkillKeywords.installedSkills()
        for eintrag in SkillKeywords.map {
            XCTAssertTrue(verfügbar.contains(eintrag.skill),
                          "Stichwort zeigt auf nicht verfügbaren Skill: \(eintrag.skill)")
        }
    }
}
