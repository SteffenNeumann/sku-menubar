import XCTest
@testable import myClaude

final class ClaudeCLIVersionTests: XCTestCase {

    func testParsesVersionOutput() {
        // Genau das gibt `claude --version` aus.
        XCTAssertEqual(ClaudeCLIVersion(parsing: "2.1.243 (Claude Code)"), ClaudeCLIVersion(2, 1, 243))
        XCTAssertEqual(ClaudeCLIVersion(parsing: "  2.1.186 (Claude Code)\n"), ClaudeCLIVersion(2, 1, 186))
        XCTAssertEqual(ClaudeCLIVersion(parsing: "v10.0.7"), ClaudeCLIVersion(10, 0, 7))
    }

    func testFindsVersionAfterLeadingNoise() {
        // Eine einzelne Zahl vor der Version brach den alten Scanner ab.
        XCTAssertEqual(ClaudeCLIVersion(parsing: "Claude Code v2 build 2.1.243"),
                       ClaudeCLIVersion(2, 1, 243))
        XCTAssertEqual(ClaudeCLIVersion(parsing: "abc 2.1.243"), ClaudeCLIVersion(2, 1, 243))
    }

    func testRejectsUnparsableOutput() {
        XCTAssertNil(ClaudeCLIVersion(parsing: ""))
        XCTAssertNil(ClaudeCLIVersion(parsing: "command not found"))
        XCTAssertNil(ClaudeCLIVersion(parsing: "2.1"))     // Patch fehlt
        XCTAssertNil(ClaudeCLIVersion(parsing: "2..1.3"))
        // Vierteilig ist kein CLI-Format — lieber nil als ein geratenes Teilstück.
        XCTAssertNil(ClaudeCLIVersion(parsing: "1.2.3.4"))
    }

    func testAcceptsLeadingZeroes() {
        XCTAssertEqual(ClaudeCLIVersion(parsing: "2.01.3"), ClaudeCLIVersion(2, 1, 3))
    }

    func testHugeNumbersYieldNilNotZero() {
        // Der alte Parser machte aus dem Int-Overflow still eine 0 und lieferte
        // "0.1.2" — eine plausibel aussehende, falsche Version, die jedes Gate sperrt.
        XCTAssertNil(ClaudeCLIVersion(parsing: "99999999999999999999.1.2"))
    }

    func testIgnoresNonASCIIDigits() {
        // isNumber ist true für ١٢٣, Int() parst sie nicht → früher 0.0.0.
        XCTAssertNil(ClaudeCLIVersion(parsing: "١٢٣.١.٢"))
    }

    func testOrdersByComponent() {
        // Rein lexikografisch wäre "2.1.9" > "2.1.243" — deshalb der Zahlenvergleich.
        XCTAssertTrue(ClaudeCLIVersion(2, 1, 9) < ClaudeCLIVersion(2, 1, 243))
        XCTAssertTrue(ClaudeCLIVersion(2, 1, 243) < ClaudeCLIVersion(2, 2, 0))
        XCTAssertTrue(ClaudeCLIVersion(1, 9, 9) < ClaudeCLIVersion(2, 0, 0))
    }

    func testDesignCanvasGate() {
        let min = ClaudeFeature.designCanvas.minVersion
        XCTAssertEqual(min, ClaudeCLIVersion(2, 1, 233))
        XCTAssertFalse(ClaudeCLIVersion(2, 1, 186) >= min)   // Stand vor dem Update
        XCTAssertTrue(ClaudeCLIVersion(2, 1, 243) >= min)
    }
}

final class SlashRoutingTests: XCTestCase {

    func testExtractsCommandWord() {
        XCTAssertEqual(SlashRouting.commandWord(of: "/design"), "/design")
        XCTAssertEqual(SlashRouting.commandWord(of: "/design Login-Screen"), "/design")
        XCTAssertEqual(SlashRouting.commandWord(of: "/DESIGN Login"), "/design")
        // Shift+Enter erzeugt einen Newline, kein Leerzeichen — das umging das alte Gate.
        XCTAssertEqual(SlashRouting.commandWord(of: "/design\nLogin-Screen"), "/design")
        XCTAssertNil(SlashRouting.commandWord(of: "kein Befehl"))
    }

    func testSeparatesArguments() {
        XCTAssertEqual(SlashRouting.arguments(of: "/design Login-Screen für App X"),
                       "Login-Screen für App X")
        XCTAssertEqual(SlashRouting.arguments(of: "/design\nLogin-Screen"), "Login-Screen")
        XCTAssertEqual(SlashRouting.arguments(of: "/design"), "")
    }

