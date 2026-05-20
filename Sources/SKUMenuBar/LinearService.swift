import Foundation
import SwiftUI

// MARK: - Linear Data Models

enum LinearPriority: Int, Codable, CaseIterable {
    case noPriority = 0, urgent = 1, high = 2, medium = 3, low = 4

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

    init(int value: Int) {
        self = LinearPriority(rawValue: value) ?? .noPriority
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
    let dueDate: Date?
    let cycleName: String?
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
    var states: [LinearIssueState] = []
}

struct LinearComment: Identifiable {
    let id: String
    let body: String
    let authorName: String
    let createdAt: Date?
}

// MARK: - Linear Service

@MainActor
final class LinearService: ObservableObject {

    @Published var projects: [LinearProject] = []
    @Published var issues: [String: [LinearIssue]] = [:]   // keyed by projectId
    @Published var teams: [LinearTeam] = []
    @Published var comments: [String: [LinearComment]] = [:]  // keyed by issueId
    @Published var isLoading = false
    @Published var error: String?

    private var session: MCPClientSession?
    private var sessionConnected = false

    func configure(config: MCPServerConfig) {
        session?.stop()
        session = MCPClientSession(config: config)
        sessionConnected = false
    }

    private func ensureConnected() async throws {
        guard let session else { throw LinearError.notConfigured }
        if !sessionConnected {
            try await session.connect()
            sessionConnected = true
        }
    }

    func loadProjects() async {
        isLoading = true
        error = nil
        do {
            try await ensureConnected()
            guard let session else { throw LinearError.notConfigured }
            let raw = try await session.callTool(name: "linear_list_projects", arguments: [:])
            projects = parseProjects(from: raw)
        } catch {
            self.error = error.localizedDescription
            sessionConnected = false
        }
        isLoading = false
    }

    func loadIssues(projectId: String) async {
        isLoading = true
        do {
            try await ensureConnected()
            guard let session else { throw LinearError.notConfigured }
            // Use nested filter syntax: filter.project.id.eq
            let args: [String: Any] = [
                "filter": ["project": ["id": ["eq": projectId]]],
                "first": 100
            ]
            let raw = try await session.callTool(name: "linear_search_issues", arguments: args)
            issues[projectId] = parseIssues(from: raw)
        } catch {
            self.error = error.localizedDescription
            sessionConnected = false
        }
        isLoading = false
    }

    func loadAllIssues(teamId: String) async -> [LinearIssue] {
        do {
            try await ensureConnected()
            guard let session else { return [] }
            let args: [String: Any] = ["teamIds": [teamId], "first": 100]
            let raw = try await session.callTool(name: "linear_search_issues", arguments: args)
            return parseIssues(from: raw)
        } catch {
            self.error = error.localizedDescription
            sessionConnected = false
            return []
        }
    }

    func loadTeams() async {
        do {
            try await ensureConnected()
            guard let session else { throw LinearError.notConfigured }
            let raw = try await session.callTool(name: "linear_get_teams", arguments: [:])
            teams = parseTeams(from: raw)
        } catch {
            self.error = error.localizedDescription
            sessionConnected = false
        }
    }

    func createIssue(teamId: String, title: String, description: String, priority: Int = 0, projectId: String? = nil) async throws -> String {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String: Any] = ["teamId": teamId, "title": title, "description": desc.isEmpty ? " " : desc, "priority": priority]
        if let pid = projectId, !pid.isEmpty { args["projectId"] = pid }
        return try await session.callTool(name: "linear_create_issue", arguments: args)
    }

