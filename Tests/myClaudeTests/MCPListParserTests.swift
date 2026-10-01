import XCTest
@testable import myClaude

@MainActor
final class MCPListParserTests: XCTestCase {

    // Ausschnitt aus echter `claude mcp list`-Ausgabe (CLI 2.1.x, Okt. 2026).
    private let sample = """
    Checking MCP server health…

    claude.ai Claude Docs: https://api.anthropic.com/v1/pages/mcp - ✔ Connected
    plugin:engineering:slack: https://mcp.slack.com/mcp (HTTP) - ! Needs authentication
    plugin:engineering:google calendar:  (HTTP) - - Not configured
    stitch: https://stitch.googleapis.com/mcp (HTTP) - ✘ Failed to connect — Incompatible auth server
    penpot: http://localhost:4401/sse  - ✘ Failed to connect — ENOENT: no such file or directory
    playwright: npx -y @playwright/mcp@latest - ✔ Connected
    magic-21st-dev: npx -y @21st-dev/magic@latest - ✘ Failed to connect — -32001: Not authenticated (x-api-key / Bearer).
    """

    func testSkipsHealthCheckHeader() {
        let names = ClaudeCLIService.parseMCPList(sample).map(\.name)
        XCTAssertFalse(names.contains { $0.hasPrefix("Checking") })
        XCTAssertEqual(names.count, 7)
    }

    func testKeepsFullPluginNames() {
        let names = ClaudeCLIService.parseMCPList(sample).map(\.name)
        XCTAssertTrue(names.contains("plugin:engineering:slack"))
        XCTAssertTrue(names.contains("plugin:engineering:google calendar"))
        XCTAssertFalse(names.contains("plugin"))
    }

    func testFailedIsNotConnected() {
        let byName = Dictionary(uniqueKeysWithValues: ClaudeCLIService.parseMCPList(sample).map { ($0.name, $0) })
        XCTAssertEqual(byName["playwright"]?.status, .connected)
        XCTAssertEqual(byName["plugin:engineering:slack"]?.status, .needsAuth)
        if case .error = byName["stitch"]?.status {} else { XCTFail("stitch muss Fehler sein") }
        if case .error = byName["penpot"]?.status {} else { XCTFail("penpot muss Fehler sein") }
        if case .error = byName["magic-21st-dev"]?.status {} else { XCTFail("21st muss Fehler sein") }
    }

    func testUrlAndTransport() {
        let byName = Dictionary(uniqueKeysWithValues: ClaudeCLIService.parseMCPList(sample).map { ($0.name, $0) })
        XCTAssertEqual(byName["stitch"]?.type, "http")
        XCTAssertEqual(byName["stitch"]?.detail, "https://stitch.googleapis.com/mcp")
        XCTAssertEqual(byName["penpot"]?.detail, "http://localhost:4401/sse")
        // Klammer in der Fehlermeldung darf nicht als Transport gelesen werden
        XCTAssertEqual(byName["magic-21st-dev"]?.type, "unknown")
        XCTAssertEqual(byName["magic-21st-dev"]?.detail, "npx -y @21st-dev/magic@latest")
    }

    func testOldFormatStillWorks() {
        let s = ClaudeCLIService.parseMCPList("  foo (stdio): Connected")
        XCTAssertEqual(s.first?.name, "foo")
        XCTAssertEqual(s.first?.type, "stdio")
        XCTAssertEqual(s.first?.status, .connected)
    }
}
