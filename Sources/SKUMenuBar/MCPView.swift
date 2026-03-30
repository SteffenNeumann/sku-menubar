import SwiftUI

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

            // Remove button
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

struct AddMCPServerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appTheme) var theme
    @EnvironmentObject var state: AppState

    var onDone: () async -> Void

    @State private var name = ""
    @State private var transport = "stdio"
    @State private var commandOrUrl = ""
    @State private var extraArgs = ""       // space-separated
    @State private var headersText = ""     // one per line: "Key: Value"
    @State private var envVarsText = ""     // one per line: "KEY=VALUE"
    @State private var isAdding = false
    @State private var errorMsg: String?

    private let transports = ["stdio", "http", "sse"]

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commandOrUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
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

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

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
                                            transport == t
                                                ? accentColor.opacity(0.12)
                                                : theme.cardBg,
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
                        hint: transport == "stdio" ? "z.B. npx @sentry/mcp-server" : "https://mcp.example.com/mcp"
                    ) {
                        styledTextField(transport == "stdio" ? "npx my-mcp-server" : "https://...", text: $commandOrUrl)
                    }

                    // Extra args (stdio only)
                    if transport == "stdio" {
                        field(label: "Argumente (optional)", hint: "Leerzeichen-getrennt") {
                            styledTextField("--flag wert", text: $extraArgs)
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

            Divider().foregroundStyle(theme.cardBorder)

            // Actions
            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)

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
            .padding(14)
        }
        .frame(width: 420)
        .background(theme.windowBg)
    }

    // MARK: - Helpers

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
