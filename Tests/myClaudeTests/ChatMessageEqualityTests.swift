import XCTest
@testable import myClaude

/// `ChatMessage.==` muss jedes Feld vergleichen, das sich einzeln ändern kann — sonst gehen
/// solche Writes im Live-Betrieb verloren (fehlendes Agent-Badge, „Claude · Claude").
final class ChatMessageEqualityTests: XCTestCase {
    private func assertChangeDetected(_ mutate: (inout ChatMessage) -> Void,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let original = ChatMessage(role: .assistant, content: "x")
        var changed = original
        mutate(&changed)
        XCTAssertNotEqual(original, changed, file: file, line: line)
    }

    func testModelChangeDetected()     { assertChangeDetected { $0.model = "claude-sonnet-4-6" } }
    func testAgentNameChangeDetected() { assertChangeDetected { $0.agentName = "project-manager" } }
    func testSourceChangeDetected()    { assertChangeDetected { $0.source = .copilot } }
    func testTokensChangeDetected()    { assertChangeDetected { $0.inputTokens = 10 } }
    func testCostChangeDetected()      { assertChangeDetected { $0.costUsd = 0.01 } }
    func testSubtypeChangeDetected()   { assertChangeDetected { $0.resultSubtype = "max_turns" } }

    func testIdenticalCopyIsEqual() {
        let msg = ChatMessage(role: .assistant, content: "x")
        XCTAssertEqual(msg, msg)
    }
}
