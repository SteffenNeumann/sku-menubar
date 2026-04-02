import SwiftUI

// MARK: - Catalog data

struct MCPCatalogEntry: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: String
    let transport: String
    let command: String
    let args: [String]          // extra args after command
    let envVars: [String]       // placeholder strings like "API_KEY=YOUR_KEY"

    var needsConfig: Bool { !envVars.isEmpty }

    static func categoryIcon(_ category: String) -> String {
        switch category {
        case "Dev Tools":     return "wrench.and.screwdriver"
        case "Browser":       return "globe"
        case "Dateisystem":   return "folder"
        case "Datenbank":     return "cylinder"
        case "Produktivität": return "checkmark.circle"
        case "KI":            return "brain"
        default:              return "server.rack"
        }
    }

    static let all: [MCPCatalogEntry] = [
        // Dev Tools
        .init(name: "GitHub",
              description: "Repos, Issues und Pull Requests verwalten",
              category: "Dev Tools", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-github"],
              envVars: ["GITHUB_PERSONAL_ACCESS_TOKEN=YOUR_TOKEN"]),

        .init(name: "GitLab",
              description: "GitLab-Projekte, Issues und Merge Requests",
              category: "Dev Tools", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-gitlab"],
              envVars: ["GITLAB_PERSONAL_ACCESS_TOKEN=YOUR_TOKEN", "GITLAB_API_URL=https://gitlab.com"]),

        .init(name: "Sentry",
              description: "Fehler-Tracking und Error-Monitoring",
              category: "Dev Tools", transport: "stdio",
              command: "npx", args: ["-y", "@sentry/mcp-server@latest"],
              envVars: ["SENTRY_ACCESS_TOKEN=YOUR_TOKEN"]),

        .init(name: "Linear",
              description: "Issues und Projekte in Linear verwalten",
              category: "Dev Tools", transport: "stdio",
              command: "npx", args: ["-y", "@linear/mcp-server"],
              envVars: ["LINEAR_API_KEY=YOUR_KEY"]),

        // Browser
        .init(name: "Playwright",
              description: "Browser-Automatisierung und Web-Scraping",
              category: "Browser", transport: "stdio",
              command: "npx", args: ["-y", "@playwright/mcp@latest"],
              envVars: []),

        .init(name: "Puppeteer",
              description: "Headless Chrome / Web-Automatisierung",
              category: "Browser", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-puppeteer"],
              envVars: []),

        .init(name: "Fetch",
              description: "Webseiten und APIs direkt abrufen",
              category: "Browser", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-fetch"],
              envVars: []),

        .init(name: "Brave Search",
              description: "Websuche über die Brave Search API",
              category: "Browser", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-brave-search"],
              envVars: ["BRAVE_API_KEY=YOUR_KEY"]),

        // Dateisystem
        .init(name: "Filesystem",
              description: "Lokale Dateien und Verzeichnisse lesen/schreiben",
              category: "Dateisystem", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users"],
              envVars: []),

        .init(name: "Memory",
              description: "Persistenter Kontext über Sitzungen hinweg",
              category: "Dateisystem", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"],
              envVars: []),

        // Datenbank
        .init(name: "SQLite",
              description: "SQLite-Datenbanken lesen und abfragen",
              category: "Datenbank", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-sqlite"],
              envVars: []),

        .init(name: "PostgreSQL",
              description: "PostgreSQL-Datenbankzugriff",
              category: "Datenbank", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-postgres"],
              envVars: ["POSTGRES_URL=postgresql://localhost/mydb"]),

        // Produktivität
        .init(name: "Slack",
              description: "Nachrichten senden und Kanäle lesen",
              category: "Produktivität", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-slack"],
              envVars: ["SLACK_BOT_TOKEN=xoxb-YOUR_TOKEN", "SLACK_TEAM_ID=YOUR_TEAM_ID"]),

        .init(name: "Google Drive",
              description: "Dateien in Google Drive suchen und lesen",
              category: "Produktivität", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-gdrive"],
              envVars: []),

        .init(name: "Notion",
              description: "Notion-Seiten und Datenbanken lesen/schreiben",
              category: "Produktivität", transport: "stdio",
              command: "npx", args: ["-y", "@suekou/mcp-notion-server"],
              envVars: ["NOTION_API_TOKEN=YOUR_TOKEN"]),

        // KI
        .init(name: "Sequential Thinking",
              description: "Strukturiertes, schrittweises Denken",
              category: "KI", transport: "stdio",
              command: "npx", args: ["-y", "@modelcontextprotocol/server-sequential-thinking"],
              envVars: []),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}

// MARK: - Known AI Models

struct KnownModel: Identifiable {
    let id = UUID()
    let name: String
    let apiName: String
    let provider: String
    let contextK: Int?     // context window in K tokens, nil = unknown

    static func providerIcon(_ provider: String) -> String {
        switch provider {
        case "Anthropic":   return "brain"
        case "OpenAI":      return "sparkles"
        case "Google":      return "g.circle.fill"
        case "Meta":        return "person.2.fill"
        case "Mistral":     return "wind"
        case "xAI":         return "x.circle.fill"
        case "Cohere":      return "waveform"
        case "DeepSeek":    return "water.waves"
        case "Amazon":      return "cloud.fill"
        case "Perplexity":  return "magnifyingglass.circle.fill"
        default:            return "cpu"
        }
    }

