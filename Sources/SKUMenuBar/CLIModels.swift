import Foundation
import SwiftUI

// MARK: - App Navigation

enum AppSection: String, CaseIterable, Hashable {
    case dashboard   = "Dashboard"
    case chat        = "Chat"
    case history     = "Verlauf"
    case agents      = "Agents"
    case mcp         = "MCP Server"
    case codeReview  = "Code Review"
    case files       = "Files"
    case notes       = "Notizen"
    case tasks       = "Aufgaben"
    case settings    = "Einstellungen"

    var icon: String {
        switch self {
        case .dashboard:  return "square.grid.2x2.fill"
        case .chat:       return "bubble.left.and.bubble.right.fill"
        case .history:    return "clock.fill"
        case .agents:     return "cpu.fill"
        case .mcp:        return "network"
        case .codeReview: return "checklist"
        case .files:      return "folder.fill"
        case .notes:      return "note.text"
        case .tasks:      return "checkmark.square.fill"
        case .settings:   return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .dashboard:  return .blue
        case .chat:       return .green
        case .history:    return .orange
        case .agents:     return .purple
        case .mcp:        return .cyan
        case .codeReview: return .mint
        case .files:      return .indigo
        case .notes:      return .yellow
        case .tasks:      return .green
        case .settings:   return .gray
        }
    }
}

// MARK: - Attached Files

struct AttachedFile: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var isImage: Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext)
    }
    var isText: Bool {
        let ext = url.pathExtension.lowercased()
        let textExts = ["txt", "md", "swift", "py", "js", "ts", "tsx", "jsx",
                        "json", "yaml", "yml", "toml", "sh", "bash", "zsh",
                        "html", "css", "scss", "xml", "csv", "go", "rs", "rb",
                        "java", "kt", "c", "cpp", "h", "hpp", "sql", "env",
                        "gitignore", "dockerfile", "makefile", "log"]
        return textExts.contains(ext) || url.pathExtension.isEmpty
    }
}

// MARK: - Notes & Tasks

enum NoteType: String, Codable, CaseIterable {
    case note = "Notiz"
    case task = "Aufgabe"
}

struct TaskLine: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String = ""
    var done: Bool = false
}

struct NoteItem: Identifiable, Codable {
    var id: UUID = UUID()
    var type: NoteType = .note
    var title: String = ""
    var body: String = ""
    var done: Bool = false
    var createdAt: Date = Date()
    var tags: [String] = []
    var taskLines: [TaskLine] = []
}

// MARK: - Chat Messages

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var role: MessageRole
    var content: String
    var toolCalls: [ToolCall] = []
    var isStreaming: Bool = false
    var model: String?
    var source: ChatProviderSource?
    var costUsd: Double?
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var timestamp = Date()
    var gitDiff: String?          // populated after tool calls that modify files
    var gitDiffExpanded: Bool = false

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
            && lhs.gitDiff == rhs.gitDiff && lhs.toolCalls.count == rhs.toolCalls.count
    }
}

enum MessageRole: Equatable {
    case user, assistant, system
}

enum ChatProviderSource: String, Codable {
    case claude
    case copilot

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .copilot: return "Copilot"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .copilot: return "arrow.triangle.2.circlepath"
        }
    }
}

struct ToolCall: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let input: String
    var result: String?

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Stream Events (claude --output-format stream-json)

struct StreamEvent: Decodable {
    let type: String
    let subtype: String?
    let sessionId: String?
    let message: StreamMessage?

    // result event fields
    let costUsd: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let isError: Bool?
    let result: String?    // text result in "result" events
    let error: String?     // e.g. "rate_limit" in assistant events

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, result, error
        case sessionId    = "session_id"
        case costUsd      = "cost_usd"
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
        case isError      = "is_error"
    }
}

struct StreamMessage: Decodable {
    let role: String?
    let content: [StreamContent]?
    let model: String?
    let usage: StreamUsage?
}

struct StreamContent: Decodable {
    let type: String    // "text", "tool_use", "tool_result", "thinking"
    let text: String?
    let thinking: String?
    let id: String?
    let name: String?
}

struct StreamUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Chat History

struct ProjectHistory: Identifiable, Hashable {
    let id: String          // project path
    let path: String
    var sessions: [HistorySession]
    var lastActivity: Date { sessions.first?.timestamp ?? .distantPast }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct HistorySession: Identifiable, Hashable {
    let id: String          // session uuid
    let sessionId: String
    let projectPath: String
    let preview: String     // first user message
    let timestamp: Date
    var messageCount: Int
}

struct HistoryMessage: Identifiable {
    let id: String
    let parentId: String?
    let role: MessageRole
    let content: String
    let toolCalls: [ToolCall]
    let timestamp: Date
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheTokens: Int
}

// MARK: - History JSONL parsing helpers

struct RawCLIMessage: Decodable {
    let type: String?
    let uuid: String?
    let parentUuid: String?
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let message: RawMessage?

