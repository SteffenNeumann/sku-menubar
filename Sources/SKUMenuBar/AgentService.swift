import Foundation
import AppKit

@MainActor
final class AgentService: ObservableObject {

    @Published var agents: [AgentDefinition] = []
    @Published var logs: [String: [ScheduledTaskLogEntry]] = [:]
    @Published var runningAgents: Set<String> = []
    @Published var liveOutput: [String: String] = [:]
    // Persona email learning
    @Published var emailLearningRunning: Set<String> = []
    @Published var emailLearningStatus: [String: String] = [:]
    // Dream mode
    @Published var dreamingAgents: Set<String> = []

    private let home = NSHomeDirectory()
    private weak var cliService: ClaudeCLIService?
    private weak var appState: AppState?
    private let ghModelsService = GitHubModelsService()
    private var schedulerTimer: Timer?
    private var agentsDirWatcher: DispatchSourceFileSystemObject?
    private var reloadDebounceTask: Task<Void, Never>?

    init(cliService: ClaudeCLIService? = nil, appState: AppState? = nil) {
        self.cliService = cliService
        self.appState   = appState
    }

    func startAgentsDirWatcher() {
        let path = agentsDir.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .attrib, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            reloadDebounceTask?.cancel()
            reloadDebounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.loadAgents()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        agentsDirWatcher = source
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
        Task { loadAllLogs() }
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
        let schedule        = fields["schedule"].flatMap      { $0.isEmpty ? nil : $0 }
        let dreamSchedule   = fields["dream_schedule"].flatMap { $0.isEmpty ? nil : $0 }
        let isActive        = (fields["active"] ?? "false").lowercased() == "true"
        let timeoutMins     = fields["timeout"].flatMap { Int($0) } ?? 30
        let projectDir      = fields["project"].flatMap { $0.isEmpty ? nil : $0 }
        // Persona fields
        let category        = fields["category"].flatMap { $0.isEmpty ? nil : $0 }
        let customerName    = fields["customer_name"].flatMap { $0.isEmpty ? nil : $0 }
        let industry        = fields["industry"].flatMap { $0.isEmpty ? nil : $0 }
        let techLevel       = fields["tech_level"].flatMap { $0.isEmpty ? nil : $0 }
        let priorities      = fields["priorities"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
        let dealbreakers    = fields["dealbreakers"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
        let tone            = fields["tone"].flatMap { $0.isEmpty ? nil : $0 }
        let emailDomain          = fields["email_domain"].flatMap  { $0.isEmpty ? nil : $0 }
        let emailAddress         = fields["email_address"].flatMap { $0.isEmpty ? nil : $0 }
        let emailRoutingEnabled  = fields["email_routing_enabled"].map { $0.lowercased() != "false" } ?? true
        let associatedProjects = fields["associated_projects"].map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } ?? []
        let requiredMCPs = fields["required_mcps"].map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } ?? []

        let agentId = url.deletingPathExtension().lastPathComponent
        let contextImages = loadContextImages(for: agentId)

        let body = lines[bodyStart...].joined(separator: "\n")

        // Section-aware extraction of research and skills update dates
        var researchUpdatedAt: String? = nil
        var skillsUpdatedAt: String?   = nil
        var currentSection: String?    = nil
        let dateFmtValidator: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX"); return f
        }()
        for line in lines[bodyStart...] {
            if line.contains("🔬")      { currentSection = "research" }
            else if line.contains("🛠") { currentSection = "skills" }
            else if line.hasPrefix("## ") { currentSection = nil }

            if let section = currentSection, line.contains("Last updated:"),
               let start = line.range(of: "Last updated:")?.upperBound {
                let raw = String(line[start...])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ").first ?? ""
                let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "_*"))
                // Only accept real ISO dates — rejects template placeholders like "YYYY-MM-DD"
                if cleaned.count == 10, cleaned.contains("-"),
                   dateFmtValidator.date(from: cleaned) != nil {
                    switch section {
                    case "research": researchUpdatedAt = cleaned
                    case "skills":   skillsUpdatedAt   = cleaned
                    default: break
                    }
                }
            }
        }

        return AgentDefinition(
            id: agentId,
            name: name,
            description: description,
            model: model,
            color: color,
            memory: memory,
            portrait: portrait,
            triggers: triggers,
            promptBody: body,
            filePath: url.path,
            projectDirectory: projectDir,
            schedule: schedule,
            isActive: isActive,
            timeoutMinutes: timeoutMins,
            researchUpdatedAt: researchUpdatedAt,
            skillsUpdatedAt:   skillsUpdatedAt,
            dreamSchedule:     dreamSchedule,
            category: category,
            customerName: customerName,
            industry: industry,
            techLevel: techLevel,
            priorities: priorities,
            dealbreakers: dealbreakers,
            tone: tone,
            associatedProjects: associatedProjects,
            contextImages: contextImages,
            emailDomain: emailDomain,
            emailAddress: emailAddress,
            emailRoutingEnabled: emailRoutingEnabled,
            requiredMCPs: requiredMCPs
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
        if !draft.projectDirectory.isEmpty { lines.append("project: \(draft.projectDirectory)") }
        if !draft.portrait.isEmpty  { lines.append("portrait: \(draft.portrait)") }
        if !draft.triggers.isEmpty  { lines.append("triggers: \(draft.triggers)") }
        if !draft.schedule.isEmpty      { lines.append("schedule: \(draft.schedule)") }
        if !draft.dreamSchedule.isEmpty { lines.append("dream_schedule: \(draft.dreamSchedule)") }
        if !draft.timeoutMinutes.isEmpty { lines.append("timeout: \(draft.timeoutMinutes)") }
        if draft.isActive          { lines.append("active: true") }
        if !draft.category.isEmpty        { lines.append("category: \(draft.category)") }
        if !draft.customerName.isEmpty    { lines.append("customer_name: \"\(draft.customerName)\"") }
        if !draft.industry.isEmpty        { lines.append("industry: \"\(draft.industry)\"") }
        if draft.techLevel != "medium"    { lines.append("tech_level: \(draft.techLevel)") }
        if !draft.priorities.isEmpty      { lines.append("priorities: \(draft.priorities)") }
        if !draft.dealbreakers.isEmpty    { lines.append("dealbreakers: \(draft.dealbreakers)") }
        if draft.tone != "formal"         { lines.append("tone: \(draft.tone)") }
        if !draft.associatedProjects.isEmpty {
            lines.append("associated_projects: \(draft.associatedProjects.joined(separator: ", "))")
        }
        if !draft.requiredMCPs.isEmpty {
            lines.append("required_mcps: \(draft.requiredMCPs.joined(separator: ", "))")
        }
        if !draft.emailAddress.isEmpty { lines.append("email_address: \(draft.emailAddress)") }
        if !draft.emailDomain.isEmpty  { lines.append("email_domain: \(draft.emailDomain)") }
        if !draft.emailRoutingEnabled  { lines.append("email_routing_enabled: false") }
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

        // Migrate context images sidecar if renaming
        if let prevId = previousId, prevId != agentId {
            let oldSidecar = agentsDir.appendingPathComponent("\(prevId)-images.json")
            let newSidecar = agentsDir.appendingPathComponent("\(agentId)-images.json")
            try? fm.moveItem(at: oldSidecar, to: newSidecar)
            let oldImgDir = agentsDir.appendingPathComponent("images/\(prevId)")
            let newImgDir = agentsDir.appendingPathComponent("images/\(agentId)")
            try? fm.moveItem(at: oldImgDir, to: newImgDir)
        }

        try saveContextImages(draft.contextImages, for: agentId)

        await loadAgents()
        guard let saved = agents.first(where: { $0.id == agentId }) else {
            throw AgentError.saveError("Agent konnte nach dem Speichern nicht geladen werden.")
        }
        return saved
    }

    // MARK: - Context Images

    func imagesDir(for agentId: String) -> URL {
        agentsDir.appendingPathComponent("images/\(agentId)")
    }

    func loadContextImages(for agentId: String) -> [PersonaContextImage] {
        let sidecar = agentsDir.appendingPathComponent("\(agentId)-images.json")
        guard let data = try? Data(contentsOf: sidecar),
              let images = try? JSONDecoder().decode([PersonaContextImage].self, from: data) else {
            return []
        }
        return images
    }

    func saveContextImages(_ images: [PersonaContextImage], for agentId: String) throws {
        let sidecar = agentsDir.appendingPathComponent("\(agentId)-images.json")
        if images.isEmpty {
            try? FileManager.default.removeItem(at: sidecar)
            return
        }
        let data = try JSONEncoder().encode(images)
        try data.write(to: sidecar, options: .atomic)
    }

    func saveContextImage(_ image: NSImage, agentId: String) throws -> PersonaContextImage {
        let fm = FileManager.default
        let dir = imagesDir(for: agentId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw AgentError.saveError("Bild konnte nicht konvertiert werden.")
        }
        try jpegData.write(to: fileURL)
        return PersonaContextImage(filename: filename, description: "")
    }

    func deleteContextImage(_ image: PersonaContextImage, agentId: String) {
        let fileURL = imagesDir(for: agentId).appendingPathComponent(image.filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func loadContextImageData(_ image: PersonaContextImage, agentId: String) -> NSImage? {
        let fileURL = imagesDir(for: agentId).appendingPathComponent(image.filename)
        return NSImage(contentsOf: fileURL)
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

    // MARK: - Dream mode

    /// Returns the date string from last_dream.txt for an agent, or nil if never dreamed.
    func lastDreamDate(for agent: AgentDefinition) -> String? {
        let (primary, secondary) = memoryDirs(for: agent)
        for dir in [primary, secondary] {
            let url = dir.appendingPathComponent("last_dream.txt")
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count == 10, t.contains("-") { return t }
            }
        }
        return nil
    }

    /// Returns the last dream date as a Date (midnight of that day) for schedule comparison.
    private func lastDreamDateAsDate(for agent: AgentDefinition) -> Date? {
        guard let s = lastDreamDate(for: agent) else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: s)
    }

    /// Consolidates an agent's MEMORY.md + learning_log.txt into a cleaner MEMORY.md via Claude.
    func dreamAgent(_ agent: AgentDefinition) async {
        guard !dreamingAgents.contains(agent.id), let cli = cliService else { return }
        dreamingAgents.insert(agent.id)
        defer { dreamingAgents.remove(agent.id) }

        let memContent = readMemoryFile(named: "MEMORY.md",        for: agent) ?? "(leer)"
        let logContent = readMemoryFile(named: "learning_log.txt", for: agent) ?? "(leer)"

        let systemPrompt = """
You are a memory consolidator for AI agent "\(agent.name)".
Output ONLY the new MEMORY.md content — no preamble, no fences, no explanations.

Required sections (in this order):
## Core Insights
## What Works
## What to Avoid
## Archived

Rules:
- Keep only what is still actionable and relevant.
- Each bullet = one sentence, starts with a strong verb.
- Merge similar insights into one bullet.
- Move outdated items to ## Archived with a brief note; remove trivial ones entirely.
- Preserve: domain facts, confirmed failure patterns, source-reliability notes.
- Output must be shorter than the combined input.
"""

        let userMessage = """
Consolidate memory for "\(agent.name)".

--- MEMORY.md ---
\(memContent)

--- learning_log.txt ---
\(logContent)
"""

        var output = ""
        do {
            let stream = cli.send(
                message: userMessage,
                systemPrompt: systemPrompt,
                model: agent.model.isEmpty ? nil : agent.model,
                workingDirectory: nil,
                skipPermissions: true,
                maxTurns: 5
            )
            let deadline = Date().addingTimeInterval(10 * 60)
            for try await event in stream {
                if Date() > deadline { break }
                if event.type == "assistant", let contents = event.message?.content {
                    for c in contents where c.type == "text" { output += c.text ?? "" }
                }
            }
        } catch { return }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let dir     = writableMemoryDir(for: agent)
        let memURL  = dir.appendingPathComponent("MEMORY.md")
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let today   = dateFmt.string(from: Date())

        try? trimmed.write(to: memURL, atomically: true, encoding: .utf8)
        try? today.write(
            to: dir.appendingPathComponent("last_dream.txt"),
            atomically: true, encoding: .utf8
        )
    }

    /// Builds a context preamble from MEMORY.md + learning_log.txt to inject before the system prompt.
    /// - Parameter orchestratorMode: in Multi-Agent-Läufen wird der Preamble PRO Agent gesendet;
    ///   dann MEMORY.md kappen und die Memory-Maintenance-Instruktion weglassen (E — der Agent
    ///   soll in der Orchestrierung liefern, nicht Memory pflegen).
    private func buildContextPreamble(for agent: AgentDefinition, orchestratorMode: Bool = false) -> String {
        var parts: [String] = []

        // Current date — so agents write correct timestamps
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let todayString = dateFmt.string(from: Date())
        parts.append("## Current Date\nToday is \(todayString). Always use this date when writing timestamps or \"Last updated\" markers.")

        let memDir = writableMemoryDir(for: agent)
        let memPath = memDir.appendingPathComponent("MEMORY.md").path

        // Persistent MEMORY.md — im Orchestrator-Modus gekappt (E), da pro Agent gesendet.
        if let mem = readMemoryFile(named: "MEMORY.md", for: agent) {
            let trimmed = mem.trimmingCharacters(in: .whitespacesAndNewlines)
            let memText = (orchestratorMode && trimmed.count > OrchestratorLimits.memoryCapOrchestrator)
                ? String(trimmed.prefix(OrchestratorLimits.memoryCapOrchestrator)) + "\n…[gekürzt]"
                : trimmed
            parts.append("## Your Persistent Memory\n\(memText)")
        }

        // Learning log — last 20 entries, CHAT entries excluded
        if let logContent = readMemoryFile(named: "learning_log.txt", for: agent) {
            let lines = logContent
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.contains("| CHAT |") }
            let recent = Array(lines.suffix(20))
            if !recent.isEmpty {
                parts.append("## Your Learning Log (last \(recent.count) entries)\n" + recent.joined(separator: "\n"))
            }
        }

        // Skills — extract 🛠 Skill Recommendations and surface prominently in preamble
        let bodyForSkills = agent.promptBody
        if let range = bodyForSkills.range(of: "## 🛠 Skill Recommendations") {
            let fromSection = String(bodyForSkills[range.lowerBound...])
            let trimmedSkills: String
            if let nextHeader = fromSection.range(of: "\n## ", options: [], range: fromSection.index(after: fromSection.startIndex)..<fromSection.endIndex) {
                trimmedSkills = String(fromSection[..<nextHeader.lowerBound])
            } else {
                trimmedSkills = fromSection
            }
            let content = trimmedSkills.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                parts.append("## Your Recommended Skills & Tools\nActively use the tools and libraries listed below when choosing your approach for this session:\n\n\(content)")
            }
        }

        // Memory maintenance instruction — agent updates its own MEMORY.md autonomously.
        // E: im Orchestrator-Modus weglassen — der Agent soll liefern, nicht Memory pflegen
        // (spart ~600 Zeichen PRO Agent und keine Turns für Datei-Schreibvorgänge).
        if !orchestratorMode {
        let memInstruction = """
## Memory Maintenance
Your persistent memory file is at: `\(memPath)`
During or after your work in this session, update this file autonomously using your write tools.
Track what worked well, what failed, and what to avoid next time.
Keep it concise — short bullet points under `## What Worked` and `## What to Avoid`.
Do not ask for confirmation. Just write the file silently as part of your work.

At the very end of your final response, output exactly one line in this format:
LEARNED: <one concise sentence summarising the most important insight from this session>
Only include this line when you have a genuine technical or domain insight worth remembering — omit it for routine tasks.
"""
            parts.append(memInstruction)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Records a completed chat session in the agent's learning log.
    /// Only writes an entry when the output contains an explicit "LEARNED:" line.
    func recordChatSession(agentId: String, output: String) {
        guard let agent = agents.first(where: { $0.id == agentId }) else { return }
        guard let learned = extractLearnedLine(from: output) else { return }
        let dir = writableMemoryDir(for: agent)
        let logURL = dir.appendingPathComponent("learning_log.txt")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let summary = String(
            learned.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .prefix(300)
        )
        let line = "\(fmt.string(from: Date())) | LEARN | \(summary)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }

    /// Returns today's learning log entries for an agent (all sources).
    func todaysLearnings(for agent: AgentDefinition) -> [String] {
        guard let log = readMemoryFile(named: "learning_log.txt", for: agent) else { return [] }
        let today = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()
        return log.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(today) }
    }

    /// Returns the full system prompt for an agent (preamble + promptBody).
    /// Used by the chat flow to inject agent identity and memory context.
    func fullSystemPrompt(for agent: AgentDefinition, orchestratorMode: Bool = false) -> String {
        let preamble = buildContextPreamble(for: agent, orchestratorMode: orchestratorMode)
        let body = agent.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return preamble }
        return preamble + "\n\n---\n\n" + body
    }

    /// Appends one timestamped entry to the agent's learning_log.txt.
    /// No-op when learned is nil (no LEARNED marker found in output).
    private func appendLearningEntry(for agent: AgentDefinition, status: ScheduledTaskStatus, learned: String?) {
        guard let learned else { return }
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

    /// Extracts the `LEARNED:` line from agent output.
    /// Returns nil when no explicit LEARNED marker is present — no fallback.
    private func extractLearnedLine(from output: String) -> String? {
        for line in output.components(separatedBy: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("learned:") {
                let value = t.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return String(value) }
            }
        }
        return nil
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
        for agent in agents {
            // Normal task schedule — requires isActive
            if agent.isActive, let schedule = agent.schedule, !schedule.isEmpty,
               !runningAgents.contains(agent.id) {
                let lastRun = logs[agent.id]?.last?.startedAt
                if isDue(schedule: schedule, lastRun: lastRun, now: now) {
                    await executeScheduledAgent(agent)
                }
            }
            // Dream schedule — works regardless of isActive
            if let ds = agent.dreamSchedule, !ds.isEmpty,
               !dreamingAgents.contains(agent.id) {
                let lastDream = lastDreamDateAsDate(for: agent)
                if isDue(schedule: ds, lastRun: lastDream, now: now) {
                    await dreamAgent(agent)
                }
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

    /// Fallback model used when Claude rate limit is active.
    private static let copilotFallbackModel = "github/claude-sonnet-4-5"

    func executeScheduledAgent(_ agent: AgentDefinition) async {
        let rateLimitActive = appState?.claudeRateLimitActive == true
        let cliAvailable    = cliService != nil

        // Need either CLI (no rate limit) or rate-limit-fallback via Copilot
        if !rateLimitActive, !cliAvailable {
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

        let timeoutSeconds: TimeInterval = TimeInterval(agent.timeoutMinutes * 60)
        // Single shared deadline across ALL retries — a flapping network must NOT
        // extend the agent's total runtime beyond its configured timeout.
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        // Rate-limited before we even start → go straight to the Copilot fallback.
        if rateLimitActive {
            await executeScheduledAgentViaCopilot(agent, entry: &entry)
            let learnedR = extractLearnedLine(from: liveOutput[agent.id] ?? "")
            if let learnedR { appendLearningEntry(for: agent, status: entry.status, learned: learnedR) }
            liveOutput.removeValue(forKey: agent.id)
            runningAgents.remove(agent.id)
            updateEntry(entry)
            return
        }

        // Build enriched system prompt: preamble (memory + learning log) + body.
        let preamble = buildContextPreamble(for: agent)
        let body     = agent.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = body.isEmpty ? preamble : preamble + "\n\n---\n\n" + body
        let userMessage = "Begin your session now. Execute your defined role as described in your system prompt — do not wait for further instructions."

        // CLI path with bounded retry on transient network errors. The researcher
        // makes many web-search calls over up to 60 min; a single dropped connection
        // ("The network connection was lost") used to abort the whole run with no
        // retry (only rate-limits had a fallback). We now resume the SAME session
        // — preserving the work done so far — up to maxAttempts with backoff.
        let maxAttempts = 4
        var attempt = 0
        var resumeId: String? = nil
        var triedFreshAfterStale = false
        var outputText = ""
        var resultText = ""

        retryLoop: while true {
            let outcome = await runCLIAgentAttempt(
                agent: agent, instructions: instructions, userMessage: userMessage,
                resumeSessionId: resumeId, deadline: deadline
            )
            switch outcome {
            case .completed(let out, let res):
                outputText = out
                resultText = res
                entry.status = .success
                // Prefer a dedicated daily report file if the agent wrote one this run
                // (agents can write to name/ or id/ directory).
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
                break retryLoop

            case .rateLimited(let combined):
                // Rate-limit detected mid-run → switch to the Copilot fallback.
                appState?.parseRateLimitExpiry(from: combined.lowercased())
                appState?.claudeRateLimitActive = true
                entry.status = .running
                entry.error  = ""
                await executeScheduledAgentViaCopilot(agent, entry: &entry)
                let learnedR = extractLearnedLine(from: liveOutput[agent.id] ?? "")
                if let learnedR { appendLearningEntry(for: agent, status: entry.status, learned: learnedR) }
                liveOutput.removeValue(forKey: agent.id)
                runningAgents.remove(agent.id)
                updateEntry(entry)
                return

            case .timedOut(let partial):
                entry.status = .failed
                entry.error  = "Timeout nach \(Int(timeoutSeconds / 60)) Minuten."
                if !partial.isEmpty {
                    entry.output = partial.count > 800 ? "…\n" + String(partial.suffix(800)) : partial
                }
                entry.finishedAt = Date()
                break retryLoop

            case .transient(let msg, let sid):
                attempt += 1
                resumeId = sid ?? resumeId   // continue the same session on retry
                let backoffs = [5, 15, 30]
                let backoff  = backoffs[min(attempt - 1, backoffs.count - 1)]
                // Stop if we are out of attempts OR the backoff would blow the deadline.
                guard attempt < maxAttempts,
                      Date().addingTimeInterval(TimeInterval(backoff)) < deadline else {
                    entry.status = .failed
                    entry.error  = "Netzwerkfehler nach \(attempt) Versuch(en): \(msg)"
                    entry.finishedAt = Date()
                    break retryLoop
                }
                liveOutput[agent.id, default: ""] += "\n⚠️ Netzwerkfehler — neuer Versuch \(attempt + 1)/\(maxAttempts) in \(backoff)s…\n"
                try? await Task.sleep(nanoseconds: UInt64(backoff) * 1_000_000_000)
                if Task.isCancelled {
                    entry.status = .failed
                    entry.error  = "Abgebrochen während Retry-Wartezeit."
                    entry.finishedAt = Date()
                    break retryLoop
                }
                continue retryLoop

            case .failed(let msg, let partial):
                // Safety valve: a --resume attempt whose session is gone
                // ("No conversation found …") gets ONE fresh start before giving up.
                if resumeId != nil, !triedFreshAfterStale,
                   msg.lowercased().contains("no conversation found") {
                    triedFreshAfterStale = true
                    resumeId = nil
                    liveOutput[agent.id, default: ""] += "\n⚠️ Session abgelaufen — Neustart…\n"
                    continue retryLoop
                }
                entry.status = .failed
                entry.error  = msg
                if !partial.isEmpty {
                    entry.output = partial.count > 800 ? "…\n" + String(partial.suffix(800)) : partial
                }
                entry.finishedAt = Date()
                break retryLoop
            }
        }

        // Write learning log entry only when agent produced a LEARNED: marker.
        let learnSource = outputText.isEmpty ? (liveOutput[agent.id] ?? "") : outputText
        if let learned = extractLearnedLine(from: learnSource) {
            appendLearningEntry(for: agent, status: entry.status, learned: learned)
        }

        liveOutput.removeValue(forKey: agent.id)
        runningAgents.remove(agent.id)
        updateEntry(entry)
    }

    // MARK: - Single attempt + transient-network classification

    private enum AgentAttemptOutcome {
        case completed(output: String, result: String)
        case rateLimited(combined: String)
        case transient(message: String, sessionId: String?)
        case failed(message: String, partialOutput: String)
        case timedOut(partialOutput: String)
    }

    /// Runs ONE CLI attempt for a scheduled agent and classifies the result.
    /// Lifecycle bookkeeping (runningAgents / entry / cleanup) is owned by the
    /// caller; this helper only streams chunks into `liveOutput` and returns a
    /// typed outcome. `resumeSessionId` (when set) continues an existing session
    /// via `--resume` so a retried run keeps the work it already did.
    private func runCLIAgentAttempt(
        agent: AgentDefinition,
        instructions: String,
        userMessage: String,
        resumeSessionId: String?,
        deadline: Date
    ) async -> AgentAttemptOutcome {
        var outputText = ""
        var resultText = ""
        var capturedSession: String? = resumeSessionId
        do {
            let stream = cliService!.send(
                message: userMessage,
                sessionId: resumeSessionId,
                systemPrompt: instructions.isEmpty ? nil : instructions,
                model: agent.model.isEmpty ? nil : agent.model,
                workingDirectory: agent.projectDirectory,
                skipPermissions: true,
                maxTurns: 50
            )
            for try await event in stream {
                if Date() > deadline { return .timedOut(partialOutput: outputText) }
                if let sid = event.sessionId, !sid.isEmpty { capturedSession = sid }
                switch event.type {
                case "assistant":
                    if let contents = event.message?.content {
                        for c in contents where c.type == "text" {
                            let chunk = c.text ?? ""
                            outputText += chunk
                            liveOutput[agent.id, default: ""] += chunk
                        }
                    }
                case "result":
                    if let r = event.result, !r.isEmpty { resultText = r }
                    if event.isError == true {
                        let combined = (event.result ?? "") + " " + (event.error ?? "") + " "
                            + (event.errors?.joined(separator: " ") ?? "") + " " + outputText
                        // Precedence: rate-limit (→ Copilot) beats transient (→ retry)
                        // beats a generic terminal failure.
                        if isRateLimitText(combined) { return .rateLimited(combined: combined) }
                        if isTransientNetworkText(combined) {
                            return .transient(
                                message: event.result ?? event.error ?? "Netzwerkfehler",
                                sessionId: capturedSession
                            )
                        }
                        // Non-rate-limit, non-transient error → terminal failure.
                        // (Previously this fell through and was wrongly logged as success.)
                        return .failed(
                            message: event.result ?? event.error
                                ?? event.errors?.joined(separator: "; ")
                                ?? "Unbekannter Fehler im Result-Event",
                            partialOutput: outputText
                        )
                    }
                case "rate_limit_event":
                    appState?.claudeRateLimitActive = true
                default:
                    break
                }
            }
            return .completed(output: outputText, result: resultText)
        } catch {
            let errText = error.localizedDescription
            let lower   = errText.lowercased()
            if isRateLimitText(lower) { return .rateLimited(combined: errText) }
            if isTransientNetworkText(lower) {
                return .transient(message: errText, sessionId: capturedSession)
            }
            return .failed(message: errText, partialOutput: outputText)
        }
    }
    // MARK: - Rate-limit helpers

    private func isRateLimitText(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("usage limits") || t.contains("rate_limit") ||
               t.contains("rate limit")   || t.contains("overloaded") ||
               t.contains("quota")        || t.contains(" 529")       ||
               t.contains(" 429")         || t.contains("regain access")
    }

    /// Transient network/connectivity failures that are worth retrying. Always
    /// check `isRateLimitText` FIRST — rate-limits have a better recovery path
    /// (Copilot fallback) and must not be swallowed by the network retry loop.
    private func isTransientNetworkText(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("network connection was lost")
            || t.contains("connection was lost")
            || t.contains("the request timed out") || t.contains("request timed out")
            || t.contains("connection reset")
            || t.contains("could not connect to")
            || t.contains("cannot connect to host")
            || t.contains("network is unreachable")
            || t.contains("connection refused")
            || t.contains("socket hang up")
            || t.contains("nsurlerrordomain")
            || t.contains("econnreset") || t.contains("etimedout")
            || t.contains("econnrefused") || t.contains("enotfound") || t.contains("eai_again")
            || t.contains("fetch failed")
            || t.contains(" 502") || t.contains(" 503") || t.contains(" 504")
            || t.contains("bad gateway") || t.contains("service unavailable")
            || t.contains("gateway timeout")
    }

    /// Runs the agent via GitHub Copilot API (used as rate-limit fallback).
    private func executeScheduledAgentViaCopilot(_ agent: AgentDefinition, entry: inout ScheduledTaskLogEntry) async {
        runningAgents.insert(agent.id)
        liveOutput[agent.id] = ""

        let timeoutSeconds: TimeInterval = TimeInterval(agent.timeoutMinutes * 60)
        let fallbackModel = agent.model.hasPrefix("github/") ? agent.model : Self.copilotFallbackModel
        let token = appState?.settings.token ?? ""

        let preamble = buildContextPreamble(for: agent)
        let body     = agent.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = body.isEmpty ? preamble : preamble + "\n\n---\n\n" + body

        var outputText = ""
        do {
            let stream = ghModelsService.send(
                message: "Begin your session now. Execute your defined role as described in your system prompt — do not wait for further instructions.",
                model: fallbackModel,
                systemPrompt: instructions.isEmpty ? nil : instructions,
                history: [],
                githubToken: token
            )
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            for try await event in stream {
                if Date() > deadline { break }
                if event.type == "assistant", let contents = event.message?.content {
                    for c in contents where c.type == "text" {
                        let chunk = c.text ?? ""
                        outputText += chunk
                        liveOutput[agent.id] = outputText
                    }
                }
            }
            entry.status    = .success
            entry.output    = outputText
            entry.finishedAt = Date()
        } catch {
            entry.status    = .failed
            entry.error     = "[Copilot Fallback] \(error.localizedDescription)"
            entry.output    = outputText
            entry.finishedAt = Date()
        }
    }

    // MARK: - Persona Email Learning

    func learnFromEmails(persona: AgentDefinition, emailText: String) async -> Result<String, Error> {
        emailLearningRunning.insert(persona.id)
        emailLearningStatus[persona.id] = "Analysiere…"
        defer {
            emailLearningRunning.remove(persona.id)
            emailLearningStatus.removeValue(forKey: persona.id)
        }
        let prompt = """
Du bist ein Experte für Persönlichkeitsanalyse und Kommunikationspsychologie.

Analysiere die folgenden E-Mails von "\(persona.name)" so tief wie möglich — als würdest du ein detailliertes psychologisches Profil für einen Coach erstellen, der diese Person perfekt imitieren soll.

Ziel: Wer dieses Profil liest, soll danach in der Lage sein, so zu urteilen, zu formulieren und zu reagieren wie "\(persona.name)" — als ob die Person direkt daneben sitzt.

Gib deine Analyse in exakt diesem Format zurück (alle Abschnitte ausfüllen, keine Abschnitte weglassen):

## Stimme & Sprache
Wie schreibt die Person? Satzlänge, Direktheit, Formalitätsniveau. Mindestens 5 typische wörtliche Phrasen oder Formulierungen aus den E-Mails zitieren.

## Entscheidungslogik
Wonach entscheidet die Person? Welche Kriterien sind ausschlaggebend (Preis, Vertrauen, Qualität, Geschwindigkeit, Beziehung...)? In welcher Reihenfolge?

## Emotionale Trigger
Was bringt die Person dazu, positiv zu reagieren? Was löst Skepsis, Ungeduld oder Ablehnung aus? Konkrete Beispiele aus den E-Mails.

## Warnsignale — wird kritisch wenn...
Was sind die impliziten Erwartungen, die nie ausgesprochen werden aber immer vorausgesetzt? Woran merkt man, dass die Person unzufrieden ist?

## Zustimmungssignale
Wie äußert die Person Zustimmung, Zufriedenheit oder Vertrauen? Typische Formulierungen und Verhaltensweisen.

## Implizite Werte & Prioritäten
Was ist der Person wirklich wichtig — auch wenn sie es nicht direkt sagt? Welche Weltanschauung oder Haltung steckt hinter den Nachrichten?

## Umgang mit Problemen & Eskalation
Wie reagiert die Person auf Fehler, Verzögerungen oder Enttäuschungen? Eskaliert sie schnell oder langsam? Direkt oder indirekt?

## Roleplay-Anweisung
Formuliere in 3–5 Sätzen eine direkte Anweisung für eine KI, wie sie sich verhalten soll wenn sie diese Person spielt. Beispiel: "Antworte immer kurz und direkt. Stelle nach jedem Ergebnis die implizite Frage: Wurde meine Zeit respektiert?"

---

E-Mails:
\(emailText.prefix(20000))
"""
        let model = "sonnet"
        var result = ""
        do {
            guard let cli = cliService else { throw AgentError.saveError("CLI nicht verfügbar") }
            let stream = cli.send(message: prompt, model: model)
            for try await event in stream {
                if event.type == "assistant" {
                    if let contents = event.message?.content {
                        for c in contents where c.type == "text" { result += c.text ?? "" }
                    }
                }
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // Erkenntnisse in Memory-Verzeichnis speichern
            let memDir = writableMemoryDir(for: persona)
            let insightsURL = memDir.appendingPathComponent("email_insights.md")
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
            let header = "# E-Mail-Erkenntnisse — \(persona.name)\nAnalysiert: \(fmt.string(from: Date()))\n\n"
            try? (header + trimmed).write(to: insightsURL, atomically: true, encoding: .utf8)
            return .success(trimmed)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Persona Validation

    func validateWithPersona(
        persona: AgentDefinition,
        userRequest: String,
        taskOutput: String
    ) async -> Result<PersonaValidationResult, Error> {
        let systemPrompt = persona.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
Bewerte das folgende Ergebnis aus Kundenperspektive.

Ursprüngliche Anfrage: \(userRequest.prefix(500))

Ergebnis:
\(taskOutput.prefix(3000))

Antworte NUR als valides JSON in diesem exakten Format:
{
  "score": <1-10>,
  "verdict": "<approved|revision|rejected>",
  "summary": "<1-2 Sätze>",
  "strengths": ["<punkt>"],
  "weaknesses": ["<punkt>"],
  "recommendation": "<1 Satz>"
}
"""
        let model = "sonnet"
        var raw = ""
        do {
            guard let cli = cliService else { throw AgentError.saveError("CLI nicht verfügbar") }
            let sp = systemPrompt.isEmpty ? nil : systemPrompt
            let stream = cli.send(message: prompt, systemPrompt: sp, model: "sonnet")
            for try await event in stream {
                if event.type == "assistant" {
                    if let contents = event.message?.content {
                        for c in contents where c.type == "text" { raw += c.text ?? "" }
                    }
                }
            }
            // Extract JSON block
            let jsonStr: String
            if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
                jsonStr = String(raw[start.lowerBound...end.upperBound])
            } else {
                jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(ValidationJSON.self, from: data) else {
                throw AgentError.saveError("Ungültige JSON-Antwort")
            }
            let vr = PersonaValidationResult(
                personaId: persona.id,
                personaName: persona.name,
                score: obj.score,
                verdict: ValidationVerdict(rawValue: obj.verdict) ?? .revisionNeeded,
                summary: obj.summary,
                strengths: obj.strengths,
                weaknesses: obj.weaknesses,
                recommendation: obj.recommendation,
                createdAt: Date()
            )
            return .success(vr)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Persona File Review

    func reviewFileWithPersona(
        persona: AgentDefinition,
        fileName: String,
        fileContent: String,
        livePreviewText: String? = nil,
        screenshotPath: String? = nil
    ) async -> Result<PersonaFileReview, Error> {
        let systemPrompt = persona.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build context from persona's context images (descriptions only)
        var imageContext = ""
        if !persona.contextImages.isEmpty {
            let descs = persona.contextImages
                .filter { !$0.description.isEmpty }
                .map { "- \($0.description)" }
                .joined(separator: "\n")
            if !descs.isEmpty {
                imageContext = "\n\nVisueller Kontext über dich:\n\(descs)"
            }
        }

        // Build live preview context from JS-extracted visible text
        let livePreviewSection: String
        if let visibleText = livePreviewText, !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            livePreviewSection = """


Das siehst du gerade in der gerenderten Live-Vorschau (sichtbarer Text der Seite):
\(visibleText.prefix(8000))
"""
        } else {
            livePreviewSection = ""
        }

        // Screenshot section: tell Claude about the attached image
        let screenshotSection: String
        if screenshotPath != nil {
            screenshotSection = "\n\nDas beigefügte Bild zeigt einen Screenshot der gerenderten Live-Vorschau. Beziehe dich beim Bewerten ausschließlich auf das, was du im Bild siehst — NICHT auf HTML-Code."
        } else {
            screenshotSection = ""
        }

        // Persona always evaluates the rendered result, never raw HTML source.
        // Use visible text from the live preview as primary context.
        // Only fall back to filename (no source code) when no preview text is available.
        let contentHint: String
        if livePreviewText == nil && screenshotPath == nil {
            contentHint = "\n\nDatei: \(fileName)"
        } else {
            contentHint = ""
        }

        let prompt = """
Du bist \(persona.name). Bewerte die folgende Webseite aus deiner persönlichen Perspektive als Nutzer.\(screenshotSection)
\(imageContext)\(livePreviewSection)\(contentHint)

Antworte NUR als valides JSON in exakt diesem Format (auf Deutsch, aus deiner Ich-Perspektive):
{
  "rating": <0-10>,
  "liked": ["<was dir gefällt>", ...],
  "disliked": ["<was dir nicht gefällt>", ...],
  "wishes": ["<konkreter Wunsch / Verbesserung>", ...],
  "summary": "<2-3 Sätze persönliches Fazit>"
}

Wichtig:
- Mindestens 2 Einträge pro Liste
- Wünsche sollen konkret und umsetzbar sein
- Sprich in der Ich-Form, als wärst du der Kunde
"""

        var raw = ""
        do {
            guard let cli = cliService else { throw AgentError.saveError("CLI nicht verfügbar") }
            let sp = systemPrompt.isEmpty ? nil : systemPrompt
            let imgPaths: [String] = screenshotPath.map { [$0] } ?? []
            let stream = cli.send(message: prompt, systemPrompt: sp, model: "sonnet", imagePaths: imgPaths)
            for try await event in stream {
                if event.type == "assistant" {
                    if let contents = event.message?.content {
                        for c in contents where c.type == "text" { raw += c.text ?? "" }
                    }
                } else if event.type == "result", let resultText = event.result, !resultText.isEmpty {
                    // Fallback: CLI liefert Gesamttext im result-Event
                    if raw.isEmpty { raw = resultText }
                }
            }
            let jsonStr: String
            if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
                jsonStr = String(raw[start.lowerBound..<end.upperBound])
            } else {
                jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(ReviewJSON.self, from: data) else {
                throw AgentError.saveError("KI-Antwort konnte nicht geparst werden (kein gültiges JSON). Bitte erneut versuchen.")
            }
            return .success(PersonaFileReview(
                personaId: persona.id,
                personaName: persona.name,
                rating: max(0, min(10, obj.rating)),
                liked: obj.liked,
                disliked: obj.disliked,
                wishes: obj.wishes,
                summary: obj.summary,
                createdAt: Date()
            ))
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Validation JSON helper

private struct ValidationJSON: Decodable {
    let score: Int
    let verdict: String
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let recommendation: String
}

private struct ReviewJSON: Decodable {
    let rating: Int
    let liked: [String]
    let disliked: [String]
    let wishes: [String]
    let summary: String
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