    static let all: [KnownModel] = [
        // GitHub Copilot (via Claude CLI --model github/...)
        .init(name: "Claude Sonnet 4.5",        apiName: "github/claude-sonnet-4-5",        provider: "GitHub",    contextK: 200),
        .init(name: "Claude Opus 4",            apiName: "github/claude-opus-4-5",          provider: "GitHub",    contextK: 200),
        .init(name: "Claude 3.7 Sonnet",        apiName: "github/claude-3-7-sonnet",        provider: "GitHub",    contextK: 200),
        .init(name: "Claude 3.5 Sonnet",        apiName: "github/claude-3-5-sonnet",        provider: "GitHub",    contextK: 200),
        .init(name: "GPT-4.1",                  apiName: "github/gpt-4.1",                  provider: "GitHub",    contextK: 1000),
        .init(name: "GPT-4o",                   apiName: "github/gpt-4o",                   provider: "GitHub",    contextK: 128),
        .init(name: "o3",                       apiName: "github/o3",                       provider: "GitHub",    contextK: 200),
        // Anthropic
        .init(name: "Claude Opus 4",            apiName: "claude-opus-4-5",                provider: "Anthropic", contextK: 200),
        .init(name: "Claude Sonnet 4.5",        apiName: "claude-sonnet-4-5",              provider: "Anthropic", contextK: 200),
        .init(name: "Claude 3.7 Sonnet",        apiName: "claude-3-7-sonnet-20250219",     provider: "Anthropic", contextK: 200),
        .init(name: "Claude 3.5 Sonnet",        apiName: "claude-3-5-sonnet-20241022",     provider: "Anthropic", contextK: 200),
        .init(name: "Claude 3.5 Haiku",         apiName: "claude-3-5-haiku-20241022",      provider: "Anthropic", contextK: 200),
        .init(name: "Claude 3 Opus",            apiName: "claude-3-opus-20240229",         provider: "Anthropic", contextK: 200),
        .init(name: "Claude 3 Haiku",           apiName: "claude-3-haiku-20240307",        provider: "Anthropic", contextK: 200),
        // OpenAI
        .init(name: "GPT-4.1",                  apiName: "gpt-4.1",                        provider: "OpenAI",    contextK: 1000),
        .init(name: "GPT-4.1 mini",             apiName: "gpt-4.1-mini",                   provider: "OpenAI",    contextK: 1000),
        .init(name: "GPT-4.1 nano",             apiName: "gpt-4.1-nano",                   provider: "OpenAI",    contextK: 1000),
        .init(name: "GPT-4o",                   apiName: "gpt-4o",                         provider: "OpenAI",    contextK: 128),
        .init(name: "GPT-4o mini",              apiName: "gpt-4o-mini",                    provider: "OpenAI",    contextK: 128),
        .init(name: "GPT-4 Turbo",              apiName: "gpt-4-turbo",                    provider: "OpenAI",    contextK: 128),
        .init(name: "o1",                       apiName: "o1",                             provider: "OpenAI",    contextK: 200),
        .init(name: "o1-mini",                  apiName: "o1-mini",                        provider: "OpenAI",    contextK: 128),
        .init(name: "o3",                       apiName: "o3",                             provider: "OpenAI",    contextK: 200),
        .init(name: "o3-mini",                  apiName: "o3-mini",                        provider: "OpenAI",    contextK: 200),
        .init(name: "o4-mini",                  apiName: "o4-mini",                        provider: "OpenAI",    contextK: 200),
        // Google
        .init(name: "Gemini 2.5 Pro",           apiName: "gemini-2.5-pro",                 provider: "Google",    contextK: 1000),
        .init(name: "Gemini 2.5 Flash",         apiName: "gemini-2.5-flash",               provider: "Google",    contextK: 1000),
        .init(name: "Gemini 2.0 Flash",         apiName: "gemini-2.0-flash",               provider: "Google",    contextK: 1000),
        .init(name: "Gemini 2.0 Flash Lite",    apiName: "gemini-2.0-flash-lite",          provider: "Google",    contextK: 1000),
        .init(name: "Gemini 1.5 Pro",           apiName: "gemini-1.5-pro",                 provider: "Google",    contextK: 2000),
        .init(name: "Gemini 1.5 Flash",         apiName: "gemini-1.5-flash",               provider: "Google",    contextK: 1000),
        // Meta
        .init(name: "Llama 4 Scout",            apiName: "meta-llama/llama-4-scout",                         provider: "Meta", contextK: 10000),
        .init(name: "Llama 4 Maverick",         apiName: "meta-llama/llama-4-maverick",                      provider: "Meta", contextK: 1000),
        .init(name: "Llama 3.3 70B",            apiName: "meta-llama/llama-3.3-70b-instruct",                provider: "Meta", contextK: 128),
        .init(name: "Llama 3.2 90B Vision",     apiName: "meta-llama/llama-3.2-90b-vision-instruct",         provider: "Meta", contextK: 128),
        .init(name: "Llama 3.1 405B",           apiName: "meta-llama/llama-3.1-405b-instruct",               provider: "Meta", contextK: 128),
        // Mistral
        .init(name: "Mistral Large 2",          apiName: "mistral-large-2411",             provider: "Mistral",   contextK: 128),
        .init(name: "Mistral Small 3.1",        apiName: "mistral-small-2503",             provider: "Mistral",   contextK: 128),
        .init(name: "Mistral Large",            apiName: "mistral-large-latest",           provider: "Mistral",   contextK: 128),
        .init(name: "Mistral Small",            apiName: "mistral-small-latest",           provider: "Mistral",   contextK: 32),
        .init(name: "Codestral",                apiName: "codestral-latest",               provider: "Mistral",   contextK: 256),
        .init(name: "Mixtral 8x22B",            apiName: "open-mixtral-8x22b",             provider: "Mistral",   contextK: 64),
        // xAI
        .init(name: "Grok 3",                   apiName: "grok-3",                         provider: "xAI",       contextK: 131),
        .init(name: "Grok 3 mini",              apiName: "grok-3-mini",                    provider: "xAI",       contextK: 131),
        .init(name: "Grok 2",                   apiName: "grok-2-latest",                  provider: "xAI",       contextK: 131),
        .init(name: "Grok Vision Beta",         apiName: "grok-vision-beta",               provider: "xAI",       contextK: 8),
        // Cohere
        .init(name: "Command R+",               apiName: "command-r-plus",                 provider: "Cohere",    contextK: 128),
        .init(name: "Command R",                apiName: "command-r",                      provider: "Cohere",    contextK: 128),
        .init(name: "Command R 08-2024",        apiName: "command-r-08-2024",              provider: "Cohere",    contextK: 128),
        // DeepSeek
        .init(name: "DeepSeek V3",              apiName: "deepseek-chat",                  provider: "DeepSeek",  contextK: 64),
        .init(name: "DeepSeek R1",              apiName: "deepseek-reasoner",              provider: "DeepSeek",  contextK: 64),
        // Amazon
        .init(name: "Nova Pro",                 apiName: "amazon.nova-pro-v1:0",           provider: "Amazon",    contextK: 300),
        .init(name: "Nova Lite",                apiName: "amazon.nova-lite-v1:0",          provider: "Amazon",    contextK: 300),
        .init(name: "Titan Text G1 Express",    apiName: "amazon.titan-text-express-v1",   provider: "Amazon",    contextK: 8),
        // Perplexity
        .init(name: "Sonar Large",              apiName: "llama-3.1-sonar-large-128k-online", provider: "Perplexity", contextK: 128),
        .init(name: "Sonar Small",              apiName: "llama-3.1-sonar-small-128k-online", provider: "Perplexity", contextK: 128),
        .init(name: "Sonar Pro",                apiName: "sonar-pro",                      provider: "Perplexity", contextK: 200),
    ]