    func testRoutesKnownCommandsOnly() {
        XCTAssertTrue(SlashRouting.needsLocalHandling("/design Login-Screen"))
        XCTAssertTrue(SlashRouting.needsLocalHandling("/design\nLogin-Screen"))
        XCTAssertTrue(SlashRouting.needsLocalHandling("/compact"))
        XCTAssertTrue(SlashRouting.needsLocalHandling("/agent code-reviewer"))
        XCTAssertTrue(SlashRouting.needsLocalHandling("/files *.swift"))
    }

    func testLeavesEverythingElseAlone() {
        // Dateipfade sind keine Befehle.
        XCTAssertFalse(SlashRouting.needsLocalHandling("/Users/steffen/Documents/x.swift"))
        // Unbekannte Befehle gehen unangetastet an die CLI — nicht durch das lokale
        // Handling, das sonst das Eingabefeld leert.
        XCTAssertFalse(SlashRouting.needsLocalHandling("/foo"))
        XCTAssertFalse(SlashRouting.needsLocalHandling("/designsystem prüfen"))
        XCTAssertFalse(SlashRouting.needsLocalHandling("normaler Text"))
    }
}

final class ArtifactRefTests: XCTestCase {

    func testExtractsURLFromToolResult() {
        let text = "Published to https://claude.ai/code/artifact/abc-123 — share it with your team."
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: text),
                       "https://claude.ai/code/artifact/abc-123")
    }

    func testStripsTrailingPunctuation() {
        // Ein Satz, der mit Punkt endet, reicht für eine kaputte URL.
        for (text, expected) in [
            ("Fertig: https://claude.ai/x/1.",       "https://claude.ai/x/1"),
            ("Fertig: https://claude.ai/x/1!",       "https://claude.ai/x/1"),
            ("Siehe https://claude.ai/x/1: dort",    "https://claude.ai/x/1"),
            ("(https://claude.ai/x/1)",              "https://claude.ai/x/1"),
            ("[Link](https://claude.ai/x/1), fertig","https://claude.ai/x/1"),
        ] {
            XCTAssertEqual(ArtifactRef.firstArtifactURL(in: text), expected, "bei: \(text)")
        }
    }

    func testStripsMarkdownEmphasis() {
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: "**https://claude.ai/x/1**"),
                       "https://claude.ai/x/1")
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: "`https://claude.ai/x/1`"),
                       "https://claude.ai/x/1")
    }

    func testIgnoresTextWithoutArtifactURL() {
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "kein Link hier"))
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "https://example.com/claude.ai/nope"))
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "https://claude.ai/"))   // nur die Basis
    }

    func testBuildsRefOnlyFromFinishedPublish() {
        var call = ToolCall(name: "Artifact", input: "/tmp/spring-menu-poster.html")
        XCTAssertNil(ArtifactRef(toolCall: call), "ohne tool_result gibt es noch keine URL")

        call.result = "Published: https://claude.ai/code/artifact/xyz"
        let ref = ArtifactRef(toolCall: call)
        XCTAssertEqual(ref?.url, "https://claude.ai/code/artifact/xyz")
        XCTAssertEqual(ref?.title, "spring-menu-poster.html")

        var other = ToolCall(name: "Bash", input: "echo https://claude.ai/code/artifact/xyz")
        other.result = "https://claude.ai/code/artifact/xyz"
        XCTAssertNil(ArtifactRef(toolCall: other), "nur Artifact-Calls ergeben eine Karte")
    }

    func testIgnoresNonPublishingArtifactActions() {
        // `action: "list"` liefert lauter claude.ai-URLs, veröffentlicht aber nichts.
        var listing = ToolCall(name: "Artifact", input: "action: list · limit: 25")
        listing.result = "https://claude.ai/code/artifact/aaa — Poster\nhttps://claude.ai/code/artifact/bbb — Memo"
        XCTAssertNil(ArtifactRef(toolCall: listing))
    }

    func testDeduplicatesRepublishOfSameURL() {
        // Ein Redeploy publiziert auf dieselbe URL; ForEach über Identifiable
        // verträgt keine doppelten IDs.
        var first  = ToolCall(name: "Artifact", input: "/tmp/poster.html")
        first.result = "https://claude.ai/code/artifact/same"
        var second = ToolCall(name: "Artifact", input: "/tmp/poster.html")
        second.result = "Updated: https://claude.ai/code/artifact/same"

        var msg = ChatMessage(role: .assistant, content: "")
        msg.toolCalls = [first, second]
        msg.refreshArtifacts()
        XCTAssertEqual(msg.artifacts.count, 1)
        XCTAssertEqual(msg.artifacts.first?.url, "https://claude.ai/code/artifact/same")
    }
}

