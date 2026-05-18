import Foundation
import SwiftUI

// MARK: - Linear Data Models

enum LinearPriority: Int, Codable, CaseIterable {
    case urgent = 1, high = 2, medium = 3, low = 4, noPriority = 0

    var label: String {
        switch self {
        case .urgent:     return "Urgent"
        case .high:       return "High"
        case .medium:     return "Medium"
        case .low:        return "Low"
        case .noPriority: return "No Priority"
        }
    }

    var icon: String {
        switch self {
        case .urgent:     return "exclamationmark.3"
        case .high:       return "arrow.up"
        case .medium:     return "minus"
        case .low:        return "arrow.down"
        case .noPriority: return "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .urgent:     return Color(red: 0.95, green: 0.22, blue: 0.22)
        case .high:       return Color(red: 0.95, green: 0.50, blue: 0.15)
        case .medium:     return Color(red: 0.95, green: 0.78, blue: 0.15)
        case .low:        return Color(red: 0.45, green: 0.70, blue: 0.95)
        case .noPriority: return Color.secondary
        }
    }

    init(rawValue: Int) {
        switch rawValue {
        case 1: self = .urgent
        case 2: self = .high
        case 3: self = .medium
        case 4: self = .low
        default: self = .noPriority
        }
    }
}

struct LinearIssueState: Identifiable {
    let id: String
    let name: String
    let type: String   // "backlog", "unstarted", "started", "completed", "cancelled"
    let color: String

    var displayColor: Color {
        switch type {
        case "started":   return Color(red: 0.35, green: 0.50, blue: 0.98)
        case "completed": return Color(red: 0.20, green: 0.75, blue: 0.45)
        case "cancelled": return .secondary
        case "backlog":   return Color(red: 0.55, green: 0.55, blue: 0.60)
        default:          return Color(red: 0.65, green: 0.65, blue: 0.70)
        }
    }

    var isCompleted: Bool { type == "completed" || type == "cancelled" }
}

struct LinearIssue: Identifiable {
    let id: String
    let identifier: String      // e.g. "SKU-123"
    let title: String
    let description: String
    let priority: LinearPriority
    let state: LinearIssueState?
    let teamId: String
    let projectId: String?
    let assigneeName: String?
    let labels: [String]
    let createdAt: Date?
    let updatedAt: Date?
    let url: String
}

struct LinearProject: Identifiable {
    let id: String
    let name: String
    let description: String
    let state: String           // "planned", "inProgress", "paused", "completed", "cancelled"
    let icon: String?
    let color: String?
    let issueCount: Int
    let teamIds: [String]

