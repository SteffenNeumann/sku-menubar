import SwiftUI

struct ChatTab: Identifiable {
    var id = UUID()
    var title: String = "Neue Session"
    var sessionId: String?
    var messages: [ChatMessage] = []
    var model: String = "claude-sonnet-4-6"
    var agentId: String = ""
    var personaId: String = ""   // selected persona for post-task validation
    var isStreaming: Bool = false
    var error: String?
    var inputText: String = ""
    var workingDirectory: String?
    var orchestratorMode: Bool = false
}
