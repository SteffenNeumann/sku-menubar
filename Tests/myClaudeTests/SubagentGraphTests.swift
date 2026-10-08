import XCTest
@testable import myClaude

/// Agent-Flussbild: Lebenszyklus der Subagenten aus dem CLI-Stream und ein Layout,
/// in dem sich Karten nie überlappen.
final class SubagentGraphTests: XCTestCase {

    // MARK: - Lebenszyklus

    func testForegroundAgentRunsAndFinishes() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "code-reviewer", description: "Prüft Login")
        XCTAssertEqual(g.node("a1")?.status, .running)
        g.agentReturned(toolUseId: "a1", isError: false, text: "ok", resultStatus: "completed", tokens: 77_000)
        XCTAssertEqual(g.node("a1")?.status, .done)
        XCTAssertEqual(g.node("a1")?.tokens, 77_000)
        XCTAssertFalse(g.hasActive)
    }

    func testBackgroundAgentIsNotDoneUntilNotification() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "researcher", description: nil)
        g.agentReturned(toolUseId: "a1", isError: false, text: "Async agent launched successfully",
                        resultStatus: "async_launched", tokens: nil)
        XCTAssertEqual(g.node("a1")?.status, .background)
        g.streamEnded()
        XCTAssertEqual(g.node("a1")?.status, .background, "Hintergrund-Ende kann nach dem Stream-Ende kommen")
        g.taskFinished(toolUseId: "a1", status: "completed", tokens: 1234)
        XCTAssertEqual(g.node("a1")?.status, .done)
        XCTAssertEqual(g.node("a1")?.tokens, 1234)
    }

    func testDeniedAgentIsMarkedDenied() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "Explore", description: "Suche")
        g.agentReturned(toolUseId: "a1", isError: true,
                        text: "Agent type 'Explore' has been denied by permission rule 'Agent(Explore)' from cliArg.",
                        resultStatus: nil, tokens: nil)
        XCTAssertEqual(g.node("a1")?.status, .denied)
    }

    func testStreamEndStopsRunningForegroundAgents() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "qa-test-engineer", description: nil)
        g.streamEnded()
        XCTAssertEqual(g.node("a1")?.status, .failed)
        XCTAssertFalse(g.hasActive)
    }

    func testNestedAgentsAndUnknownParent() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "frontend-webdesigner", description: nil)
        g.agentStarted(toolUseId: "a2", parentToolUseId: "a1", type: "code-reviewer", description: nil)
        g.agentStarted(toolUseId: "a3", parentToolUseId: "gibt-es-nicht", type: "", description: nil)
        XCTAssertEqual(g.node("a2")?.parentId, "a1")
        XCTAssertNil(g.node("a3")?.parentId, "unbekannte Eltern → direkt am Haupt-Claude")
        XCTAssertEqual(g.node("a3")?.type, "general-purpose", "fehlender Typ = CLI-Standard")
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "x", description: nil)
        XCTAssertEqual(g.nodes.count, 3, "doppelter Start legt keine zweite Karte an")
    }

    func testToolUseFeedsSkillsTodosAndSteps() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "backend-developer", description: nil)
        g.toolUsed(byAgent: "a1", name: "Read", skill: nil, todoStatuses: nil)
        g.toolUsed(byAgent: "a1", name: "Skill", skill: "ponytail-lazy-code", todoStatuses: nil)
        g.toolUsed(byAgent: "a1", name: "Skill", skill: "ponytail-lazy-code", todoStatuses: nil)
        g.toolUsed(byAgent: "a1", name: "TodoWrite", skill: nil,
                   todoStatuses: ["completed", "in_progress", "pending", "completed"])
        g.toolUsed(byAgent: "fremd", name: "Bash", skill: nil, todoStatuses: nil)
        let n = g.node("a1")
        XCTAssertEqual(n?.toolCount, 4)
        XCTAssertEqual(n?.lastTool, "TodoWrite")
        XCTAssertEqual(n?.skills, ["ponytail-lazy-code"])
        XCTAssertEqual(n?.todosDone, 2)
        XCTAssertEqual(n?.todosTotal, 4)
    }

    // MARK: - Layout

    private func assertNoOverlap(_ g: SubagentGraph, file: StaticString = #filePath, line: UInt = #line) {
        let (frames, size) = SubagentLayout.frames(for: g)
        XCTAssertEqual(frames.count, g.nodes.count + 1, file: file, line: line)
        let rects = Array(frames.values)
        for i in rects.indices {
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rects[i]), "Karte außerhalb", file: file, line: line)
            for j in rects.indices where j > i {
                XCTAssertFalse(rects[i].intersects(rects[j]), "Karten überlappen: \(rects[i]) / \(rects[j])",
                               file: file, line: line)
            }
        }
    }

    func testLayoutEmptyGraphHasOnlyRoot() {
        let (frames, _) = SubagentLayout.frames(for: SubagentGraph())
        XCTAssertEqual(frames.count, 1)
        XCTAssertNotNil(frames[SubagentLayout.rootKey])
    }

    func testLayoutNeverOverlapsWideAndDeep() {
        var g = SubagentGraph()
        // 20 Subagenten auf 3 Ebenen (CLI-Standard: max. 20 parallel, Tiefe 3), ungleich verteilt.
        for i in 0..<6 { g.agentStarted(toolUseId: "l1-\(i)", parentToolUseId: nil, type: "t", description: nil) }
        for i in 0..<9 { g.agentStarted(toolUseId: "l2-\(i)", parentToolUseId: "l1-\(i % 2)", type: "t", description: nil) }
        for i in 0..<5 { g.agentStarted(toolUseId: "l3-\(i)", parentToolUseId: "l2-0", type: "t", description: nil) }
        XCTAssertEqual(g.nodes.count, 20)
        assertNoOverlap(g)
    }

    func testLayoutChildIsBelowParent() {
        var g = SubagentGraph()
        g.agentStarted(toolUseId: "a1", parentToolUseId: nil, type: "t", description: nil)
        g.agentStarted(toolUseId: "a2", parentToolUseId: "a1", type: "t", description: nil)
        let (f, _) = SubagentLayout.frames(for: g)
        XCTAssertLessThan(f[SubagentLayout.rootKey]!.maxY, f["a1"]!.minY)
        XCTAssertLessThan(f["a1"]!.maxY, f["a2"]!.minY)
    }

    // MARK: - Stream-Dekodierung

    private func decode(_ json: String) throws -> StreamEvent {
        try JSONDecoder().decode(StreamEvent.self, from: Data(json.utf8))
    }

    func testToolUseResultAsObjectAndAsString() throws {
        let obj = try decode(#"{"type":"user","tool_use_result":{"status":"async_launched","isAsync":true}}"#)
        XCTAssertEqual(obj.agentResultStatus, "async_launched")
        // Fehlerfall: tool_use_result ist ein String — das Event darf trotzdem nicht verloren gehen.
        let str = try decode(#"{"type":"user","tool_use_result":"Error: denied"}"#)
        XCTAssertNil(str.agentResultStatus)
    }

    func testTaskNotificationFields() throws {
        let e = try decode(#"{"type":"system","subtype":"task_notification","tool_use_id":"toolu_1","status":"completed","usage":{"total_tokens":4321,"tool_uses":3}}"#)
        XCTAssertEqual(e.taskToolUseId, "toolu_1")
        XCTAssertEqual(e.taskStatus, "completed")
        XCTAssertEqual(e.taskTokens, 4321)
    }

    func testTodoStatusesWithoutIds() throws {
        let e = try decode(#"{"type":"assistant","parent_tool_use_id":"toolu_1","message":{"content":[{"type":"tool_use","id":"t2","name":"TodoWrite","input":{"todos":[{"content":"a","status":"completed","activeForm":"A"},{"content":"b","status":"pending","activeForm":"B"}]}}]}}"#)
        XCTAssertEqual(e.parentToolUseId, "toolu_1")
        XCTAssertEqual(e.message?.content?.first?.toolInput?.todoStatuses, ["completed", "pending"])
    }
}
