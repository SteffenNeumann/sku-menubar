import XCTest
@testable import myClaude

/// Unit-Tests für die reine Orchestrator-Logik (Parser + Routing).
/// Genau diese Funktionen brauchten in der Hardening-Session mehrere Fixes (H1/H3/M1) —
/// die Tests frieren das Verhalten ein, damit künftiges Prompt-/Heuristik-Tuning
/// keine stillen Regressionen einführt.
final class OrchestratorLogicTests: XCTestCase {

    // MARK: - Helpers

    private func makeAgent(id: String, name: String) -> AgentDefinition {
        AgentDefinition(
            id: id, name: name, description: "", model: "", color: nil, memory: nil,
            portrait: nil, triggers: [], promptBody: "", filePath: "",
            projectDirectory: nil, schedule: nil, isActive: false, timeoutMinutes: 30,
            researchUpdatedAt: nil, skillsUpdatedAt: nil, dreamSchedule: nil,
            category: nil, customerName: nil, industry: nil, techLevel: nil,
            priorities: [], dealbreakers: [], tone: nil, associatedProjects: [],
            contextImages: [], emailDomain: nil, emailAddress: nil,
            emailRoutingEnabled: false, requiredMCPs: []
        )
    }

    private var agents: [AgentDefinition] {
        [makeAgent(id: "backend", name: "backend-developer"),
         makeAgent(id: "data", name: "data-analyst"),
         makeAgent(id: "qa", name: "qa-test-engineer")]
    }

    // MARK: - classifyFollowUp

