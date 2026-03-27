import SwiftUI

struct MCPView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var servers: [MCPServer] = []
    @State private var isLoading = false
    @State private var lastLoaded: Date?

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
            // Status icon
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
            Text("Server können mit `claude mcp add`\nkonfiguriert werden.")
                .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: "https://docs.anthropic.com/de/docs/claude-code/mcp") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("MCP Dokumentation", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

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
}
