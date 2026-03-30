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

// MARK: - MCPView

struct MCPView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var servers: [MCPServer] = []
    @State private var isLoading = false
    @State private var lastLoaded: Date?
    @State private var showAddSheet = false
    @State private var removingId: String?

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().foregroundStyle(theme.cardBorder)

            if isLoading {
                Spacer()
                ProgressView("MCP Server werden abgefragt…")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            } else if servers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        summaryRow
                        ForEach(servers) { server in
                            serverCard(server)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet { await load() }
                .environmentObject(state)
                .environment(\.appTheme, theme)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Server")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                if let t = lastLoaded {
                    Text("Zuletzt: \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                }
            }

            Spacer()

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    Text("Hinzufügen").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                Task { await load() }
            } label: {
                HStack(spacing: 4) {
                    if isLoading { ProgressView().scaleEffect(0.6).frame(width: 12, height: 12) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    Text("Aktualisieren").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(16)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryCard(
                count: servers.filter { $0.status == .connected }.count,
                label: "Verbunden", color: .green, icon: "checkmark.circle.fill"
            )
            summaryCard(
                count: servers.filter {
                    if case .needsAuth = $0.status { return true }; return false
                }.count,
                label: "Auth. nötig", color: .orange, icon: "lock.fill"
            )
            summaryCard(
                count: servers.filter {
                    if case .error = $0.status { return true }; return false
                }.count,
                label: "Fehler", color: .red, icon: "xmark.circle.fill"
            )
        }
    }

    private func summaryCard(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(label).font(.system(size: 10)).foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .mirrorCard()
    }

    // MARK: - Server card

    private func serverCard(_ server: MCPServer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(server.status.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: server.status.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(server.status.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    if server.type != "unknown" {
                        Text(server.type.uppercased())
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(theme.primaryText.opacity(0.06), in: Capsule())
                    }
                    Spacer()
                    statusBadge(server.status)
                }

                Text(server.detail.isEmpty ? server.status.label : server.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }

            Button {
                Task { await removeServer(server) }
            } label: {
                if removingId == server.id {
                    ProgressView().scaleEffect(0.55).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .disabled(removingId != nil)
            .help("Server entfernen")
        }
        .padding(14)
        .mirrorCard()
    }

    private func statusBadge(_ status: MCPStatus) -> some View {
        Text(status.label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "network.slash")
                .font(.system(size: 38)).foregroundStyle(theme.tertiaryText)
            Text("Keine MCP Server gefunden")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondaryText)
            Text("Füge deinen ersten Server hinzu.")
                .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Server hinzufügen", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5))
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

    var onDone: () async -> Void

    @State private var mode: AddMCPMode = .catalog
    @State private var selectedCategory: String = "Alle"

    // Manual form fields
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var commandOrUrl = ""
    @State private var extraArgs = ""
    @State private var headersText = ""
    @State private var envVarsText = ""
    @State private var isAdding = false
    @State private var errorMsg: String?
    @State private var catalogSourceName: String?   // banner: "Aus Katalog: X"

    private let transports = ["stdio", "http", "sse"]

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commandOrUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredEntries: [MCPCatalogEntry] {
        selectedCategory == "Alle"
            ? MCPCatalogEntry.all
            : MCPCatalogEntry.all.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().foregroundStyle(theme.cardBorder)
            modePicker
            Divider().foregroundStyle(theme.cardBorder)

            if mode == .catalog {
                catalogView
            } else {
                manualForm
            }

            Divider().foregroundStyle(theme.cardBorder)
            actionBar
        }
        .frame(width: 440)
        .background(theme.windowBg)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text("MCP Server hinzufügen")
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
                    ForEach(filteredEntries) { entry in
                        catalogCard(entry)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 320)
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

                if let err = errorMsg {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Abbrechen") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)

            if mode == .catalog {
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
                        Text("Hinzufügen")
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

    // MARK: - Add server

    private func addServer() async {
        isAdding = true
        errorMsg = nil
        defer { isAdding = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCmd  = commandOrUrl.trimmingCharacters(in: .whitespaces)
        let argList     = extraArgs.split(separator: " ").map(String.init)
        let headers     = headersText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let envVars     = envVarsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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
