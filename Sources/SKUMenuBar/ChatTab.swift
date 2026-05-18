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
    // TMetric: per-tab project association + timer state
    var tmetricProjectId:       Int?    = nil
    var tmetricProjectName:     String  = ""
    var tmetricIsTimerRunning:  Bool    = false
    var tmetricTimerStart:      Date?   = nil
    var tmetricRunningEntryId:  Int?    = nil
    var tmetricTimerError:      String? = nil
}
