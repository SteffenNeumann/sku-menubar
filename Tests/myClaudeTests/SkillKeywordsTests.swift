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
        XCTAssertTrue(all.contains("run"), "eingebauter Skill fehlt")
        XCTAssertTrue(all.isSuperset(of: SkillKeywords.localSkills()),
                      "lokale Skills müssen enthalten bleiben")
        // Alle drei sind im `skills`-Feld des init-Events gelistet, aber
        // `disable-model-invocation` — das Skill-Tool lehnt sie ab.
        for blocked in ["debug", "verify", "deep-research"] {
            XCTAssertFalse(all.contains(blocked),
                           "\(blocked) ist disable-model-invocation und darf nicht angeboten werden")
        }
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

extension SkillKeywordsTests {

    // MARK: - ⭐ Pflicht-Skills

    private var agentBody: String { """
    ## Active Skills

    ### ⭐ Hauptskills — bei jeder Aufgabe laden

    - **`10k-website-checklist`** — The $10K Checklist (`~/.claude/skills/10k-website-checklist/SKILL.md`) — Text.
    - **`ui-ux-pro-max`** — UI/UX Pro Max (`~/.claude/skills/ui-ux-pro-max/SKILL.md`) — Text.
    - **`shadcn`** — shadcn/ui — Text.

    ### Situativ — laden, sobald das Thema auftaucht

    - **`ponytail-lazy-code`** — Ponytail — Text.

    You are an expert Frontend Developer.
    """ }

    func testMainSkillsReadsOnlyStarredBlock() {
        XCTAssertEqual(SkillKeywords.mainSkills(inAgentBody: agentBody),
                       ["10k-website-checklist", "ui-ux-pro-max", "shadcn"])
    }

    func testMainSkillsEmptyWithoutBlock() {
        XCTAssertTrue(SkillKeywords.mainSkills(inAgentBody: "Ein Agent ganz ohne Skill-Block.").isEmpty)
    }

    func testSkipPrefix() {
        XCTAssertTrue(SkillKeywords.hasSkipPrefix("kurz: ändere die Farbe"))
        XCTAssertTrue(SkillKeywords.hasSkipPrefix("  KURZ: mach das"))
        XCTAssertFalse(SkillKeywords.hasSkipPrefix("kurzfristig die Farbe ändern"))
        XCTAssertEqual(SkillKeywords.stripSkipPrefix("kurz:  ändere die Farbe"), "ändere die Farbe")
        XCTAssertEqual(SkillKeywords.stripSkipPrefix("ändere die Farbe"), "ändere die Farbe")
    }

    func testMainSkillsHintNamesEverySkill() {
        let hint = SkillKeywords.mainSkillsHint(for: ["a", "b"])
        XCTAssertTrue(hint.contains("`a`"))
        XCTAssertTrue(hint.contains("`b`"))
        XCTAssertTrue(hint.contains("Skill-Tool"))
    }

    /// Der Researcher erwähnt „⭐ Hauptskills" in seinen Arbeitsanweisungen im Fließtext.
    /// Nur eine Überschrift darf den Block eröffnen — sonst las der Parser dort weiter und
    /// zog Bruchstücke wie `## Active Skills` als Skill-Namen heraus.
    func testMainSkillsIgnoresProseMention() {
        let prose = """
        ## Arbeitsanweisung

        - **Respect the two-tier structure.** `## Active Skills` ist geteilt in
          `### ⭐ Hauptskills — bei jeder Aufgabe laden` und `### Situativ`.
        - Never touch a bullet marked `(eingebaut)`.
        """
        XCTAssertTrue(SkillKeywords.mainSkills(inAgentBody: prose).isEmpty)
    }

    /// Steht nach der Prosa-Erwähnung eine echte Überschrift, gewinnt diese.
    func testMainSkillsFindsHeadingAfterProseMention() {
        let mixed = """
        - Hinweis auf `### ⭐ Hauptskills — bei jeder Aufgabe laden` im Fließtext mit `(eingebaut)`.

        ### ⭐ Hauptskills — bei jeder Aufgabe laden
        - **`ui-ux-pro-max`** — Text.

        ### Situativ — laden, sobald das Thema auftaucht
        - **`ponytail-lazy-code`** — Text.
        """
        XCTAssertEqual(SkillKeywords.mainSkills(inAgentBody: mixed), ["ui-ux-pro-max"])
    }
}
