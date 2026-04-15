import Foundation
import SwiftUI

// MARK: - App Navigation

enum AppSection: String, CaseIterable, Hashable {
    case home        = "Home"
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
        case .home:       return "house.fill"
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
        case .home:       return .blue
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
                        "gitignore", "dockerfile", "makefile", "log",
                        "bas", "cls", "frm", "vba", "vbs"]
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
    var pinned: Bool = false
    var createdAt: Date = Date()
    var tags: [String] = []
    var taskLines: [TaskLine] = []

    init(type: NoteType = .note, title: String = "", body: String = "") {
        self.type = type
        self.title = title
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,        forKey: .id)
        type      = try c.decode(NoteType.self,    forKey: .type)
        title     = try c.decode(String.self,      forKey: .title)
        body      = try c.decode(String.self,      forKey: .body)
        done      = try c.decode(Bool.self,        forKey: .done)
        pinned    = try c.decodeIfPresent(Bool.self,      forKey: .pinned)    ?? false
        createdAt = try c.decode(Date.self,        forKey: .createdAt)
        tags      = try c.decodeIfPresent([String].self,  forKey: .tags)      ?? []
        taskLines = try c.decodeIfPresent([TaskLine].self, forKey: .taskLines) ?? []
    }
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
    let toolUseId: String?   // matches StreamContent.id for pairing with tool_result
    let name: String
    let input: String        // human-readable command / path summary
    var result: String?      // stdout / output from the tool execution

    init(name: String, input: String, toolUseId: String? = nil) {
        self.name = name
        self.input = input
        self.toolUseId = toolUseId
    }

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

// Input payload of a tool_use block (fields vary per tool)
struct StreamToolInput: Decodable {
    let command: String?      // Bash
    let filePath: String?     // Read / Write / Edit
    let pattern: String?      // Glob / Grep
    let path: String?         // LS
    let description: String?  // misc

    enum CodingKeys: String, CodingKey {
        case command
        case filePath    = "file_path"
        case pattern
        case path
        case description
    }

    /// Human-readable single-line summary for UI display
    var displayText: String? {
        command ?? filePath ?? pattern ?? path ?? description
    }

    /// Convenience init for programmatic creation (e.g. GitHub tool_calls)
    init(description: String) {
        self.command     = nil
        self.filePath    = nil
        self.pattern     = nil
        self.path        = nil
        self.description = description
    }
}

struct StreamContent: Decodable {
    let type: String    // "text", "tool_use", "tool_result", "thinking"
    let text: String?
    let thinking: String?
    let id: String?          // tool_use id
    let name: String?
    let toolInput: StreamToolInput?   // decoded from tool_use.input
    let toolUseId: String?            // tool_result: references tool_use.id
    let toolResultText: String?       // tool_result: stdout/stderr text

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, input, content
        case toolUseId = "tool_use_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type           = (try? c.decode(String.self, forKey: .type)) ?? ""
        text           = try? c.decodeIfPresent(String.self, forKey: .text)
        thinking       = try? c.decodeIfPresent(String.self, forKey: .thinking)
        id             = try? c.decodeIfPresent(String.self, forKey: .id)
        name           = try? c.decodeIfPresent(String.self, forKey: .name)
        toolInput      = try? c.decodeIfPresent(StreamToolInput.self, forKey: .input)
        toolUseId      = try? c.decodeIfPresent(String.self, forKey: .toolUseId)
        toolResultText = try? c.decodeIfPresent(String.self, forKey: .content)
    }

    /// Convenience init for programmatic creation (e.g. in GitHubModelsService)
    init(type: String, text: String? = nil, thinking: String? = nil,
         id: String? = nil, name: String? = nil,
         toolInput: StreamToolInput? = nil, toolUseId: String? = nil, toolResultText: String? = nil) {
        self.type           = type
        self.text           = text
        self.thinking       = thinking
        self.id             = id
        self.name           = name
        self.toolInput      = toolInput
        self.toolUseId      = toolUseId
        self.toolResultText = toolResultText
    }
}