    enum CodingKeys: String, CodingKey {
        case type, uuid, timestamp, sessionId = "sessionId", cwd, message
        case parentUuid = "parentUuid"
    }
}

struct RawMessage: Decodable {
    let role: String?
    let content: RawContent?
    let model: String?
    let usage: RawUsage?
}

// Content can be String or [ContentItem]
enum RawContent: Decodable {
    case text(String)
    case blocks([RawContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else if let arr = try? container.decode([RawContentBlock].self) {
            self = .blocks(arr)
        } else {
            self = .text("")
        }
    }

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .blocks(let blocks):
            return blocks.compactMap { block in
                switch block.type {
                case "text": return block.text
                case "tool_use": return "[\(block.name ?? "tool")]"
                case "tool_result":
                    if let content = block.content {
                        switch content {
                        case .text(let t): return t
                        case .blocks(let b): return b.compactMap(\.text).joined()
                        }
                    }
                    return nil
                default: return nil
                }
            }.joined(separator: "\n")
        }
    }
}

struct RawContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let content: RawContent?
    let thinking: String?
}

struct RawUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens              = "input_tokens"
        case outputTokens             = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens     = "cache_read_input_tokens"
    }
}

// MARK: - Global History Entry

struct GlobalHistoryEntry: Decodable {
    let display: String?
    let timestamp: Double?
    let project: String?
    let sessionId: String?
}

// MARK: - Agents

struct AgentDefinition: Identifiable, Hashable {
    let id: String              // filename without .md
    let name: String
    let description: String
    let model: String
    let color: String?
    let memory: String?
    let portrait: String?       // e.g. "ap03"
    let triggers: [String]      // trigger keywords
    let promptBody: String
    let filePath: String
    let projectDirectory: String?  // working directory when running
    // Scheduling
    let schedule: String?       // "hourly", "daily", "weekly", "@HH:MM" (daily at time)
    let isActive: Bool          // scheduling enabled
    let timeoutMinutes: Int     // max run time in minutes (default 30)
    // Research
    let researchUpdatedAt: String?  // date string from "🔬 Research Updates" section

    /// Returns explicit triggers if set, otherwise auto-extracts keywords from content.
    var effectiveTriggers: [String] {
        if !triggers.isEmpty { return triggers }
        return Self.extractKeywords(from: description + " " + promptBody, limit: 6)
    }

    private static let stopWords: Set<String> = [
        "this","that","with","from","have","when","your","they","been","will","more",
        "also","into","than","then","them","some","what","about","after","before",
        "which","there","their","these","those","would","could","should","other",
        "just","like","need","used","using","work","tasks","task","agent","agents",
        "include","includes","including","such","both","each","were","make","made",
        "take","over","only","very","much","many","most","well","even","time","here",
        "where","while","through","without","between","user","users","help","helps",
        "helping","best","high","level","based","build","create","ensure","provide",
        "handle","follow","write","adds","added","adding","given","gives","allows",
        "across","against","along","already","always","another","apply","applies",
        "around","available","avoid","because","being","below","beyond","called",
        "cases","certain","changes","check","checks","common","complex","contains",
        "correct","current","directly","doing","during","either","ensures","errors",
        "every","example","examples","existing","experience","file","files","first",
        "focus","following","format","framework","full","further","general","getting",
        "given","goes","good","handles","having","however","implement","important",
        "instead","keep","keeps","large","later","less","logic","long","maintain",
        "making","means","might","must","never","next","once","parts","pass","place",
        "point","possible","rather","real","related","return","same","second","side",
        "since","small","specific","still","style","support","system","three","toward",
        "under","unless","until","upon","usually","various","want","whenever","whether",
        "within","works","yet","your","zudem","auch","dass","damit","oder","wird",
        "werden","nicht","eine","einen","einem","einer","eines","haben","sein","kann",
        "kann","noch","aber","wenn","nach","beim","durch","über","unter","sowie",
        "allen","immer","alle","kein","keine","keinen","schon","dann","hier","mehr"
    ]

