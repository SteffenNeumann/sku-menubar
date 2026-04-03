import Foundation

@MainActor
final class AgentService: ObservableObject {

    @Published var agents: [AgentDefinition] = []
    @Published var logs: [String: [ScheduledTaskLogEntry]] = [:]
    @Published var runningAgents: Set<String> = []
    @Published var liveOutput: [String: String] = [:]

    private let home = NSHomeDirectory()
    private weak var cliService: ClaudeCLIService?
    private var schedulerTimer: Timer?

    init(cliService: ClaudeCLIService? = nil) {
        self.cliService = cliService
    }

    var agentsDir: URL {
        URL(fileURLWithPath: "\(home)/.claude/agents")
    }

    var logsDir: URL {
        URL(fileURLWithPath: "\(home)/.claude/agent-logs")
    }

    // MARK: - Load agents from ~/.claude/agents/*.md

    func loadAgents() async {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        var result: [AgentDefinition] = []
        for file in files where file.pathExtension == "md" {
            if let agent = parseAgentFile(file) {
                result.append(agent)
            }
        }
        agents = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loadAllLogs()
    }

    // MARK: - Parse YAML frontmatter from .md file

    private func parseAgentFile(_ url: URL) -> AgentDefinition? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        var frontmatterLines: [String] = []
        var bodyStart = 1
        var inFrontmatter = true