struct StreamUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    /// Gesamte Input-Token-Nutzung inkl. Cache (= echter Kontext-Verbrauch)
    var totalInputTokens: Int {
        (inputTokens ?? 0) + (cacheReadInputTokens ?? 0) + (cacheCreationInputTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens             = "input_tokens"
        case outputTokens            = "output_tokens"
        case cacheReadInputTokens    = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
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
    var toolCalls: [ToolCall]
    let timestamp: Date
    let model: String?
    var inputTokens: Int
    var outputTokens: Int
    var cacheTokens: Int
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
        case .text(let s): return s.strippingClaudeSystemTags()
        case .blocks(let blocks):
            return blocks.compactMap { block in
                switch block.type {
                case "text": return block.text?.strippingClaudeSystemTags()
                case "tool_use": return nil // shown via toolCalls badges, not as text
                case "tool_result":
                    // Tool results are internal harness content — never shown in chat history
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
    // Category
    let category: String?       // nil = worker, "persona" = customer persona
    // Customer Persona fields (only used when category == "persona")
    let customerName: String?
    let industry: String?
    let techLevel: String?      // "low" | "medium" | "high"
    let priorities: [String]
    let dealbreakers: [String]
    let tone: String?           // "formal" | "informal"

    var isPersona: Bool { category == "persona" }

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
    // Category
    var category: String = ""   // "" = worker, "persona" = customer persona
    // Persona fields
    var customerName: String = ""
    var industry: String = ""
    var techLevel: String = "medium"
    var priorities: String = ""    // comma-separated
    var dealbreakers: String = ""  // comma-separated
    var tone: String = "formal"

    var isPersona: Bool { category == "persona" }

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
        category     = agent.category ?? ""
        customerName = agent.customerName ?? ""
        industry     = agent.industry ?? ""
        techLevel    = agent.techLevel ?? "medium"
        priorities   = agent.priorities.joined(separator: ", ")
        dealbreakers = agent.dealbreakers.joined(separator: ", ")
        tone         = agent.tone ?? "formal"
    }
}

// MARK: - Persona Validation

enum ValidationVerdict: String, Codable {
    case approved       = "approved"
    case revisionNeeded = "revision"
    case rejected       = "rejected"

    var label: String {
        switch self {
        case .approved:       return "Freigabe"
        case .revisionNeeded: return "Überarbeitung nötig"
        case .rejected:       return "Abgelehnt"
        }
    }

    var icon: String {
        switch self {
        case .approved:       return "checkmark.circle.fill"
        case .revisionNeeded: return "exclamationmark.triangle.fill"
        case .rejected:       return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .approved:       return .green
        case .revisionNeeded: return .orange
        case .rejected:       return .red
        }
    }
}

struct PersonaValidationResult: Identifiable {
    let id = UUID()
    let personaId: String
    let personaName: String
    let score: Int              // 1–10
    let verdict: ValidationVerdict
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let recommendation: String
    let createdAt: Date

    var scoreColor: Color {
        switch score {
        case 8...10: return .green
        case 5...7:  return .orange
        default:     return .red
        }
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

enum MCPScope: String, Codable, CaseIterable, Hashable {
    case user    = "user"    // global ~/.claude/claude.json
    case project = "project" // per-project .claude/settings.json
    case local   = "local"   // per-project .claude/settings.local.json

    var label: String {
        switch self {
        case .user:    return "Global"
        case .project: return "Projekt"
        case .local:   return "Lokal"
        }
    }

    var icon: String {
        switch self {
        case .user:    return "globe"
        case .project: return "folder.badge.gearshape"
        case .local:   return "laptopcomputer"
        }
    }

    var cliFlag: String { rawValue }
}

struct MCPServerConfig: Codable {
    var name: String
    var transport: String
    var commandOrUrl: String
    var args: [String]
    var headers: [String]
    var envVars: [String]
    var scope: MCPScope
}

struct MCPProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var servers: [MCPServerConfig]
    var createdAt: Date = Date()
}

struct MCPServer: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let status: MCPStatus
    let detail: String
    var scope: MCPScope = .user
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

// MARK: - String helper: strip Claude internal system tags

private extension String {
    /// Removes Claude Code internal XML tags from message content so they don't
    /// appear in the chat history view. These tags are injected by the harness
    /// and are not meant to be visible to users.
    func strippingClaudeSystemTags() -> String {
        let tagNames = [
            "local-command-caveat",
            "command-name",
            "command-message",
            "command-args",
            "system-reminder",
            "user-prompt-submit-hook",
        ]
        var result = self
        for tag in tagNames {
            // Remove <tag ...>...</tag> blocks (including multiline content)
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: []
            ) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ActiveSessionFile: Decodable {
    let pid: Int?
    let sessionId: String?
    let cwd: String?
    let startedAt: Double?
    let kind: String?
}

// MARK: - Home Tile Configuration

enum HomeTileID: String, CaseIterable, Codable {
    case quickActions    = "quickActions"
    case costToday       = "costToday"
    case recentProjects  = "recentProjects"
    case activeSessions  = "activeSessions"
    case agents          = "agents"
    case tokenUsage      = "tokenUsage"

    var displayName: String {
        switch self {
        case .quickActions:   return "Schnellzugriff"
        case .costToday:      return "Kosten Heute"
        case .recentProjects: return "Letzte Projekte"
        case .activeSessions: return "Aktive Sessions"
        case .agents:         return "Agents"
        case .tokenUsage:     return "Token-Verbrauch"
        }
    }

    var icon: String {
        switch self {
        case .quickActions:   return "bolt.fill"
        case .costToday:      return "eurosign.circle.fill"
        case .recentProjects: return "clock.arrow.circlepath"
        case .activeSessions: return "terminal.fill"
        case .agents:         return "cpu.fill"
        case .tokenUsage:     return "chart.bar.fill"
        }
    }
}