    static var providers: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.provider).inserted ? $0.provider : nil }
    }
}

// MARK: - MCP Log Entry

struct MCPLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let node: String
    let event: String
    let status: MCPLogStatus
    let duration: String

    enum MCPLogStatus {
        case success, error, retriable, pending

        var label: String {
            switch self {
            case .success:   return "SUCCESS"
            case .error:     return "ERROR"
            case .retriable: return "RETRIABLE"
            case .pending:   return "PENDING"
            }
        }
        var color: Color {
            switch self {
            case .success:   return .green
            case .error:     return .red
            case .retriable: return .orange
            case .pending:   return .yellow
            }
        }
    }
}

// MARK: - MCPView

struct MCPView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var servers: [MCPServer] = []
    @State private var isLoading = false
    @State private var lastLoaded: Date?
    @State private var showAddSheet = false
    @State private var editingServer: MCPServer?
    @State private var removingId: String?
    @State private var logs: [MCPLogEntry] = []
    @State private var showAllLogs = false
    @State private var expandedLogId: UUID?

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    // Derived counts
    private var connectedCount: Int { servers.filter { $0.status == .connected }.count }
    private var authCount: Int { servers.filter { if case .needsAuth = $0.status { return true }; return false }.count }
    private var errorCount: Int { servers.filter { if case .error = $0.status { return true }; return false }.count }
    private var offlineCount: Int { servers.filter { if case .unknown = $0.status { return true }; return false }.count }

    private var uptimePercent: Double {
        guard !servers.isEmpty else { return 0 }
        return Double(connectedCount) / Double(servers.count) * 100
    }

    var body: some View {
        VStack(spacing: 0) {
            commandCenterHeader
            Divider().foregroundStyle(theme.cardBorder)

            if isLoading && servers.isEmpty {
                Spacer()
                ProgressView("MCP Server werden abgefragt…")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            } else if servers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    HStack {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 20) {
                            statusDashboard

                            // Section header
                            Text("Server")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(theme.primaryText)
                                .padding(.bottom, -8)

                            serverGrid
                            systemLogsSection
                        }
                        .frame(maxWidth: 900)
                        .padding(20)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet(editingServer: nil) { await load() }
                .environmentObject(state)
                .environment(\.appTheme, theme)
        }
        .sheet(item: $editingServer) { server in
            AddMCPServerSheet(editingServer: server) { await load() }
                .environmentObject(state)
                .environment(\.appTheme, theme)
        }
    }

    // MARK: - Header

    private var commandCenterHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("my MCP's")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Orchestrate your Model Context Protocol server nodes")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await load() }
                } label: {
                    HStack(spacing: 5) {
                        if isLoading { ProgressView().scaleEffect(0.55).frame(width: 12, height: 12) }
                        else { Image(systemName: "arrow.2.circlepath").font(.system(size: 10)) }
                        Text("Aktualisieren").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 11))
                        Text("Hinzufügen").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    // MARK: - Status Dashboard

    private var statusDashboard: some View {
        HStack(spacing: 12) {
            statusMetricCard(
                icon: "antenna.radiowaves.left.and.right",
                iconColor: .green,
                showLive: true,
                header: "ACTIVE STATUS",
                value: String(format: "%02d", connectedCount),
                valueLabel: "Nodes",
                valueColor: .green,
                footnote: connectedCount > 0 ? "All critical systems nominal" : "No active nodes"
            )
            statusMetricCard(
                icon: "lock.fill",
                iconColor: Color(red: 0.2, green: 0.7, blue: 1.0),
                showLive: false,
                header: "ATTENTION REQUIRED",
                value: String(format: "%02d", authCount),
                valueLabel: "Auth",
                valueColor: Color(red: 0.2, green: 0.7, blue: 1.0),
                footnote: authCount > 0 ? "Token expiration in 48 hours" : "No auth issues"
            )
            statusMetricCard(
                icon: "exclamationmark.triangle.fill",
                iconColor: Color(red: 1.0, green: 0.35, blue: 0.3),
                showLive: false,
                header: "HEALTH ISSUES",
                value: String(format: "%02d", errorCount + offlineCount),
                valueLabel: "Alert",
                valueColor: Color(red: 1.0, green: 0.35, blue: 0.3),
                footnote: errorCount > 0 ? "Latency spike detected" : "No health alerts"
            )
        }
    }

    private func statusMetricCard(icon: String, iconColor: Color, showLive: Bool,
                                   header: String, value: String, valueLabel: String,
                                   valueColor: Color, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(iconColor)
                }
                Spacer()
                if showLive {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .tracking(1)
                    }
                }
            }
            Text(header)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                Text(valueLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(valueColor)
            }
            Text(footnote)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .mirrorCard()
    }

    // MARK: - Server Grid (2 columns)

    private var serverGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(servers) { server in
                serverNodeCard(server)
            }
            connectNodePlaceholder
        }
    }

    private func serverNodeCard(_ server: MCPServer) -> some View {
        let statusText  = healthStatusText(for: server)
        let statusColor = healthStatusColor(for: server)
        return VStack(alignment: .leading, spacing: 12) {
            // Name + status badge — badge floats top-right
            HStack(alignment: .center, spacing: 6) {
                Text(server.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                runningBadge(server.status)
            }

            // Endpoint section
            VStack(alignment: .leading, spacing: 3) {
                Text("ENDPOINT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                    .tracking(1)
                Text(serverEndpoint(for: server))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.windowBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            }

            Spacer(minLength: 0)

            // Bottom row: health status + action buttons
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health Status")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                        .tracking(0.5)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // Action buttons with 8px gap
                HStack(spacing: 8) {
                // Edit (gear)
                Button {
                    editingServer = server
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(removingId != nil)
                .help("Server bearbeiten")

                // Delete
                Button {
                    Task { await removeServer(server) }
                } label: {
                    if removingId == server.id {
                        ProgressView().scaleEffect(0.5).frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 26, height: 26)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(removingId != nil)
                .help("Server entfernen")
                } // end HStack buttons
            }
        }
        .padding(16)
        .frame(minHeight: 140)
        .mirrorCard()
    }

    private func runningBadge(_ status: MCPStatus) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch status {
            case .connected:  return ("CONNECTED",     Color(red: 0.13, green: 0.65, blue: 0.30), .white)
            case .needsAuth:  return ("AUTH REQUIRED", Color(red: 0.85, green: 0.48, blue: 0.10), .white)
            case .error:      return ("OFFLINE",       Color(red: 0.80, green: 0.18, blue: 0.18), .white)
            case .unknown:    return ("PENDING",       Color(red: 0.40, green: 0.40, blue: 0.45), .white)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(fg)
            .tracking(0.4)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private func serverLatency(for server: MCPServer) -> String {
        let hash = abs(server.name.hashValue)
        switch server.status {
        case .connected:  return "\(80 + hash % 400)ms"
        case .needsAuth:  return "\(200 + hash % 600)ms"
        case .error:      return "840ms"
        case .unknown:    return "—"
        }
    }

    private func serverMemory(for server: MCPServer) -> String {
        let hash = abs(server.name.hashValue)
        switch server.status {
        case .connected:  return "\(64 + hash % 256)MB"
        case .needsAuth:  return "\(128 + hash % 128)MB"
        case .error:      return "1.2GB"
        case .unknown:    return "—"
        }
    }

    private func latencyColor(_ status: MCPStatus) -> Color {
        switch status {
        case .connected:  return theme.secondaryText
        case .needsAuth:  return .orange
        case .error:      return Color(red: 1.0, green: 0.35, blue: 0.3)
        case .unknown:    return theme.tertiaryText
        }
    }

    private func healthStatusText(for server: MCPServer) -> String {
        let hash = abs(server.name.hashValue)
        switch server.status {
        case .connected:  return "Last seen \(1 + hash % 5)m ago"
        case .needsAuth:  return "Waiting for token..."
        case .error:      return "Path not accessible"
        case .unknown:    return "Connecting..."
        }
    }

    private func healthStatusColor(for server: MCPServer) -> Color {
        switch server.status {
        case .connected:  return Color(red: 0.13, green: 0.65, blue: 0.30)
        case .needsAuth:  return .orange
        case .error:      return Color(red: 1.0, green: 0.35, blue: 0.3)
        case .unknown:    return theme.tertiaryText
        }
    }

    private var connectNodePlaceholder: some View {
        Button {
            showAddSheet = true
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(theme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                Text("Connect Node")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Text("Add a custom MCP endpoint")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(theme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server Helpers

    private func serverEndpoint(for server: MCPServer) -> String {
        let n = server.name.lowercased()
        if server.type == "http" || server.type == "sse" {
            return server.detail.isEmpty ? "https://\(server.name.lowercased()).endpoint" : server.detail
        }
        if n.contains("github")     { return "github.mcp.io/v3/au..." }
        if n.contains("slack")      { return "https://hooks.slack..." }
        if n.contains("notion")     { return "api.notion.com/v1/m..." }
        if n.contains("postgres")   { return "localhost:5432/mcp_..." }
        if n.contains("filesystem") { return "/Users/admin/projec..." }
        if n.contains("linear")     { return "https://api.linear...." }
        return "\(server.type)://\(server.name.lowercased())"
    }

    // MARK: - System Logs Section

    private var systemLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent System Logs")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button {
                    showAllLogs.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(showAllLogs ? "Collapse" : "View full audit log")
                            .font(.system(size: 12))
                        Image(systemName: showAllLogs ? "chevron.up" : "arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                logTable(showAllLogs ? logs : Array(logs.prefix(4)))
            }
            .frame(maxHeight: showAllLogs ? 400 : 200)
        }
    }

    private func logTable(_ entries: [MCPLogEntry]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("TIMESTAMP").frame(width: 90, alignment: .leading)
                Text("ORIGIN").frame(width: 140, alignment: .leading)
                Text("EVENT").frame(maxWidth: .infinity, alignment: .leading)
                Text("STATUS").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(theme.tertiaryText)
            .tracking(0.8)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(theme.windowBg.opacity(0.4))

            Divider().foregroundStyle(theme.cardBorder)

            ForEach(entries) { entry in
                let isExpanded = expandedLogId == entry.id

                // Main row
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedLogId = isExpanded ? nil : entry.id
                    }
                } label: {
                    HStack(spacing: 0) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .frame(width: 90, alignment: .leading)
                            .foregroundStyle(theme.tertiaryText)
                        Text(entry.node)
                            .fontWeight(.semibold)
                            .frame(width: 140, alignment: .leading)
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(entry.event)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(entry.status == .error
                                ? Color(red: 1.0, green: 0.35, blue: 0.3)
                                : theme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        logStatusBadge(entry.status)
                            .frame(width: 70, alignment: .trailing)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.tertiaryText)
                            .frame(width: 20, alignment: .trailing)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(isExpanded ? theme.windowBg.opacity(0.5) : Color.clear)
                }
                .buttonStyle(.plain)

                // Expanded detail panel
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 24) {
                            logDetailCell(label: "NODE",      value: entry.node)
                            logDetailCell(label: "DATE",      value: entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                            logDetailCell(label: "TIME",      value: entry.timestamp.formatted(date: .omitted, time: .standard))
                            logDetailCell(label: "STATUS",    value: entry.status.label)
                            Spacer()
                        }
                        logDetailCell(label: "EVENT DETAIL", value: entry.event)
                        if !entry.duration.isEmpty {
                            logDetailCell(label: "DURATION",  value: entry.duration)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accentColor.opacity(0.05))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().foregroundStyle(theme.cardBorder.opacity(0.4))
            }
        }
        .mirrorCard()
    }

    private func logDetailCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func logStatusBadge(_ status: MCPLogEntry.MCPLogStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .success:   return ("OK", .green)
            case .error:     return ("ERROR", Color(red: 1.0, green: 0.35, blue: 0.3))
            case .retriable: return ("WARN", .orange)
            case .pending:   return ("INFO", Color(red: 0.2, green: 0.7, blue: 1.0))
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.3), lineWidth: 0.5))
    }

    // Generate mock logs from real server states
    private func generateLogs() -> [MCPLogEntry] {
        let now = Date()
        let events: [(MCPStatus) -> (String, MCPLogEntry.MCPLogStatus)] = [
            { s in
                switch s {
                case .connected:  return ("Handshake successful with upstream API", .success)
                case .needsAuth:  return ("Token refreshed for administrator", .success)
                case .error:      return ("Latency threshold exceeded (840ms > 200ms)", .error)
                case .unknown:    return ("Memory optimization daemon initiated", .pending)
                }
            }
        ]
        return servers.enumerated().compactMap { index, server in
            let offset = TimeInterval(-index * 97 - 23)
            let ts = now.addingTimeInterval(offset)
            let (event, status) = events[0](server.status)
            return MCPLogEntry(timestamp: ts, node: server.name, event: event, status: status, duration: "")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(theme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: 60, height: 60)
                Image(systemName: "server.rack")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.tertiaryText)
            }
            Text("No nodes deployed yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text("Deploy your first MCP server to start orchestrating.")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 11))
                    Text("Deploy First Node").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        servers = await state.cliService.listMCPServers()
        if servers.isEmpty {
            servers = await state.mcpService.servers.isEmpty
                ? { await state.mcpService.load(); return state.mcpService.servers }()
                : state.mcpService.servers
        }
        lastLoaded = .now
        // Refresh logs
        logs = generateLogs()
    }

    private func removeServer(_ server: MCPServer) async {
        removingId = server.id
        defer { removingId = nil }
        let (_, _) = await state.cliService.removeMCPServer(name: server.name)
        await load()
    }
}

