import Foundation

@MainActor
final class MCPService: ObservableObject {

    @Published var servers: [MCPServer] = []
    @Published var isLoading: Bool = false

    private let cliService: ClaudeCLIService

    init(cliService: ClaudeCLIService) {
        self.cliService = cliService
    }

    // MARK: - Load MCP servers

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Primary: run `claude mcp list`
        let fresh = await cliService.listMCPServers()
        if !fresh.isEmpty {
            servers = fresh
            return
        }

        // Fallback: read auth-cache to infer known servers
        servers = loadFromAuthCache()
    }

    // MARK: - Auth cache fallback

    private func loadFromAuthCache() -> [MCPServer] {
        let home = NSHomeDirectory()
        let cacheFile = URL(fileURLWithPath: "\(home)/.claude/mcp-needs-auth-cache.json")
        guard let data = try? Data(contentsOf: cacheFile),
              let dict = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
        else { return [] }

        return dict.keys.sorted().map { name in
            MCPServer(id: name, name: name, type: "unknown", status: .needsAuth, detail: "Needs authentication")
        }
    }
}