final class StreamToolInputFallbackTests: XCTestCase {

    private func decode(_ json: String) throws -> StreamToolInput {
        try JSONDecoder().decode(StreamToolInput.self, from: Data(json.utf8))
    }

    func testKnownFieldsStillWin() throws {
        let input = try decode(#"{"file_path":"/tmp/a.html","title":"Poster"}"#)
        XCTAssertEqual(input.displayText, "/tmp/a.html")
    }

    func testUnknownFieldsBecomeSummary() throws {
        // Vorher: Chip mit leerem Text, weil kein Feld passte.
        let input = try decode(#"{"title":"Poster","favicon":"🎨"}"#)
        XCTAssertEqual(input.displayText, "favicon: 🎨 · title: Poster")
    }

    func testEmptyInputStaysNil() throws {
        XCTAssertNil(try decode("{}").displayText)
    }

    func testNeverLeaksSecrets() throws {
        // MCP-Tools mit api-key/token-Parametern würden den Wert sonst sichtbar
        // in den Chat schreiben — heikel bei Screenshots und Screensharing.
        let input = try decode(#"{"api_key":"sk-ant-api03-SECRET","endpoint":"https://x"}"#)
        XCTAssertEqual(input.displayText, "endpoint: https://x")
        XCTAssertNil(try decode(#"{"password":"hunter2"}"#).displayText)
        XCTAssertNil(try decode(#"{"authToken":"abc"}"#).displayText)
    }

    func testNotebookPathIsAPathNotSummaryNoise() throws {
        // NotebookEdit heißt notebook_path; ohne den Key landete die rawSummary
        // ("cell_id: c1 · …") als erfundener Pfad im Datei-Panel.
        let input = try decode(#"{"notebook_path":"/a.ipynb","cell_id":"c1","cell_type":"code"}"#)
        XCTAssertEqual(input.displayText, "/a.ipynb")
        XCTAssertEqual(input.pathLikeValue, "/a.ipynb")
    }

    func testSummaryIsNeverTreatedAsPath() throws {
        XCTAssertNil(try decode(#"{"favicon":"🎨"}"#).pathLikeValue)
    }

    func testToleratesNonObjectInput() {
        // Der eigene Decoder darf nicht strenger sein als der synthetisierte:
        // StreamContent dekodiert toolInput mit `try?` und erwartet Fehlertoleranz.
        for json in ["[]", #""text""#, "null", "42"] {
            XCTAssertNil(try? decode(json), "sollte nil ergeben, nicht crashen: \(json)")
        }
    }
}

final class AgentTriggeringTests: XCTestCase {

    func testTriggersWhenNothingChosen() {
        XCTAssertTrue(AgentTriggering.mayAutoTrigger(
            selectedAgent: "", suppressed: false,
            text: "Bau mir ein Design", orchestratorActive: false))
    }

    func testRespectsExplicitNoAgent() {
        // Der gemeldete Fehler: "Kein Agent" setzte nur selectedAgent = "" — genau den
        // Zustand, in dem der Trigger greift. Beim nächsten Tastendruck war er wieder da.
        XCTAssertFalse(AgentTriggering.mayAutoTrigger(
            selectedAgent: "", suppressed: true,
            text: "Bau mir ein Design", orchestratorActive: false))
    }

    func testNeverOverridesAManualChoice() {
        XCTAssertFalse(AgentTriggering.mayAutoTrigger(
            selectedAgent: "qa-test-engineer", suppressed: false,
            text: "Bau mir ein Design", orchestratorActive: false))
    }

    func testStaysQuietDuringOrchestrationAndOnEmptyInput() {
        XCTAssertFalse(AgentTriggering.mayAutoTrigger(
            selectedAgent: "", suppressed: false,
            text: "Status", orchestratorActive: true))
        XCTAssertFalse(AgentTriggering.mayAutoTrigger(
            selectedAgent: "", suppressed: false,
            text: "", orchestratorActive: false))
    }
}