    func testTrivialThanksIsChat() {
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("danke"), .chat)
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("ok danke"), .chat)
    }

    func testQuestionIsChat() {
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("Wie funktioniert die Archivtabelle?"), .chat)
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("was ist das Archiv-Modul"), .chat)
    }

    func testExplanationRequestWithoutQuestionMarkIsChat() {
        // Der ursprüngliche Bug: lange Erklärfrage ohne "?" löste neue Orchestrierung aus
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp(
            "Erläutere mir noch wie das mit der Archivtabelle funktioniert"), .chat)
    }

    func testExplanationPlusSecondTaskIsFast() {
        // M1: Composite-Satz — Erklärung + echte zweite Aufgabe darf NICHT als reiner Chat enden
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp(
            "Fasse das zusammen und baue dann noch Tests dazu"), .fast)
    }

    func testExplanationWithTemporalDanachStaysChat() {
        // "danach" als temporales Adverb ohne Handlungsverb darf NICHT als Aufgabe gelten
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp(
            "Erläutere mir erst das Schema, danach reden wir weiter"), .chat)
    }

    func testPureExecuteIsFast() {
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("go"), .fast)
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp("bitte umsetzen"), .fast)
    }

    func testComplexNewTopicIsFull() {
        let text = "Analysiere bitte die komplette Datenbankstruktur und erstelle anschließend " +
                   "ein vollständiges Migrationskonzept für alle Tabellen inklusive Datenvalidierung " +
                   "sowie einem Rollback-Plan für den Fehlerfall mit allen nötigen Skripten"
        XCTAssertEqual(OrchestratorLogic.classifyFollowUp(text), .full)
    }

    // MARK: - containsAdditionalActionTask

    func testActionContinuationDetected() {
        XCTAssertTrue(OrchestratorLogic.containsAdditionalActionTask(
            "Fasse zusammen und baue dann Tests"))
        XCTAssertTrue(OrchestratorLogic.containsAdditionalActionTask(
            "Explain the cache and add a test"))
        XCTAssertTrue(OrchestratorLogic.containsAdditionalActionTask(
            "Erkläre das und dann implementiere die Lösung"))
    }

    func testTemporalAdverbWithoutVerbNotDetected() {
        XCTAssertFalse(OrchestratorLogic.containsAdditionalActionTask(
            "Erläutere mir das Schema, danach reden wir"))
        XCTAssertFalse(OrchestratorLogic.containsAdditionalActionTask(
            "Beschreibe den Ablauf"))
    }

    // MARK: - isComplexTask

    func testShortTextNotComplex() {
        XCTAssertFalse(OrchestratorLogic.isComplexTask("Bitte führe auch einen Security-Scan durch"))
    }

    func testMultiVerbLongTextComplex() {
        let text = "Erstelle bitte eine vollständige Analyse der bestehenden Architektur " +
                   "und implementiere danach die notwendigen Verbesserungen im Backend-Bereich " +
                   "damit die Anwendung stabiler läuft"
        XCTAssertTrue(OrchestratorLogic.isComplexTask(text))
    }

    // MARK: - resolveAgent (H3)

    func testResolveAgentAcrossHyphens() {
        // "Data Analyst" muss "data-analyst" matchen — reines contains scheiterte am Bindestrich
        XCTAssertEqual(OrchestratorLogic.resolveAgent(named: "Data Analyst", in: agents)?.id, "data")
        XCTAssertEqual(OrchestratorLogic.resolveAgent(named: "QA Test Engineer", in: agents)?.id, "qa")
    }

    func testResolveAgentExactMatchWins() {
        XCTAssertEqual(OrchestratorLogic.resolveAgent(named: "backend-developer", in: agents)?.id, "backend")
    }

    func testResolveAgentAmbiguityPicksLongestDeterministically() {
        let pool = [makeAgent(id: "d1", name: "designer"),
                    makeAgent(id: "d2", name: "ux-designer")]
        // "Designer" ist ein EXAKTER (case-insensitiver) Match auf "designer" → der gewinnt
        XCTAssertEqual(OrchestratorLogic.resolveAgent(named: "Designer", in: pool)?.id, "d1")
        // Ohne exakten Match ("Design" matcht beide fuzzy) → längster Kandidat, deterministisch
        XCTAssertEqual(OrchestratorLogic.resolveAgent(named: "Design", in: pool)?.id, "d2")
    }

    func testResolveAgentUnknownReturnsNil() {
        XCTAssertNil(OrchestratorLogic.resolveAgent(named: "frontend-magician", in: agents))
    }

    // MARK: - parseMasterPlan (Text-Format)

    func testParseMasterPlanGoldenFormat() {
        let plan = """
        ZIEL: Rechnungsarchiv fertigstellen

        1. Backend-Arbeiten
           1.1 Archivtabelle anlegen → backend-developer
           1.2 Datenmigration prüfen → data-analyst

        2. Qualitätssicherung
           2.1 Tests schreiben → qa-test-engineer
        """
        let result = OrchestratorLogic.parseMasterPlan(plan, agents: agents)
        XCTAssertEqual(result.goal, "Rechnungsarchiv fertigstellen")
        XCTAssertEqual(result.agentTasks["backend"], "Archivtabelle anlegen")
        XCTAssertEqual(result.agentTasks["data"], "Datenmigration prüfen")
        XCTAssertEqual(result.agentTasks["qa"], "Tests schreiben")
        XCTAssertEqual(result.todos.filter { $0.level == 0 }.count, 2)
        XCTAssertEqual(result.todos.filter { $0.level == 1 }.count, 3)
    }

    func testParseMasterPlanToleratesMarkdownArtifacts() {
        let plan = """
        ZIEL: Test

        **1. Phase**
           - **1.1:** Aufgabe eins → **backend-developer**
        """
        let result = OrchestratorLogic.parseMasterPlan(plan, agents: agents)
        XCTAssertEqual(result.agentTasks["backend"], "Aufgabe eins")
    }

    func testParseMasterPlanMergesMultipleSubItemsPerAgent() {
        let plan = """
        ZIEL: Test
        1. Phase
           1.1 Erste Aufgabe → backend-developer
           1.2 Zweite Aufgabe → backend-developer
        """
        let result = OrchestratorLogic.parseMasterPlan(plan, agents: agents)
        XCTAssertEqual(result.agentTasks["backend"], "Erste Aufgabe\n- Zweite Aufgabe")
    }

    func testParseMasterPlanEmptyInput() {
        let result = OrchestratorLogic.parseMasterPlan("", agents: agents)
        XCTAssertTrue(result.agentTasks.isEmpty)
        XCTAssertTrue(result.todos.isEmpty)
        XCTAssertEqual(result.goal, "")
    }

    // MARK: - parsePlanJSON (V6)

    func testParsePlanJSONBasic() {
        let raw = """
        {"ziel":"Archiv fertigstellen","schritte":[{"nr":"1.1","titel":"Tabelle anlegen","agent":"backend-developer"},{"nr":"1.2","titel":"Tests schreiben","agent":"qa-test-engineer"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.goal, "Archiv fertigstellen")
        XCTAssertEqual(result?.agentTasks["backend"], "Tabelle anlegen")
        XCTAssertEqual(result?.agentTasks["qa"], "Tests schreiben")
        XCTAssertEqual(result?.todos.count, 2)
    }

    func testParsePlanJSONToleratesCodeFencesAndSurroundingText() {
        let raw = """
        Hier ist der Plan:
        ```json
        {"ziel":"X","schritte":[{"nr":"1.1","titel":"Aufgabe","agent":"Data Analyst"}]}
        ```
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        // Agent-Name-Auflösung über Bindestrich-Normalisierung (H3) auch im JSON-Pfad
        XCTAssertEqual(result?.agentTasks["data"], "Aufgabe")
    }

    func testParsePlanJSONEnglishKeys() {
        let raw = """
        {"goal":"Finish","steps":[{"id":"1.1","title":"Do it","agent":"backend-developer"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.goal, "Finish")
        XCTAssertEqual(result?.agentTasks["backend"], "Do it")
    }

    func testParsePlanJSONInvalidReturnsNil() {
        XCTAssertNil(OrchestratorLogic.parsePlanJSON("ZIEL: kein JSON\n1.1 Aufgabe → backend", agents: agents))
        XCTAssertNil(OrchestratorLogic.parsePlanJSON("", agents: agents))
        XCTAssertNil(OrchestratorLogic.parsePlanJSON("{\"ziel\":\"x\",\"schritte\":[]}", agents: agents))
    }

    // MARK: - parsePlanJSON Recovery (P1/P2/P4)

    /// Fehlendes agent-Feld → positionsbasierte Recovery statt leerem agentTasks (kein Fallback).
    func testParsePlanJSONMissingAgentRecoversPositional() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"Aufgabe A"},{"nr":"1.2","titel":"Aufgabe B"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.agentTasks.isEmpty ?? true)
        // Round-robin über die übergebene Agent-Liste: Schritt 0 → backend, Schritt 1 → data
        XCTAssertEqual(result?.agentTasks["backend"], "Aufgabe A")
        XCTAssertEqual(result?.agentTasks["data"], "Aufgabe B")
    }

    /// Platzhalter "AgentName" aus dem Prompt-Beispiel wörtlich kopiert → Recovery.
    func testParsePlanJSONPlaceholderAgentRecovers() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"A","agent":"AgentName"},{"nr":"1.2","titel":"B","agent":"AgentName"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentTasks["backend"], "A")
        XCTAssertEqual(result?.agentTasks["data"], "B")
    }

    /// Übersetzter/erfundener Name (matcht nicht) → Recovery statt Gesamtauftrag-Fallback.
    func testParsePlanJSONTranslatedNameRecovers() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"A","agent":"Datenanalyst"},{"nr":"1.2","titel":"B","agent":"Backend-Entwickler"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentTasks["backend"], "A")
        XCTAssertEqual(result?.agentTasks["data"], "B")
    }

    /// P4: Komma-Liste in einem agent-Feld → BEIDE Agents erhalten die Aufgabe (kein stiller Verlust).
    func testParsePlanJSONCommaListResolvesBoth() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"Gemeinsam","agent":"data-analyst, qa-test-engineer"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentTasks["data"], "Gemeinsam")
        XCTAssertEqual(result?.agentTasks["qa"], "Gemeinsam")
        XCTAssertEqual(result?.todos.count, 1)
    }

    /// P4: "und"-getrennte Namen → beide aufgelöst.
    func testParsePlanJSONUndSeparatorResolvesBoth() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"X","agent":"backend-developer und qa-test-engineer"}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertEqual(result?.agentTasks["backend"], "X")
        XCTAssertEqual(result?.agentTasks["qa"], "X")
    }

    /// Falscher Key (Plural "agents") → agent nil → Recovery positionsbasiert.
    func testParsePlanJSONUnknownAgentKeyRecovers() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"A","agents":["data-analyst"]}]}
        """
        let result = OrchestratorLogic.parsePlanJSON(raw, agents: agents)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentTasks["backend"], "A")
    }

    /// Ohne Agent-Liste KEINE Recovery möglich → nil (Caller nutzt bewusst Gesamtauftrag-Fallback).
    func testParsePlanJSONNoAgentsListReturnsNil() {
        let raw = """
        {"ziel":"Z","schritte":[{"nr":"1.1","titel":"A","agent":"AgentName"}]}
        """
        XCTAssertNil(OrchestratorLogic.parsePlanJSON(raw, agents: []))
    }

    // MARK: - parseOrchestratorPlan (Legacy)

    func testParseLegacyPlan() {
        let plan = """
        AGENT: backend-developer
        AUFGABE: Tabelle bauen
        AGENT: qa-test-engineer
        AUFGABE: Testen
        """
        let result = OrchestratorLogic.parseOrchestratorPlan(plan, agents: agents)
        XCTAssertEqual(result["backend"], "Tabelle bauen")
        XCTAssertEqual(result["qa"], "Testen")
    }

    // MARK: - parseBulkAnalysis (Phase 0)

    func testParseBulkAnalysisAssignsLines() {
        let text = """
        backend-developer: Baut die Tabelle.
        - data-analyst: Prüft die Daten.
        """
        let result = OrchestratorLogic.parseBulkAnalysis(text, agents: agents)
        XCTAssertEqual(result.first(where: { $0.name == "backend-developer" })?.analysis, "Baut die Tabelle.")
        XCTAssertEqual(result.first(where: { $0.name == "data-analyst" })?.analysis, "Prüft die Daten.")
        XCTAssertEqual(result.first(where: { $0.name == "qa-test-engineer" })?.analysis, "")
    }

    // MARK: - formatPlan

    func testFormatPlanRendersGoalAndSteps() {
        let todos = [
            MasterTodoItem(id: "1.", number: "1.", title: "Phase", assignedAgent: nil, level: 0, status: .pending),
            MasterTodoItem(id: "1.1", number: "1.1", title: "Aufgabe", assignedAgent: "backend-developer", level: 1, status: .done)
        ]
        let text = OrchestratorLogic.formatPlan(goal: "Ziel X", todos: todos)
        XCTAssertTrue(text.contains("🎯 ZIEL: Ziel X"))
        XCTAssertTrue(text.contains("✓ 1.1 Aufgabe → backend-developer"))
        XCTAssertTrue(text.contains("○ 1. Phase"))
    }

    // MARK: - inputMatchesTrigger

    func testTriggerMatching() {
        XCTAssertTrue(OrchestratorLogic.inputMatchesTrigger("bitte code review machen", trigger: "code review"))
        XCTAssertTrue(OrchestratorLogic.inputMatchesTrigger("review this", trigger: "Reviewer"))
        XCTAssertFalse(OrchestratorLogic.inputMatchesTrigger("hallo welt", trigger: "code review"))
    }

    // MARK: - Regression-Guards (aus QA-Review)

    func testParsePlanJSONWithBracesInPreambleFallsBack() {
        // Bekanntes Limit des Brace-Extraktors: {} im Vortext → kaputter Slice → nil
        // (Caller fällt dann auf den Text-Parser zurück — dokumentiert als Regression-Guard).
        let raw = "Here is {my plan}:\n{\"ziel\":\"X\",\"schritte\":[{\"nr\":\"1\",\"titel\":\"T\",\"agent\":\"backend-developer\"}]}"
        XCTAssertNil(OrchestratorLogic.parsePlanJSON(raw, agents: agents))
    }

    func testOrchestratorLimitsSanity() {
        // Ein Tippfehler in den zentralen Limits würde sonst durch alle Tests rauschen.
        XCTAssertGreaterThan(OrchestratorLimits.defaultIdleTimeoutSec, 0)
        XCTAssertGreaterThanOrEqual(OrchestratorLimits.defaultMaxTurns, OrchestratorLimits.minAgentTurns)
        XCTAssertGreaterThan(OrchestratorLimits.historyMaxEntries, OrchestratorLimits.historyWindow)
        XCTAssertGreaterThan(OrchestratorLimits.maxAgents, 1)
        XCTAssertGreaterThan(OrchestratorLimits.foreignOutputCap, OrchestratorLimits.historyEntryCapPhase2)
    }

    func testParseMasterPlanStepWithoutAgentArrow() {
        // Sub-Item ohne "→ Agent" → Todo ohne Zuweisung, agentTasks leer
        // (so greift später korrekt der Gesamtauftrag-Fallback).
        let plan = "ZIEL: Test\n1. Phase\n   1.1 Aufgabe ohne Agent\n"
        let result = OrchestratorLogic.parseMasterPlan(plan, agents: agents)
        XCTAssertTrue(result.agentTasks.isEmpty)
        XCTAssertEqual(result.todos.first(where: { $0.level == 1 })?.assignedAgent, nil)
    }
}
