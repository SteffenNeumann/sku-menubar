import XCTest
@testable import myClaude

/// Belege stammen aus echten `claude --output-format stream-json`-Läufen (CLI 2.1.186).
final class SkillTrackingTests: XCTestCase {

    private func decodeEvent(_ json: String) throws -> StreamEvent {
        try JSONDecoder().decode(StreamEvent.self, from: Data(json.utf8))
    }

    /// Skill-Aufruf des Haupt-Agenten: Name muss aus input.skill kommen.
    func testSkillToolUseIsDecoded() throws {
        let json = """
        {"type":"assistant","parent_tool_use_id":null,"session_id":"s1",
         "message":{"role":"assistant","content":[
           {"type":"tool_use","id":"toolu_1","name":"Skill",
            "input":{"skill":"ui-ux-pro-max","args":"plan redesign"},
            "caller":{"type":"direct"}}]}}
        """
        let event = try decodeEvent(json)
        let block = try XCTUnwrap(event.message?.content?.first)
        XCTAssertEqual(block.name, "Skill")
        XCTAssertEqual(block.toolInput?.skill, "ui-ux-pro-max")
        XCTAssertEqual(block.toolInput?.args, "plan redesign")
        // displayText trägt den Skill-Namen — vorher war es nil (leerer Badge).
        XCTAssertEqual(block.toolInput?.displayText, "ui-ux-pro-max")
        XCTAssertNil(event.subagentType)
    }

    /// Sub-Agent: subagent_type steht top-level auf dem Event, nicht im Block.
    func testSubagentSkillCarriesSubagentType() throws {
        let json = """
        {"type":"assistant","parent_tool_use_id":"toolu_parent","session_id":"s1",
         "subagent_type":"general-purpose","task_description":"Skill-Test",
         "message":{"role":"assistant","content":[
           {"type":"tool_use","id":"toolu_2","name":"Skill",
            "input":{"skill":"10k-website-checklist"},"caller":{"type":"direct"}}]}}
        """
        let event = try decodeEvent(json)
        XCTAssertEqual(event.subagentType, "general-purpose")
        XCTAssertEqual(event.parentToolUseId, "toolu_parent")
        XCTAssertEqual(event.message?.content?.first?.toolInput?.skill, "10k-website-checklist")
    }

    /// Agent-Spawn: subagent_type liegt hier IM Input und speist displayText.
    func testAgentSpawnInputExposesSubagentType() throws {
        let json = """
        {"type":"assistant","session_id":"s1","message":{"role":"assistant","content":[
          {"type":"tool_use","id":"toolu_3","name":"Agent",
           "input":{"description":"Recherche","prompt":"…","subagent_type":"researcher"}}]}}
        """
        let block = try XCTUnwrap(try decodeEvent(json).message?.content?.first)
        XCTAssertEqual(block.toolInput?.subagentType, "researcher")
        XCTAssertEqual(block.toolInput?.displayText, "researcher")
    }

    /// Bestehende Tools dürfen sich nicht verändert haben.
    func testExistingToolsUnaffected() throws {
        let json = """
        {"type":"assistant","session_id":"s1","message":{"role":"assistant","content":[
          {"type":"tool_use","id":"t","name":"Bash","input":{"command":"git status"}},
          {"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/tmp/a.txt"}}]}}
        """
        let blocks = try XCTUnwrap(try decodeEvent(json).message?.content)
        XCTAssertEqual(blocks[0].toolInput?.displayText, "git status")
        XCTAssertEqual(blocks[1].toolInput?.displayText, "/tmp/a.txt")
    }

    // MARK: - noteSkillUse

    func testNoteSkillUseDeduplicatesPerAgent() {
        var msg = ChatMessage(role: .assistant, content: "")
        msg.noteSkillUse("shadcn")
        msg.noteSkillUse("shadcn")                       // exaktes Duplikat → ignoriert
        msg.noteSkillUse("shadcn", agent: "frontend")    // anderer Agent → eigener Eintrag
        msg.noteSkillUse("  ")                           // leer → ignoriert
        XCTAssertEqual(msg.usedSkills, [
            SkillUse(name: "shadcn", agent: nil),
            SkillUse(name: "shadcn", agent: "frontend"),
        ])
    }

    func testNoteSkillUseTrimsAndKeepsOrder() {
        var msg = ChatMessage(role: .assistant, content: "")
        msg.noteSkillUse(" grill-me\n")
        msg.noteSkillUse("ponytail-lazy-code")
        XCTAssertEqual(msg.usedSkills.map(\.name), ["grill-me", "ponytail-lazy-code"])
    }

    /// Equatable muss usedSkills berücksichtigen, sonst rendert SwiftUI nicht neu.
    func testEqualityReactsToSkillChange() {
        let base = ChatMessage(role: .assistant, content: "x")
        var changed = base
        changed.noteSkillUse("mcp")
        XCTAssertNotEqual(base, changed)
    }
}