    func updateIssueStatus(issueId: String, stateId: String) async throws {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_bulk_update_issues", arguments: [
            "issueIds": [issueId],
            "update": ["stateId": stateId]
        ])
    }

    func updateIssuePriority(issueId: String, priority: Int) async throws {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_bulk_update_issues", arguments: [
            "issueIds": [issueId],
            "update": ["priority": priority]
        ])
    }

    func updateIssueTitle(issueId: String, title: String) async throws {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_bulk_update_issues", arguments: [
            "issueIds": [issueId],
            "update": ["title": title]
        ])
    }

    func addComment(issueId: String, body: String) async throws {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_create_comment", arguments: [
            "issueId": issueId, "body": body
        ])
    }

    func loadComments(issueId: String, identifier: String) async {
        do {
            try await ensureConnected()
            guard let session else { throw LinearError.notConfigured }
            let raw = try await session.callTool(name: "linear_search_issues_by_identifier", arguments: [
                "identifiers": [identifier]
            ])
            comments[issueId] = parseComments(from: raw)
        } catch {
            // Comments are non-critical — don't set global error
        }
    }

    private func parseComments(from raw: String) -> [LinearComment] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        // Navigate to comments in the issue response
        var commentsNodes: [[String: Any]] = []
        if let issues = json["issues"] as? [[String: Any]],
           let first = issues.first,
           let comms = first["comments"] as? [String: Any],
           let nodes = comms["nodes"] as? [[String: Any]] {
            commentsNodes = nodes
        } else if let comms = json["comments"] as? [String: Any],
                  let nodes = comms["nodes"] as? [[String: Any]] {
            commentsNodes = nodes
        }
        // Also try flat structure from linear_search_issues_by_identifier response
        if commentsNodes.isEmpty, let nodes = json["comments"] as? [[String: Any]] {
            commentsNodes = nodes
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        return commentsNodes.compactMap { c -> LinearComment? in
            guard let id = c["id"] as? String else { return nil }
            let user = c["user"] as? [String: Any]
            let dateStr = c["createdAt"] as? String
            let date = dateStr.flatMap { iso.date(from: $0) ?? isoFallback.date(from: $0) }
            return LinearComment(
                id: id,
                body: (c["body"] as? String) ?? "",
                authorName: (user?["name"] as? String) ?? (user?["displayName"] as? String) ?? "Unbekannt",
                createdAt: date
            )
        }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func createProject(teamId: String, name: String, description: String = "") async throws -> (id: String, name: String) {
        try await ensureConnected()
        guard let session else { throw LinearError.notConfigured }
        _ = try await session.callTool(name: "linear_create_project_with_issues", arguments: [
            "teamIds": [teamId],
            "name": name,
            "description": description
        ])
        // Response is plain text ("Project: <name>\nProject URL: ...") — no UUID available.
        // Fetch the real project ID by listing projects and matching by name.
        let listRaw = try await session.callTool(name: "linear_list_projects", arguments: [:])
        let projectList = parseProjects(from: listRaw)
        if let found = projectList.first(where: { $0.name == name }) {
            return (found.id, found.name)
        }
        // Fallback: return name as placeholder (issue will still be created in team, just unlinked)
        return ("", name)
    }

    func loadIssueStates(teamId: String) async -> [LinearIssueState] {
        if teams.isEmpty { await loadTeams() }
        return teams.first(where: { $0.id == teamId })?.states ?? []
    }

    /// Returns first state ID matching the given type ("backlog","started","completed","cancelled").
    func stateId(for type: String, in states: [LinearIssueState]) -> String? {
        states.first { $0.type == type }?.id
    }

    func stopSession() {
        session?.stop()
        session = nil
        sessionConnected = false
    }

    // MARK: - JSON Parsing helpers
    // Response format: { "projects": { "nodes": [...] } }

    private func parseProjects(from raw: String) -> [LinearProject] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let arr: [[String: Any]]
        if let outer = json["projects"] as? [String: Any],
           let nodes = outer["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = json["projects"] as? [[String: Any]] {
            arr = direct
        } else {
            return []
        }

        return arr.compactMap { d -> LinearProject? in
            guard let id   = d["id"]   as? String,
                  let name = d["name"] as? String else { return nil }
            let teamsOuter = d["teams"] as? [String: Any]
            let teamIds = (teamsOuter?["nodes"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
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

    // Response format: { "issues": { "nodes": [...], "pageInfo": {...} } }
    private func parseIssues(from raw: String) -> [LinearIssue] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let arr: [[String: Any]]
        if let outer = json["issues"] as? [String: Any],
           let nodes = outer["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = json["issues"] as? [[String: Any]] {
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
            let assigneeName = assigneeDict?["name"] as? String

            let labelsOuter = d["labels"] as? [String: Any]
            let labelsData  = (labelsOuter?["nodes"] as? [[String: Any]]) ?? []
            let labels      = labelsData.compactMap { $0["name"] as? String }

            // Due date (yyyy-MM-dd format in Linear)
            let dueDateStr = d["dueDate"] as? String
            let dueDate: Date? = dueDateStr.flatMap { str in
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                return df.date(from: str)
            }

            // Cycle
            let cycleDict = d["cycle"] as? [String: Any]
            let cycleName = cycleDict?["name"] as? String

            return LinearIssue(
                id:           id,
                identifier:   ident,
                title:        title,
                description:  (d["description"] as? String) ?? "",
                priority:     LinearPriority(int: (d["priority"] as? Int) ?? 0),
                state:        issueState,
                teamId:       (d["team"] as? [String: Any])?["id"] as? String ?? "",
                projectId:    (d["project"] as? [String: Any])?["id"] as? String,
                assigneeName: assigneeName,
                labels:       labels,
                createdAt:    (d["createdAt"] as? String).flatMap { iso.date(from: $0) },
                updatedAt:    (d["updatedAt"] as? String).flatMap { iso.date(from: $0) },
                dueDate:      dueDate,
                cycleName:    cycleName,
                url:          (d["url"] as? String) ?? ""
            )
        }
    }

    // Response format: { "teams": { "nodes": [...] } }
    private func parseTeams(from raw: String) -> [LinearTeam] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let arr: [[String: Any]]
        if let outer = json["teams"] as? [String: Any],
           let nodes = outer["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = json["teams"] as? [[String: Any]] {
            arr = direct
        } else {
            return []
        }

        return arr.compactMap { d in
            guard let id  = d["id"]   as? String,
                  let nam = d["name"] as? String else { return nil }
            var teamStates: [LinearIssueState] = []
            if let statesObj = d["states"] as? [String: Any],
               let stateNodes = statesObj["nodes"] as? [[String: Any]] {
                teamStates = stateNodes.compactMap { s in
                    guard let sid = s["id"] as? String else { return nil }
                    return LinearIssueState(
                        id: sid,
                        name: s["name"] as? String ?? "",
                        type: s["type"] as? String ?? "backlog",
                        color: s["color"] as? String ?? "#888888"
                    )
                }
            }
            return LinearTeam(id: id, name: nam, key: (d["key"] as? String) ?? "", states: teamStates)
        }
    }

    private func parseIssueStates(from raw: String) -> [LinearIssueState] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var arr: [[String: Any]] = []
        if let nodes = (json["workflowStates"] as? [String: Any])?["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let nodes = json["nodes"] as? [[String: Any]] {
            arr = nodes
        } else if let direct = json as? [String: Any], let id = direct["id"] as? String {
            arr = [["id": id, "name": direct["name"] ?? "", "type": direct["type"] ?? "", "color": direct["color"] ?? ""]]
        }
        return arr.compactMap { node -> LinearIssueState? in
            guard let id = node["id"] as? String else { return nil }
            return LinearIssueState(
                id: id,
                name: node["name"] as? String ?? "",
                type: node["type"] as? String ?? "backlog",
                color: node["color"] as? String ?? "#888888"
            )
        }
    }
}

enum LinearError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "Linear MCP nicht konfiguriert" }
}