// MARK: - Add MCP Server Sheet

private enum AddMCPMode { case catalog, manual }

struct AddMCPServerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appTheme) var theme
    @EnvironmentObject var state: AppState

    var editingServer: MCPServer?
    var onDone: () async -> Void

    private var isEditing: Bool { editingServer != nil }

    @State private var mode: AddMCPMode = .catalog
    @State private var selectedCategory: String = "Alle"
    @State private var catalogSearch: String = ""

    // Manual form fields
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var commandOrUrl = ""
    @State private var extraArgs = ""
    @State private var headersText = ""
    @State private var envVarsText = ""
    @State private var isAdding = false
    @State private var isFetchingConfig = false
    @State private var errorMsg: String?
    @State private var catalogSourceName: String?   // banner: "Aus Katalog: X"

    // Model picker
    @State private var selectedModel: String = ""
    @State private var showModelPicker = false
    @State private var modelSearch = ""
    @State private var modelProvider = "Alle"

    // AI Assistance
    @State private var aiPrompt = ""
    @State private var isAIAssisting = false
    @State private var aiError: String?

    private let transports = ["stdio", "http", "sse"]

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commandOrUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredEntries: [MCPCatalogEntry] {
        MCPCatalogEntry.all.filter { entry in
            let matchesCat = selectedCategory == "Alle" || entry.category == selectedCategory
            let matchesSearch = catalogSearch.isEmpty ||
                entry.name.localizedCaseInsensitiveContains(catalogSearch) ||
                entry.description.localizedCaseInsensitiveContains(catalogSearch) ||
                entry.category.localizedCaseInsensitiveContains(catalogSearch)
            return matchesCat && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().foregroundStyle(theme.cardBorder)
            if !isEditing { modePicker; Divider().foregroundStyle(theme.cardBorder) }

            if mode == .catalog && !isEditing {
                catalogView
            } else if isFetchingConfig {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Konfiguration wird geladen…")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                manualForm
            }

            Divider().foregroundStyle(theme.cardBorder)
            actionBar
        }
        .frame(width: 700)
        .background(theme.windowBg)
        .task {
            if let server = editingServer {
                await loadExistingConfig(for: server)
            }
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text(isEditing ? "MCP Server bearbeiten" : "MCP Server hinzufügen")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeTab(label: "Katalog", icon: "square.grid.2x2", tab: .catalog)
            modeTab(label: "Manuell", icon: "pencil", tab: .manual)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func modeTab(label: String, icon: String, tab: AddMCPMode) -> some View {
        let active = mode == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { mode = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? accentColor : theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalog view

    private var catalogView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Server suchen…", text: $catalogSearch)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                if !catalogSearch.isEmpty {
                    Button { catalogSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Category filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip("Alle")
                    ForEach(MCPCatalogEntry.categories, id: \.self) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Keine Server gefunden")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    } else {
                        ForEach(filteredEntries) { entry in
                            catalogCard(entry)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 768)
        }
    }

    private func categoryChip(_ category: String) -> some View {
        let active = selectedCategory == category
        let icon = category == "Alle" ? "square.grid.2x2" : MCPCatalogEntry.categoryIcon(category)
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(category).font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? accentColor : theme.secondaryText)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(active ? accentColor.opacity(0.10) : theme.cardBg, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? accentColor.opacity(0.3) : theme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func catalogCard(_ entry: MCPCatalogEntry) -> some View {
        Button {
            applyEntry(entry)
        } label: {
            HStack(spacing: 12) {
                // Category icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: MCPCatalogEntry.categoryIcon(entry.category))
                        .font(.system(size: 13))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text(entry.category)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(theme.primaryText.opacity(0.06), in: Capsule())
                        Spacer()
                        if entry.needsConfig {
                            HStack(spacing: 3) {
                                Image(systemName: "key.fill").font(.system(size: 8))
                                Text("API-Key").font(.system(size: 9))
                            }
                            .foregroundStyle(.orange.opacity(0.8))
                        }
                    }
                    Text(entry.description)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func applyEntry(_ entry: MCPCatalogEntry) {
        name          = entry.name.lowercased().replacingOccurrences(of: " ", with: "-")
        transport     = entry.transport
        commandOrUrl  = entry.command
        extraArgs     = entry.args.joined(separator: " ")
        envVarsText   = entry.envVars.joined(separator: "\n")
        headersText   = ""
        catalogSourceName = entry.name
        errorMsg      = nil
        withAnimation(.easeInOut(duration: 0.15)) { mode = .manual }
    }

    // MARK: - Manual form

    private var manualForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Catalog source banner
                if let src = catalogSourceName {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accentColor)
                        Text("Aus Katalog: \(src) — Felder anpassen und hinzufügen")
                            .font(.system(size: 11))
                            .foregroundStyle(accentColor)
                        Spacer()
                        Button {
                            catalogSourceName = nil
                            name = ""; commandOrUrl = ""; extraArgs = ""; envVarsText = ""; headersText = ""
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accentColor.opacity(0.2), lineWidth: 0.5))
                }

                // Name
                field(label: "Name", hint: "z.B. sentry") {
                    styledTextField("mein-server", text: $name)
                }

                // Transport
                field(label: "Transport", hint: nil) {
                    HStack(spacing: 6) {
                        ForEach(transports, id: \.self) { t in
                            Button {
                                transport = t
                            } label: {
                                Text(t)
                                    .font(.system(size: 11, weight: transport == t ? .semibold : .regular))
                                    .foregroundStyle(transport == t ? accentColor : theme.secondaryText)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(
                                        transport == t ? accentColor.opacity(0.12) : theme.cardBg,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(transport == t ? accentColor.opacity(0.3) : theme.cardBorder, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                // Command / URL
                field(
                    label: transport == "stdio" ? "Befehl" : "URL",
                    hint: transport == "stdio" ? "z.B. npx" : "https://mcp.example.com/mcp"
                ) {
                    styledTextField(transport == "stdio" ? "npx" : "https://...", text: $commandOrUrl)
                }

                // Extra args (stdio only)
                if transport == "stdio" {
                    field(label: "Argumente (optional)", hint: "Leerzeichen-getrennt") {
                        styledTextField("-y @my-mcp-server", text: $extraArgs)
                    }
                }

                // Headers (http/sse)
                if transport != "stdio" {
                    field(label: "Headers (optional)", hint: "Eine pro Zeile: Authorization: Bearer xxx") {
                        styledTextEditor(text: $headersText, minHeight: 54)
                    }
                }

                // Env vars (stdio)
                if transport == "stdio" {
                    field(label: "Umgebungsvariablen (optional)", hint: "Eine pro Zeile: API_KEY=xxx") {
                        styledTextEditor(text: $envVarsText, minHeight: 54)
                    }
                }

                // Model selection
                field(label: "Modell (optional)", hint: "Vorausgefülltes Modell für diesen Server") {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            ZStack(alignment: .leading) {
                                if selectedModel.isEmpty {
                                    Text("Modell wählen oder eingeben…")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                }
                                TextField("", text: $selectedModel)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(theme.primaryText)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                            }
                            .frame(maxWidth: .infinity)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))

                            Button {
                                modelSearch = ""; modelProvider = "Alle"
                                showModelPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "cpu").font(.system(size: 10))
                                    Text("Auswählen").font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                                ModelPickerPopover(
                                    search: $modelSearch,
                                    provider: $modelProvider,
                                    onSelect: { model in
                                        selectedModel = model.apiName
                                        showModelPicker = false
                                    }
                                )
                                .environmentObject(state)
                                .environment(\.appTheme, theme)
                            }

                            if !selectedModel.isEmpty {
                                Button {
                                    selectedModel = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // HowTo hint
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Modell nicht gefunden? Den API-Namen direkt ins Feld tippen, z. B. ")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                            Text("my-provider/model-name")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }

                if let err = errorMsg {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                // How To section
                howToSection

                // AI Assistance
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(accentColor)
                        Text("AI Assistance")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    Text("Describe what you need in plain language and let AI fill in the form fields.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)

                    styledTextEditor(text: $aiPrompt, minHeight: 52)
                        .overlay(
                            Group {
                                if aiPrompt.isEmpty {
                                    Text("e.g. Help me configure this for PostgreSQL on port 5433")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.tertiaryText)
                                        .padding(10)
                                        .allowsHitTesting(false)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        )

                    HStack(spacing: 8) {
                        if let err = aiError {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            Task { await runAIAssist() }
                        } label: {
                            HStack(spacing: 4) {
                                if isAIAssisting {
                                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "sparkles").font(.system(size: 10))
                                }
                                Text("Ask AI").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAIAssisting ? theme.tertiaryText : accentColor,
                                        in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAIAssisting)
                    }
                }
                .padding(12)
                .background(accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accentColor.opacity(0.15), lineWidth: 0.5))
            }
            .padding(16)
        }
        .frame(maxHeight: 1008)
    }

    // MARK: - How To section

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(accentColor)
                Text("How to edit an MCP Server")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            Divider().foregroundStyle(theme.cardBorder)

            VStack(alignment: .leading, spacing: 16) {
                howToRow(
                    icon: "tag",
                    title: "Name",
                    detail: "A unique, lowercase identifier with no spaces. Claude CLI uses this name to reference the server in all commands and config files.",
                    example: "my-server  /  github-tools  /  postgres-dev"
                )
                howToRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Transport",
                    detail: "Defines how Claude communicates with the server. Use stdio for local processes launched as a child process. Use http or sse for remote servers reachable via a URL — http is stateless REST, sse keeps a persistent event stream open.",
                    example: "stdio  →  local  |  http / sse  →  remote"
                )
                howToRow(
                    icon: "terminal",
                    title: "Command / URL",
                    detail: "For stdio: the executable that starts the server (Claude will launch it). For http/sse: the full base URL of the running MCP endpoint. Must be reachable from this machine.",
                    example: "npx  /  uvx  /  python  /  https://mcp.example.com/mcp"
                )
                howToRow(
                    icon: "list.bullet",
                    title: "Arguments",
                    detail: "Space-separated arguments passed after the command when stdio launches the process. Typically used to specify the npm package or script path. Each token becomes one CLI argument.",
                    example: "-y @modelcontextprotocol/server-github  /  -y @linear/mcp-server"
                )
                howToRow(
                    icon: "key",
                    title: "Env Vars",
                    detail: "Environment variables injected into the server process at launch (stdio only). One KEY=VALUE per line. Use this for API tokens, secrets, and configuration — never hard-code secrets in the command or args fields.",
                    example: "GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxx\nLINEAR_API_KEY=lin_api_xxx"
                )
                howToRow(
                    icon: "cpu",
                    title: "Model (optional)",
                    detail: "Optionally pre-select a specific AI model for this server's context. If set, this model will be used when this MCP server is active. Leave blank to inherit the globally configured default model.",
                    example: "claude-sonnet-4-5  /  github/gpt-4o  /  gemini-2.5-pro"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.windowBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    private func howToRow(icon: String, title: String, detail: String, example: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accentColor)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                Text(example)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(accentColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Abbrechen") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)

            if mode == .catalog && !isEditing {
                Button {
                    catalogSourceName = nil
                    withAnimation(.easeInOut(duration: 0.15)) { mode = .manual }
                } label: {
                    Text("Manuell eingeben")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accentColor.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await addServer() }
                } label: {
                    HStack(spacing: 5) {
                        if isAdding { ProgressView().scaleEffect(0.6).frame(width: 12, height: 12) }
                        Text(isEditing ? "Speichern" : "Hinzufügen")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(canAdd ? accentColor : theme.tertiaryText, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd || isAdding)
            }
        }
        .padding(14)
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func field<Content: View>(label: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                if let h = hint {
                    Text("· \(h)")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            content()
        }
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.primaryText)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    private func styledTextEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.primaryText)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .frame(minHeight: minHeight)
            .padding(6)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Load existing config (edit mode)

    private func loadExistingConfig(for server: MCPServer) async {
        isFetchingConfig = true
        mode = .manual
        name = server.name
        transport = server.type == "unknown" ? "stdio" : server.type
        if let config = await state.cliService.getMCPServerConfig(name: server.name) {
            commandOrUrl = config.commandOrUrl
            extraArgs    = config.args.joined(separator: " ")
            headersText  = config.headers.joined(separator: "\n")
            envVarsText  = config.envVars.joined(separator: "\n")
        } else {
            // Fallback: populate from what we know in the server list
            commandOrUrl = server.detail
        }
        isFetchingConfig = false
    }

    // MARK: - AI Assist

    private func runAIAssist() async {
        isAIAssisting = true
        aiError = nil
        defer { isAIAssisting = false }

        let userRequest = aiPrompt.trimmingCharacters(in: .whitespaces)
        let systemHint = name.isEmpty ? "" : " The server name is \"\(name)\"."
        let prompt = "\(userRequest).\(systemHint) Output ONLY a valid JSON object with these keys: name (string), transport (\"stdio\"|\"http\"|\"sse\"), commandOrUrl (string), args (array of strings), envVars (array of KEY=VALUE strings). No explanation, no markdown, just raw JSON."

        do {
            let output = try await state.cliService.runCommand(["claude", "-p", prompt])
            // Strip markdown code fences if present
            let cleaned = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^```\\s*",     with: "", options: .regularExpression)
                .replacingOccurrences(of: "```$",         with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                aiError = "Could not parse AI response."
                return
            }

            if let n = json["name"] as? String,    !n.isEmpty  { name = n }
            if let t = json["transport"] as? String             { transport = t }
            if let c = json["commandOrUrl"] as? String          { commandOrUrl = c }
            if let a = json["args"] as? [String]                { extraArgs = a.joined(separator: " ") }
            if let e = json["envVars"] as? [String]             { envVarsText = e.joined(separator: "\n") }
        } catch {
            aiError = error.localizedDescription
        }
    }

    // MARK: - Add / Save server

    private func addServer() async {
        isAdding = true
        errorMsg = nil
        defer { isAdding = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCmd  = commandOrUrl.trimmingCharacters(in: .whitespaces)
        let argList     = extraArgs.split(separator: " ").map(String.init)
        let headers     = headersText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var envVars     = envVarsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Modell als Env-Var einfügen, wenn gesetzt und nicht bereits vorhanden
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespaces)
        if !trimmedModel.isEmpty {
            let modelKey = "MODEL"
            let alreadySet = envVars.contains { $0.hasPrefix("\(modelKey)=") || $0.hasPrefix("CLAUDE_MODEL=") || $0.hasPrefix("OPENAI_MODEL=") }
            if !alreadySet {
                envVars.insert("\(modelKey)=\(trimmedModel)", at: 0)
            }
        }

        // In edit mode: remove the old server first (even if name changed)
        if let existing = editingServer {
            _ = await state.cliService.removeMCPServer(name: existing.name)
        }

        let (ok, output) = await state.cliService.addMCPServer(
            name: trimmedName,
            transport: transport,
            commandOrUrl: trimmedCmd,
            args: argList,
            headers: headers,
            envVars: envVars
        )

        if ok {
            await onDone()
            dismiss()
        } else {
            errorMsg = output.isEmpty ? "Unbekannter Fehler" : output
        }
    }
}

// MARK: - Model Picker Popover

private struct ModelPickerPopover: View {
    @Environment(\.appTheme) var theme
    @EnvironmentObject var state: AppState
    @Binding var search: String
    @Binding var provider: String
    var onSelect: (KnownModel) -> Void

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var filtered: [KnownModel] {
        KnownModel.all.filter { m in
            let matchProv = provider == "Alle" || m.provider == provider
            let matchSearch = search.isEmpty ||
                m.name.localizedCaseInsensitiveContains(search) ||
                m.apiName.localizedCaseInsensitiveContains(search) ||
                m.provider.localizedCaseInsensitiveContains(search)
            return matchProv && matchSearch
        }
    }

    // Group by provider while keeping order
    private var grouped: [(provider: String, models: [KnownModel])] {
        var result: [(provider: String, models: [KnownModel])] = []
        var seen = Set<String>()
        for m in filtered {
            if !seen.contains(m.provider) {
                seen.insert(m.provider)
                result.append((provider: m.provider, models: filtered.filter { $0.provider == m.provider }))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
                Text("Modell auswählen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(filtered.count) Modelle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().foregroundStyle(theme.cardBorder)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Modell suchen…", text: $search)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Provider filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    providerChip("Alle")
                    ForEach(KnownModel.providers, id: \.self) { p in
                        providerChip(p)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider().foregroundStyle(theme.cardBorder)

            // Model list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Kein Modell gefunden")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(grouped, id: \.provider) { group in
                            // Provider section header
                            HStack(spacing: 5) {
                                Image(systemName: KnownModel.providerIcon(group.provider))
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.tertiaryText)
                                Text(group.provider)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.tertiaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 3)

                            ForEach(group.models) { model in
                                modelRow(model)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 320)
        .background(theme.windowBg)
    }

    private func providerChip(_ p: String) -> some View {
        let active = provider == p
        let icon = p == "Alle" ? "square.grid.2x2" : KnownModel.providerIcon(p)
        return Button { provider = p } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8))
                Text(p).font(.system(size: 10, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? accentColor : theme.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(active ? accentColor.opacity(0.10) : theme.cardBg, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? accentColor.opacity(0.3) : theme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func modelRow(_ model: KnownModel) -> some View {
        Button { onSelect(model) } label: {
            HStack(spacing: 10) {
                Image(systemName: KnownModel.providerIcon(model.provider))
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor.opacity(0.7))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Text(model.apiName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                if let k = model.contextK {
                    Text("\(k)K")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(theme.primaryText.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }
}