    var displayColor: Color {
        guard let c = color, c.hasPrefix("#"), c.count == 7 else {
            return Color(red: 0.45, green: 0.35, blue: 0.90)
        }
        let r = Double(Int(c.dropFirst().prefix(2), radix: 16) ?? 0) / 255
        let g = Double(Int(c.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255
        let b = Double(Int(c.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255
        return Color(red: r, green: g, blue: b)
    }

    var stateColor: Color {
        switch state {
        case "inProgress": return Color(red: 0.35, green: 0.50, blue: 0.98)
        case "completed":  return Color(red: 0.20, green: 0.75, blue: 0.45)
        case "cancelled":  return .secondary
        default:           return Color(red: 0.65, green: 0.65, blue: 0.70)
        }
    }
}

struct LinearTeam: Identifiable {
    let id: String
    let name: String
    let key: String
}

// MARK: - Linear Service

@MainActor
final class LinearService: ObservableObject {

    @Published var projects: [LinearProject] = []
    @Published var issues: [String: [LinearIssue]] = [:]   // keyed by projectId
    @Published var teams: [LinearTeam] = []
    @Published var isLoading = false
    @Published var error: String?

    private var session: MCPClientSession?
    private var configuredApiKey: String?

    func configure(config: MCPServerConfig) {
        let newKey = config.envVars.first(where: { $0.hasPrefix("LINEAR_API_KEY=") })
        if newKey != configuredApiKey || session == nil {
            session?.stop()
            session = MCPClientSession(config: config)
            configuredApiKey = newKey
        }
    }

    func loadProjects() async {
        guard let session else { error = "Linear MCP nicht konfiguriert"; return }
        isLoading = true
        error = nil
        do {
            if !(try await{ try await session.connect(); return true }()) { return }
            let raw = try await session.callTool(name: "linear_list_projects", arguments: [:])
            projects = parseProjects(from: raw)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadIssues(projectId: String, teamId: String? = nil) async {
        guard let session else { return }
        isLoading = true
        do {
            var args: [String: Any] = ["includeArchived": false]
            if !projectId.isEmpty { args["projectId"] = projectId }
            let raw = try await session.callTool(name: "linear_search_issues", arguments: args)
            issues[projectId] = parseIssues(from: raw)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadTeamIssues(teamKey: String) async -> [LinearIssue] {
        guard let session else { return [] }
        do {
            let raw = try await session.callTool(name: "linear_search_issues",
                                                 arguments: ["teamKey": teamKey, "includeArchived": false])
            return parseIssues(from: raw)
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    func loadTeams() async {
        guard let session else { return }
        do {
            let raw = try await session.callTool(name: "linear_get_teams", arguments: [:])
            teams = parseTeams(from: raw)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateIssueStatus(issueId: String, stateId: String) async throws {
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_search_issues",
                                       arguments: ["id": issueId, "stateId": stateId])
    }

    func createIssue(teamId: String, title: String, description: String, priority: Int = 0) async throws -> String {
        guard let session else { throw LinearError.notConfigured }
        return try await session.callTool(name: "linear_create_issue", arguments: [
            "teamId": teamId, "title": title, "description": description, "priority": priority
        ])
    }

    func stopSession() {
        session?.stop()
        session = nil
    }

    // MARK: - JSON Parsing helpers

    private func parseProjects(from raw: String) -> [LinearProject] {
        guard let data = raw.data(using: .utf8) else { return [] }

        // MCP returns either a direct array or { projects: [...] }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let arr: [[String: Any]]
        if let nodes = json?["projects"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json?["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            arr = direct
        } else {
            return []
        }

        return arr.compactMap { d -> LinearProject? in
            guard let id   = d["id"]   as? String,
                  let name = d["name"] as? String else { return nil }
            let teamIds = (d["teams"] as? [String: Any]).flatMap {
                ($0["nodes"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            } ?? []
            return LinearProject(
                id:          id,
                name:        name,
                description: (d["description"] as? String) ?? "",
                state:       (d["state"] as? String) ?? "planned",
                icon:        d["icon"] as? String,
                color:       d["color"] as? String,
                issueCount:  (d["issueCount"] as? Int) ?? 0,
                teamIds:     teamIds
            )
        }
    }

    private func parseIssues(from raw: String) -> [LinearIssue] {
        guard let data = raw.data(using: .utf8) else { return [] }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let arr: [[String: Any]]
        if let nodes = json?["issues"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json?["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            arr = direct
        } else {
            return []
        }

        let iso = ISO8601DateFormatter()

        return arr.compactMap { d -> LinearIssue? in
            guard let id    = d["id"]         as? String,
                  let ident = d["identifier"] as? String,
                  let title = d["title"]      as? String else { return nil }

            let stateDict = d["state"] as? [String: Any]
            let issueState: LinearIssueState? = stateDict.flatMap { s in
                guard let sid  = s["id"]   as? String,
                      let snam = s["name"] as? String else { return nil }
                return LinearIssueState(id: sid, name: snam,
                                        type:  (s["type"]  as? String) ?? "unstarted",
                                        color: (s["color"] as? String) ?? "#aaaaaa")
            }

            let assigneeDict = d["assignee"] as? [String: Any]
            let assigneeName = assigneeDict?["displayName"] as? String
                            ?? assigneeDict?["name"] as? String

            let labelsData  = (d["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            let labels      = labelsData.compactMap { $0["name"] as? String }

            return LinearIssue(
                id:           id,
                identifier:   ident,
                title:        title,
                description:  (d["description"] as? String) ?? "",
                priority:     LinearPriority(rawValue: (d["priority"] as? Int) ?? 0),
                state:        issueState,
                teamId:       (d["team"] as? [String: Any])?["id"] as? String ?? "",
                projectId:    (d["project"] as? [String: Any])?["id"] as? String,
                assigneeName: assigneeName,
                labels:       labels,
                createdAt:    (d["createdAt"] as? String).flatMap { iso.date(from: $0) },
                updatedAt:    (d["updatedAt"] as? String).flatMap { iso.date(from: $0) },
                url:          (d["url"] as? String) ?? ""
            )
        }
    }

    private func parseTeams(from raw: String) -> [LinearTeam] {
        guard let data = raw.data(using: .utf8) else { return [] }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let arr: [[String: Any]]
        if let nodes = json?["teams"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json?["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            arr = direct
        } else {
            return []
        }
        return arr.compactMap { d in
            guard let id  = d["id"]  as? String,
                  let nam = d["name"] as? String else { return nil }
            return LinearTeam(id: id, name: nam, key: (d["key"] as? String) ?? "")
        }
    }
}

enum LinearError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "Linear MCP nicht konfiguriert" }
}
