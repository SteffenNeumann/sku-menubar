import Foundation

@MainActor
final class AgentService: ObservableObject {

    enum AgentServiceError: LocalizedError {
        case emptyName
        case invalidIdentifier
        case duplicateIdentifier(String)
        case deleteFailed
        case exportFailed
        case invalidAgentFile
        case importFailed
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Bitte einen Agent-Namen eintragen."
            case .invalidIdentifier:
                return "Bitte eine gueltige Kennung oder einen Namen angeben."
            case .duplicateIdentifier(let id):
                return "Ein Agent mit der Kennung \(id) existiert bereits."
            case .deleteFailed:
                return "Der Agent konnte nicht geloescht werden."
            case .exportFailed:
                return "Der Agent konnte nicht exportiert werden."
            case .invalidAgentFile:
                return "Die ausgewaehlte Datei ist keine gueltige Agent-Datei."
            case .importFailed:
                return "Der Agent konnte nicht importiert werden."
            case .saveFailed:
                return "Der Agent konnte nicht gespeichert werden."
            }
        }
    }

    @Published var agents: [AgentDefinition] = []

    private let home = NSHomeDirectory()

    var agentsDir: URL {
        URL(fileURLWithPath: "\(home)/.claude/agents")
    }

    // MARK: - Load agents from ~/.claude/agents/*.md

    func loadAgents() async {
        guard FileManager.default.fileExists(atPath: agentsDir.path) else {
            agents = []
            return
        }

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
            value = decodeFrontmatterValue(value)
            fields[key] = value
        }

        let name        = fields["name"] ?? url.deletingPathExtension().lastPathComponent
        let description = fields["description"] ?? ""
        let model       = fields["model"] ?? "sonnet"
        let color       = fields["color"]
        let memory      = fields["memory"]

        let body = lines[bodyStart...].joined(separator: "\n")

        return AgentDefinition(
            id: url.deletingPathExtension().lastPathComponent,
            name: name,
            description: description,
            model: model,
            color: color,
            memory: memory,
            promptBody: body,
            filePath: url.path
        )
    }

    // MARK: - Save agents

    func saveAgent(_ draft: AgentDraft, previousId: String? = nil) async throws -> AgentDefinition {
        var normalized = normalizedDraft(draft)

        guard !normalized.name.isEmpty else {
            throw AgentServiceError.emptyName
        }

        if normalized.id.isEmpty {
            normalized.id = makeIdentifier(from: normalized.name)
        }

        guard !normalized.id.isEmpty else {
            throw AgentServiceError.invalidIdentifier
        }

        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let targetURL = agentsDir.appendingPathComponent("\(normalized.id).md")
        let existingURL = previousId.map { agentsDir.appendingPathComponent("\($0).md") }

        if let previousId, previousId != normalized.id {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                throw AgentServiceError.duplicateIdentifier(normalized.id)
            }
            if let existingURL, FileManager.default.fileExists(atPath: existingURL.path) {
                try FileManager.default.moveItem(at: existingURL, to: targetURL)
                moveAgentMemory(from: previousId, to: normalized.id)
            }
        } else if previousId == nil, FileManager.default.fileExists(atPath: targetURL.path) {
            throw AgentServiceError.duplicateIdentifier(normalized.id)
        }

        let content = serializeAgentFile(normalized)
        try content.write(to: targetURL, atomically: true, encoding: .utf8)

        await loadAgents()

        guard let saved = agents.first(where: { $0.id == normalized.id }) else {
            throw AgentServiceError.saveFailed
        }
        return saved
    }

    func duplicateAgent(_ agent: AgentDefinition) async throws -> AgentDefinition {
        var draft = AgentDraft(agent: agent)
        draft.id = nextAvailableIdentifier(basedOn: "\(agent.id)-copy")
        draft.name = nextAvailableName(basedOn: agent.name)
        return try await saveAgent(draft)
    }

    func importAgent(from sourceURL: URL) async throws -> AgentDefinition {
        guard let imported = parseAgentFile(sourceURL) else {
            throw AgentServiceError.invalidAgentFile
        }

        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let targetId = nextAvailableIdentifier(basedOn: imported.id)
        let targetURL = agentsDir.appendingPathComponent("\(targetId).md")

        do {
            let content = try String(contentsOf: sourceURL, encoding: .utf8)
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            throw AgentServiceError.importFailed
        }

        await loadAgents()

        guard let saved = agents.first(where: { $0.id == targetId }) else {
            throw AgentServiceError.importFailed
        }
        return saved
    }

    func exportAgent(_ agent: AgentDefinition, to destinationURL: URL) throws {
        let sourceURL = URL(fileURLWithPath: agent.filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AgentServiceError.exportFailed
        }

        let targetURL: URL
        if destinationURL.pathExtension.lowercased() == "md" {
            targetURL = destinationURL
        } else {
            targetURL = destinationURL.appendingPathExtension("md")
        }

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        } catch {
            throw AgentServiceError.exportFailed
        }
    }

    func deleteAgent(agentId: String) async throws {
        let fileURL = agentsDir.appendingPathComponent("\(agentId).md")
        let memoryURL = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agentId)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AgentServiceError.deleteFailed
        }

        try FileManager.default.removeItem(at: fileURL)

        if FileManager.default.fileExists(atPath: memoryURL.path) {
            try? FileManager.default.removeItem(at: memoryURL)
        }

        await loadAgents()
    }

    // MARK: - Agent memory

    func loadAgentMemory(agentId: String) -> String? {
        let memPath = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agentId)/MEMORY.md")
        return try? String(contentsOf: memPath, encoding: .utf8)
    }

    func previewAgentFile(_ draft: AgentDraft) -> String {
        serializeAgentFile(normalizedDraft(draft))
    }

    private func normalizedDraft(_ draft: AgentDraft) -> AgentDraft {
        var normalized = draft
        normalized.id = makeIdentifier(from: normalized.id)
        normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.description = normalized.description.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.model = normalized.model.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.color = normalized.color.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.memory = normalized.memory.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.promptBody = normalized.promptBody.trimmingCharacters(in: .newlines)
        if normalized.model.isEmpty {
            normalized.model = "sonnet"
        }
        return normalized
    }

    private func makeIdentifier(from value: String) -> String {
        let lowercased = value.lowercased()
        let replaced = lowercased.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func decodeFrontmatterValue(_ value: String) -> String {
        if value.hasPrefix("\"") && value.hasSuffix("\""),
           let data = "[\(value)]".data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
           let first = decoded.first {
            return first
        }

        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }

    private func encodedFrontmatterValue(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let wrapped = String(data: data, encoding: .utf8) else {
            return "\"\(value)\""
        }
        return String(wrapped.dropFirst().dropLast())
    }

    private func serializeAgentFile(_ draft: AgentDraft) -> String {
        var lines = [
            "---",
            "name: \(encodedFrontmatterValue(draft.name))",
            "description: \(encodedFrontmatterValue(draft.description))",
            "model: \(encodedFrontmatterValue(draft.model))"
        ]

        if !draft.color.isEmpty {
            lines.append("color: \(encodedFrontmatterValue(draft.color))")
        }
        if !draft.memory.isEmpty {
            lines.append("memory: \(encodedFrontmatterValue(draft.memory))")
        }

        lines.append("---")
        lines.append("")
        lines.append(draft.promptBody)

        return lines.joined(separator: "\n") + "\n"
    }

    private func moveAgentMemory(from oldId: String, to newId: String) {
        let baseURL = URL(fileURLWithPath: "\(home)/.claude/agent-memory")
        let oldURL = baseURL.appendingPathComponent(oldId)
        let newURL = baseURL.appendingPathComponent(newId)

        guard oldId != newId,
              FileManager.default.fileExists(atPath: oldURL.path),
              !FileManager.default.fileExists(atPath: newURL.path) else {
            return
        }

        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    private func nextAvailableIdentifier(basedOn base: String) -> String {
        let normalizedBase = makeIdentifier(from: base)
        guard !normalizedBase.isEmpty else { return "agent-copy" }

        var candidate = normalizedBase
        var index = 2

        while FileManager.default.fileExists(
            atPath: agentsDir.appendingPathComponent("\(candidate).md").path
        ) {
            candidate = "\(normalizedBase)-\(index)"
            index += 1
        }

        return candidate
    }

    private func nextAvailableName(basedOn base: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedBase.isEmpty ? "Agent" : trimmedBase
        let existingNames = Set(agents.map(\.name))

        let firstCandidate = "\(fallback) Kopie"
        guard existingNames.contains(firstCandidate) else { return firstCandidate }

        var index = 2
        while existingNames.contains("\(fallback) Kopie \(index)") {
            index += 1
        }
        return "\(fallback) Kopie \(index)"
    }
}
