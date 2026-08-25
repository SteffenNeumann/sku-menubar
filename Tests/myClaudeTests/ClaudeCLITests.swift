import XCTest
@testable import myClaude

final class ClaudeCLIVersionTests: XCTestCase {

    func testParsesVersionOutput() {
        // Genau das gibt `claude --version` aus.
        XCTAssertEqual(ClaudeCLIVersion(parsing: "2.1.243 (Claude Code)"), ClaudeCLIVersion(2, 1, 243))
        XCTAssertEqual(ClaudeCLIVersion(parsing: "  2.1.186 (Claude Code)\n"), ClaudeCLIVersion(2, 1, 186))
        XCTAssertEqual(ClaudeCLIVersion(parsing: "v10.0.7"), ClaudeCLIVersion(10, 0, 7))
    }

    func testRejectsUnparsableOutput() {
        XCTAssertNil(ClaudeCLIVersion(parsing: ""))
        XCTAssertNil(ClaudeCLIVersion(parsing: "command not found"))
        XCTAssertNil(ClaudeCLIVersion(parsing: "2.1"))   // Patch fehlt
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

final class ArtifactRefTests: XCTestCase {

    func testExtractsURLFromToolResult() {
        let text = "Published to https://claude.ai/code/artifact/abc-123 — share it with your team."
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: text),
                       "https://claude.ai/code/artifact/abc-123")
    }

    func testStripsTrailingMarkdownAndPunctuation() {
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: "(https://claude.ai/x/1)"),
                       "https://claude.ai/x/1")
        XCTAssertEqual(ArtifactRef.firstArtifactURL(in: "[Link](https://claude.ai/x/2), fertig"),
                       "https://claude.ai/x/2")
    }

    func testIgnoresTextWithoutArtifactURL() {
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "kein Link hier"))
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "https://example.com/claude.ai/nope"))
        XCTAssertNil(ArtifactRef.firstArtifactURL(in: "https://claude.ai/"))   // nur die Basis
    }

    func testBuildsRefOnlyFromFinishedArtifactCall() {
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
}