    static func extractKeywords(from text: String, limit: Int) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: #"[^\w\s\-]"#, with: " ", options: .regularExpression)
            .lowercased()
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
        var seen = Set<String>()
        var result: [String] = []
        for word in words {
            let w = word.trimmingCharacters(in: .init(charactersIn: "-_"))
            guard w.count >= 4,
                  !stopWords.contains(w),
                  !w.allSatisfy(\.isNumber),
                  seen.insert(w).inserted else { continue }
            result.append(w.prefix(1).uppercased() + w.dropFirst())
            if result.count == limit { break }
        }
        return result
    }

    var modelBadgeColor: Color {
        switch model.lowercased() {
        case "opus":   return .purple
        case "sonnet": return .blue
        case "haiku":  return .green
        default:       return .gray
        }
    }

    var dotColor: Color {
        switch color?.lowercased() {
        case "purple": return .purple
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "cyan":   return .cyan
        case "yellow": return .yellow
        case "pink":   return Color(red: 0.95, green: 0.20, blue: 0.55)
        case "indigo": return .indigo
        case "teal":   return .teal
        default:       return .gray
        }
    }
}

// MARK: - Agent Draft (editor model)

struct AgentDraft {
    var id: String = ""
    var name: String = ""
    var description: String = ""
    var model: String = "sonnet"
    var color: String = ""
    var memory: String = ""
    var portrait: String = ""
    var triggers: String = ""   // comma-separated
    var promptBody: String = ""
    var schedule: String = ""
    var isActive: Bool = false
    var timeoutMinutes: String = ""  // empty = default (30 min)
    var projectDirectory: String = ""

    init() {}

    init(agent: AgentDefinition) {
        id          = agent.id
        name        = agent.name
        description = agent.description
        model       = agent.model
        color       = agent.color  ?? ""
        memory      = agent.memory ?? ""
        portrait    = agent.portrait ?? ""
        triggers    = agent.triggers.joined(separator: ", ")
        promptBody  = agent.promptBody
        schedule    = agent.schedule ?? ""
        isActive    = agent.isActive
        timeoutMinutes = agent.timeoutMinutes == 30 ? "" : String(agent.timeoutMinutes)
        projectDirectory = agent.projectDirectory ?? ""
    }
}

// MARK: - Scheduled Task Log

enum ScheduledTaskStatus: String, Codable {
    case running, success, failed

    var label: String {
        switch self {
        case .running: return "Läuft"
        case .success: return "Erfolg"
        case .failed:  return "Fehler"
        }
    }

    var color: Color {
        switch self {
        case .running: return .orange
        case .success: return .green
        case .failed:  return .red
        }
    }

    var icon: String {
        switch self {
        case .running: return "clock.badge.fill"
        case .success: return "checkmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        }
    }
}

struct ScheduledTaskLogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var agentId: String
    var startedAt: Date
    var finishedAt: Date?
    var status: ScheduledTaskStatus
    var output: String = ""
    var error: String = ""
}

// MARK: - MCP Servers

struct MCPServerConfig {
    let name: String
    let transport: String
    let commandOrUrl: String
    let args: [String]
    let headers: [String]
    let envVars: [String]
}

struct MCPServer: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let status: MCPStatus
    let detail: String
}

enum MCPStatus: Hashable {
    case connected, needsAuth, error(String), unknown

    var label: String {
        switch self {
        case .connected:     return "Verbunden"
        case .needsAuth:     return "Auth. erforderlich"
        case .error(let e):  return "Fehler: \(e)"
        case .unknown:       return "Unbekannt"
        }
    }

    var color: Color {
        switch self {
        case .connected:  return .green
        case .needsAuth:  return .orange
        case .error:      return .red
        case .unknown:    return .gray
        }
    }

    var icon: String {
        switch self {
        case .connected:  return "checkmark.circle.fill"
        case .needsAuth:  return "lock.fill"
        case .error:      return "xmark.circle.fill"
        case .unknown:    return "questionmark.circle.fill"
        }
    }
}

// MARK: - Command Snippets

struct CommandSnippet: Identifiable, Codable {
    var id    = UUID()
    var title: String
    var text:  String
}

// MARK: - CLI Errors

enum CLIError: LocalizedError {
    case processError(exitCode: Int, stderr: String)

    var errorDescription: String? {
        switch self {
        case .processError(let code, let stderr):
            return "claude exited \(code): \(stderr)"
        }
    }
}

// MARK: - Active Sessions

struct ActiveCLISession: Identifiable {
    let id: String
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Date
    let kind: String

    var cwdDisplay: String { URL(fileURLWithPath: cwd).lastPathComponent }
}

struct ActiveSessionFile: Decodable {
    let pid: Int?
    let sessionId: String?
    let cwd: String?
    let startedAt: Double?
    let kind: String?
}
