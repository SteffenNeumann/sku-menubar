import Foundation

@MainActor
final class AgentService: ObservableObject {

    @Published var agents: [AgentDefinition] = []

    private let home = NSHomeDirectory()

    var agentsDir: URL {
        URL(fileURLWithPath: "\(home)/.claude/agents")
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
            // Strip surrounding quotes
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

    // MARK: - Agent memory

    func loadAgentMemory(agentId: String) -> String? {
        let memPath = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agentId)/MEMORY.md")
        return try? String(contentsOf: memPath, encoding: .utf8)
    }
}
