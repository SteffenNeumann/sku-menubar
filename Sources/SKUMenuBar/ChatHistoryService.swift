import Foundation

@MainActor
final class ChatHistoryService: ObservableObject {

    @Published var projects: [ProjectHistory] = []
    @Published var isLoading: Bool = false

    private let home = NSHomeDirectory()

    var projectsDir: URL {
        URL(fileURLWithPath: "\(home)/.claude/projects")
    }

    var historyFile: URL {
        URL(fileURLWithPath: "\(home)/.claude/history.jsonl")
    }

    // MARK: - Load projects from history.jsonl (fast path)

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        // Read global history file for fast session index
        guard let data = try? Data(contentsOf: historyFile) else { return }
        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []

        let decoder = JSONDecoder()
        var byProject: [String: [(session: String, preview: String, ts: Date)]] = [:]

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(GlobalHistoryEntry.self, from: lineData),
                  let project = entry.project,
                  let sessionId = entry.sessionId else { continue }

            let ts = entry.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            let preview = entry.display ?? ""
            byProject[project, default: []].append((sessionId, preview, ts))
        }

        var result: [ProjectHistory] = []
        for (path, entries) in byProject {
            let sessions = entries
                .sorted { $0.ts > $1.ts }
                .map { e in
                    // Use firstUserMessage as preview if history.jsonl shows a slash-command or empty
                    let rawPreview = e.preview
                    let preview: String
                    if rawPreview.isEmpty || rawPreview.hasPrefix("/") || rawPreview.hasPrefix("[Image") {
                        preview = firstUserMessage(sessionId: e.session, projectPath: path) ?? rawPreview
                    } else {
                        preview = rawPreview
                    }
                    return HistorySession(
                        id: "\(path)/\(e.session)",
                        sessionId: e.session,
                        projectPath: path,
                        preview: preview,
                        timestamp: e.ts,
                        messageCount: 0
                    )
                }
            // De-duplicate sessions by sessionId (keep most recent)
            var seen = Set<String>()
            let unique = sessions.filter { seen.insert($0.sessionId).inserted }
            result.append(ProjectHistory(id: path, path: path, sessions: unique))
        }
        projects = result.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Load messages for a session

    func loadMessages(for session: HistorySession) async -> [HistoryMessage] {
        let encoded = encodePath(session.projectPath)
        let file = projectsDir
            .appendingPathComponent(encoded)
            .appendingPathComponent("\(session.sessionId).jsonl")

        guard let data = try? Data(contentsOf: file) else { return [] }
        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []

        let decoder = JSONDecoder()
        var messages: [HistoryMessage] = []

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let raw = try? decoder.decode(RawCLIMessage.self, from: lineData),
                  let type = raw.type,
                  (type == "user" || type == "assistant"),
                  let uuid = raw.uuid else { continue }

            let ts: Date
            if let tsStr = raw.timestamp {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                ts = iso.date(from: tsStr) ?? ISO8601DateFormatter().date(from: tsStr) ?? .now
            } else {
                ts = .now
            }

            let role: MessageRole = type == "user" ? .user : .assistant
            let content = raw.message?.content?.displayText ?? ""
            let model = raw.message?.model

            let usage = raw.message?.usage
            let inputT = usage?.inputTokens ?? 0
            let outputT = usage?.outputTokens ?? 0
            let cacheT = (usage?.cacheCreationInputTokens ?? 0) + (usage?.cacheReadInputTokens ?? 0)

            // Extract tool calls from assistant messages
            var toolCalls: [ToolCall] = []
            if role == .assistant,
               case .blocks(let blocks) = raw.message?.content {
                for block in blocks where block.type == "tool_use" {
                    toolCalls.append(ToolCall(
                        name: block.name ?? "unknown",
                        input: "…"
                    ))
                }
            }

            // Skip messages with no visible content (e.g. pure system-tag injections like /clear)
            guard !content.isEmpty || !toolCalls.isEmpty else { continue }

            // Merge consecutive pure-tool-call assistant messages into the next one
            // so all tool calls for one turn appear in a single bubble
            if role == .assistant, content.isEmpty, !toolCalls.isEmpty,
               let lastIdx = messages.indices.last,
               messages[lastIdx].role == .assistant {
                messages[lastIdx].toolCalls.append(contentsOf: toolCalls)
                messages[lastIdx].inputTokens += inputT
                messages[lastIdx].outputTokens += outputT
                messages[lastIdx].cacheTokens += cacheT
                continue
            }

            messages.append(HistoryMessage(
                id: uuid,
                parentId: raw.parentUuid,
                role: role,
                content: content,
                toolCalls: toolCalls,
                timestamp: ts,
                model: model,
                inputTokens: inputT,
                outputTokens: outputT,
                cacheTokens: cacheT
            ))
        }
        return messages
    }

    // MARK: - Helpers

    private func encodePath(_ path: String) -> String {
        // /Users/steffen/foo -> -Users-steffen-foo
        path.replacingOccurrences(of: "/", with: "-")
    }

    /// Reads the session JSONL to find the first meaningful user text message.
    /// Stops after finding it to keep this fast.
    private func firstUserMessage(sessionId: String, projectPath: String) -> String? {
        let file = projectsDir
            .appendingPathComponent(encodePath(projectPath))
            .appendingPathComponent("\(sessionId).jsonl")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        // Read in chunks until we find the first user message
        var buffer = Data()
        let decoder = JSONDecoder()
        while true {
            let chunk = handle.readData(ofLength: 4096)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            // Process complete lines
            while let nlRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<nlRange.lowerBound]
                buffer.removeSubrange(buffer.startIndex...nlRange.lowerBound)
                guard !lineData.isEmpty,
                      let raw = try? decoder.decode(RawCLIMessage.self, from: lineData),
                      raw.type == "user" else { continue }
                let text = raw.message?.content?.displayText ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip pure slash-commands
                guard !trimmed.isEmpty && !trimmed.hasPrefix("/") else { continue }
                // Strip "[Image: source: /path...]" references, keep any user-written text
                let stripped = trimmed
                    .replacingOccurrences(of: #"\[Image: source:[^\]]*\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = stripped.isEmpty ? trimmed : stripped
                return String(preview.prefix(80))
            }
        }
        return nil
    }
}