        for (i, line) in lines.dropFirst().enumerated() {
            if inFrontmatter && line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = i + 2
                inFrontmatter = false
                break
            }
            frontmatterLines.append(line)
        }

        guard !inFrontmatter else { return nil }

        var fields: [String: String] = [:]
        for line in frontmatterLines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key   = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'")  && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }

        let name        = fields["name"] ?? url.deletingPathExtension().lastPathComponent
        let description = fields["description"] ?? ""
        let model       = fields["model"] ?? "sonnet"
        let color       = fields["color"]
        let memory      = fields["memory"]
        let portrait    = fields["portrait"].flatMap { $0.isEmpty ? nil : $0 }
        let triggers    = fields["triggers"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
        let schedule    = fields["schedule"].flatMap { $0.isEmpty ? nil : $0 }
        let isActive    = (fields["active"] ?? "false").lowercased() == "true"

        let body = lines[bodyStart...].joined(separator: "\n")

        // Extract research update date from "🔬 Research Updates" section
        var researchUpdatedAt: String? = nil
        for line in lines[bodyStart...] {
            // Matches: _Last updated: 2026-04-02 by Researcher_
            if line.contains("Last updated:"),
               let start = line.range(of: "Last updated:")?.upperBound {
                let raw = String(line[start...])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ").first ?? ""
                let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "_*"))
                if cleaned.count == 10, cleaned.contains("-") {
                    researchUpdatedAt = cleaned
                    break
                }
            }
        }

        return AgentDefinition(
            id: url.deletingPathExtension().lastPathComponent,
            name: name,
            description: description,
            model: model,
            color: color,
            memory: memory,
            portrait: portrait,
            triggers: triggers,
            promptBody: body,
            filePath: url.path,
            schedule: schedule,
            isActive: isActive,
            researchUpdatedAt: researchUpdatedAt
        )
    }

    // MARK: - Preview file content

    func previewAgentFile(_ draft: AgentDraft) -> String {
        var lines = ["---"]
        lines.append("name: \"\(draft.name)\"")
        if !draft.description.isEmpty  { lines.append("description: \"\(draft.description)\"") }
        lines.append("model: \(draft.model.isEmpty ? "sonnet" : draft.model)")
        if !draft.color.isEmpty    { lines.append("color: \(draft.color)") }
        if !draft.memory.isEmpty   { lines.append("memory: \(draft.memory)") }
        if !draft.portrait.isEmpty  { lines.append("portrait: \(draft.portrait)") }
        if !draft.triggers.isEmpty  { lines.append("triggers: \(draft.triggers)") }
        if !draft.schedule.isEmpty  { lines.append("schedule: \(draft.schedule)") }
        if draft.isActive          { lines.append("active: true") }
        lines.append("---")
        if !draft.promptBody.isEmpty {
            lines.append("")
            lines.append(draft.promptBody)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Save / Create

    func saveAgent(_ draft: AgentDraft, previousId: String?) async throws -> AgentDefinition {
        let fm = FileManager.default
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let agentId = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentId.isEmpty else { throw AgentError.invalidId }

        // Auto-fill triggers if empty
        var draft = draft
        if draft.triggers.trimmingCharacters(in: .whitespaces).isEmpty {
            let source = [draft.name, draft.description, draft.promptBody].joined(separator: " ")
            draft.triggers = AgentDefinition.extractKeywords(from: source, limit: 6).joined(separator: ", ")
        }

        let newURL = agentsDir.appendingPathComponent("\(agentId).md")

        // Delete old file if renaming
        if let prevId = previousId, prevId != agentId {
            let oldURL = agentsDir.appendingPathComponent("\(prevId).md")
            try? fm.removeItem(at: oldURL)
        }

        let content = previewAgentFile(draft)
        try content.write(to: newURL, atomically: true, encoding: .utf8)

        await loadAgents()
        guard let saved = agents.first(where: { $0.id == agentId }) else {
            throw AgentError.saveError("Agent konnte nach dem Speichern nicht geladen werden.")
        }
        return saved
    }

    // MARK: - Delete

    func deleteAgent(agentId: String) async throws {
        let url = agentsDir.appendingPathComponent("\(agentId).md")
        try FileManager.default.removeItem(at: url)
        await loadAgents()
    }

    // MARK: - Duplicate

    func duplicateAgent(_ agent: AgentDefinition) async throws -> AgentDefinition {
        var draft = AgentDraft(agent: agent)
        draft.id   = "\(agent.id)-copy"
        draft.name = "\(agent.name) (Kopie)"
        draft.isActive = false
        return try await saveAgent(draft, previousId: nil)
    }

    // MARK: - Import / Export

    func importAgent(from url: URL) async throws -> AgentDefinition {
        let fm = FileManager.default
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let dest = agentsDir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: url, to: dest)
        await loadAgents()
        let newId = url.deletingPathExtension().lastPathComponent
        guard let agent = agents.first(where: { $0.id == newId }) else {
            throw AgentError.saveError("Importierter Agent konnte nicht geladen werden.")
        }
        return agent
    }

    func exportAgent(_ agent: AgentDefinition, to url: URL) throws {
        let src = URL(fileURLWithPath: agent.filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: src, to: url)
    }

    // MARK: - Agent memory & learning log

    func loadAgentMemory(agentId: String) -> String? {
        let memPath = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agentId)/MEMORY.md")
        return try? String(contentsOf: memPath, encoding: .utf8)
    }

    /// Directories for an agent's memory files (name-based first, id-based second).
    private func memoryDirs(for agent: AgentDefinition) -> (primary: URL, secondary: URL) {
        let base = URL(fileURLWithPath: "\(home)/.claude/agent-memory")
        return (base.appendingPathComponent(agent.name),
                base.appendingPathComponent(agent.id))
    }

    /// Returns the writable memory directory (creates the name-based dir if needed).
    private func writableMemoryDir(for agent: AgentDefinition) -> URL {
        let dir = memoryDirs(for: agent).primary
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Reads a named file from the first existing memory directory.
    private func readMemoryFile(named filename: String, for agent: AgentDefinition) -> String? {
        let (primary, secondary) = memoryDirs(for: agent)
        for dir in [primary, secondary] {
            let url = dir.appendingPathComponent(filename)
            if let content = try? String(contentsOf: url, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }
        return nil
    }

    /// Builds a context preamble from MEMORY.md + learning_log.txt to inject before the system prompt.
    private func buildContextPreamble(for agent: AgentDefinition) -> String {
        var parts: [String] = []

        // Persistent MEMORY.md (researcher writes this; other agents may have one too)
        if let mem = readMemoryFile(named: "MEMORY.md", for: agent) {
            parts.append("## Your Persistent Memory\n\(mem.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Learning log — last 20 entries
        if let logContent = readMemoryFile(named: "learning_log.txt", for: agent) {
            let lines = logContent
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let recent = Array(lines.suffix(20))
            if !recent.isEmpty {
                parts.append("## Your Learning Log (last \(recent.count) entries)\n" + recent.joined(separator: "\n"))
            }
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    /// Appends one timestamped entry to the agent's learning_log.txt.
    private func appendLearningEntry(for agent: AgentDefinition, status: ScheduledTaskStatus, learned: String) {
        let dir = writableMemoryDir(for: agent)
        let logURL = dir.appendingPathComponent("learning_log.txt")

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = fmt.string(from: Date())
        let statusLabel = status == .success ? "OK" : "FEHLER"

        // Sanitize: collapse newlines, trim, limit to 300 chars
        let cleaned = learned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let summary = String(cleaned.prefix(300))
        let line = "\(timestamp) | \(statusLabel) | \(summary)\n"

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }

    /// Extracts the `LEARNED:` line from agent output, or falls back to a short snippet.
    private func extractLearnedLine(from output: String) -> String {
        for line in output.components(separatedBy: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("learned:") {
                let value = t.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return String(value) }
            }
        }
        // Fallback: last meaningful line, capped at 200 chars
        for line in output.components(separatedBy: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count > 10 { return String(t.prefix(200)) }
        }
        let preview = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "No output" : String(preview.prefix(200))
    }

    // MARK: - Logbook

    func loadAllLogs() {
        for agent in agents {
            logs[agent.id] = loadLog(agentId: agent.id)
        }
    }

    func loadLog(agentId: String) -> [ScheduledTaskLogEntry] {
        let url = logsDir.appendingPathComponent("\(agentId).json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries = (try? decoder.decode([ScheduledTaskLogEntry].self, from: data)) ?? []
        // Heal stale "running" entries left by a previous app crash/quit
        var changed = false
        for i in entries.indices where entries[i].status == .running {
            entries[i].status = .failed
            entries[i].error  = "Abgebrochen (App wurde beendet)"
            entries[i].finishedAt = entries[i].startedAt
            changed = true
        }
        if changed { saveLog(entries, agentId: agentId) }
        return entries
    }

    private func saveLog(_ entries: [ScheduledTaskLogEntry], agentId: String) {
        let url = logsDir.appendingPathComponent("\(agentId).json")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }

    func clearLog(agentId: String) {
        logs[agentId] = []
        saveLog([], agentId: agentId)
    }

    private func appendEntry(_ entry: ScheduledTaskLogEntry) {
        var current = logs[entry.agentId] ?? []
        current.append(entry)
        if current.count > 100 { current = Array(current.suffix(100)) }
        logs[entry.agentId] = current
        saveLog(current, agentId: entry.agentId)
    }

    private func updateEntry(_ entry: ScheduledTaskLogEntry) {
        guard var current = logs[entry.agentId] else { return }
        if let idx = current.firstIndex(where: { $0.id == entry.id }) {
            current[idx] = entry
        } else {
            current.append(entry)
        }
        logs[entry.agentId] = current
        saveLog(current, agentId: entry.agentId)
    }

    // MARK: - Scheduler

    func startScheduler() {
        guard schedulerTimer == nil else { return }
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkSchedules()
            }
        }
    }

    func stopScheduler() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil
    }

    func checkSchedules() async {
        let now = Date()
        for agent in agents where agent.isActive {
            guard let schedule = agent.schedule, !schedule.isEmpty else { continue }
            guard !runningAgents.contains(agent.id) else { continue }
            let lastRun = logs[agent.id]?.last?.startedAt
            if isDue(schedule: schedule, lastRun: lastRun, now: now) {
                await executeScheduledAgent(agent)
            }
        }
    }

    private func isDue(schedule: String, lastRun: Date?, now: Date) -> Bool {
        let interval = scheduleInterval(schedule)
        guard interval > 0 else { return false }
        guard let last = lastRun else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    private func scheduleInterval(_ schedule: String) -> TimeInterval {
        let s = schedule.lowercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "hourly":  return 3600
        case "daily":   return 86400
        case "weekly":  return 604800
        default:
            if s.hasPrefix("every:"), let mins = Double(s.dropFirst(6)) { return mins * 60 }
            return 0
        }
    }

    // MARK: - Execute scheduled agent

    func executeScheduledAgent(_ agent: AgentDefinition) async {
        guard let cli = cliService else {
            var entry = ScheduledTaskLogEntry(
                agentId: agent.id, startedAt: Date(), status: .failed, error: "CLI-Service nicht verfügbar."
            )
            entry.finishedAt = Date()
            appendEntry(entry)
            return
        }

        var entry = ScheduledTaskLogEntry(agentId: agent.id, startedAt: Date(), status: .running)
        appendEntry(entry)
        runningAgents.insert(agent.id)
        liveOutput[agent.id] = ""

        let timeoutSeconds: TimeInterval = 300  // 5 min max per agent run
        var outputText = ""
        var resultText = ""
        do {
            // Build enriched system prompt: preamble (memory + learning log) + body + LEARNED instruction
            let preamble = buildContextPreamble(for: agent)
            let body     = agent.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let learnedInstruction = """


---
At the very end of your response, write exactly one line in this format (do not omit this):
LEARNED: <what went well or was important> | <what failed or should be avoided next time>
"""
            var instructions: String
            if preamble.isEmpty {
                instructions = body.isEmpty ? "" : body + learnedInstruction
            } else {
                instructions = preamble + "\n\n---\n\n" + (body.isEmpty ? "Execute your role." : body) + learnedInstruction
            }

            let stream = cli.send(
                message: "Begin your session now. Execute your defined role as described in your system prompt — do not wait for further instructions.",
                systemPrompt: instructions.isEmpty ? nil : instructions,
                model: agent.model.isEmpty ? nil : agent.model,
                skipPermissions: true
            )
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            for try await event in stream {
                if Date() > deadline {
                    entry.status = .failed
                    entry.error  = "Timeout nach \(Int(timeoutSeconds / 60)) Minuten."
                    entry.finishedAt = Date()
                    break
                }
                switch event.type {
                case "assistant":
                    if let contents = event.message?.content {
                        for c in contents where c.type == "text" {
                            let chunk = c.text ?? ""
                            outputText += chunk
                            liveOutput[agent.id] = outputText
                        }
                    }
                case "result":
                    if let r = event.result, !r.isEmpty { resultText = r }
                default:
                    break
                }
            }
            if entry.status == .running {
                entry.status = .success
                // Check for a dedicated daily report file (agents can write to name/ or id/ directory)
                let reportByName = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.name)/daily_report.txt")
                let reportById   = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.id)/daily_report.txt")
                let fm = FileManager.default
                let reportURL = fm.fileExists(atPath: reportByName.path) ? reportByName : reportById
                if let reportText = try? String(contentsOf: reportURL, encoding: .utf8),
                   !reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let attrs = try? fm.attributesOfItem(atPath: reportURL.path),
                   let modified = attrs[.modificationDate] as? Date,
                   modified >= entry.startedAt {
                    entry.output = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    entry.output = outputText.isEmpty ? resultText : outputText
                }
                entry.finishedAt = Date()
            }
        } catch {
            entry.status = .failed
            entry.error  = error.localizedDescription
            // Preserve whatever output was collected before the failure
            if !outputText.isEmpty {
                let tail = outputText.count > 800 ? "…\n" + String(outputText.suffix(800)) : outputText
                entry.output = tail
            }
            entry.finishedAt = Date()
        }

        // Write learning log entry regardless of success/failure
        let learned = extractLearnedLine(from: outputText)
        appendLearningEntry(for: agent, status: entry.status, learned: learned)

        liveOutput.removeValue(forKey: agent.id)
        runningAgents.remove(agent.id)
        updateEntry(entry)
    }
}

// MARK: - Errors

enum AgentError: LocalizedError {
    case invalidId
    case saveError(String)

    var errorDescription: String? {
        switch self {
        case .invalidId:          return "Kennung darf nicht leer sein."
        case .saveError(let msg): return msg
        }
    }
}

