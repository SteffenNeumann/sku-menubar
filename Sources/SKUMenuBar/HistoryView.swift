import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var selectedProject: ProjectHistory?
    @State private var selectedSession: HistorySession?
    @State private var sessionMessages: [HistoryMessage] = []
    @State private var isLoadingMessages = false
    @State private var searchText = ""

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var filteredProjects: [ProjectHistory] {
        guard !searchText.isEmpty else { return state.historyService.projects }
        return state.historyService.projects.filter {
            $0.path.localizedCaseInsensitiveContains(searchText) ||
            $0.sessions.contains { $0.preview.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            projectList
                .frame(width: 220)

            Divider().foregroundStyle(theme.cardBorder)

            if let project = selectedProject {
                sessionList(for: project)
                    .frame(width: 260)
                Divider().foregroundStyle(theme.cardBorder)
            }

            if let session = selectedSession {
                sessionDetail(for: session)
            } else {
                placeholderDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.historyService.projects.isEmpty {
                await state.historyService.loadProjects()
            }
        }
        .onChange(of: state.historySelectedProjectId) {
            guard let id = state.historySelectedProjectId,
                  let project = state.historyService.projects.first(where: { $0.id == id }) else { return }
            selectedProject = project
            state.historySelectedProjectId = nil
        }
    }

    // MARK: - Project list

    private var projectList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                TextField("Suchen…", text: $searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(8)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .padding(10)

            Divider().foregroundStyle(theme.cardBorder)

            if state.historyService.isLoading {
                Spacer()
                ProgressView("Wird geladen…").font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            } else if filteredProjects.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "clock.badge.questionmark").font(.system(size: 28)).foregroundStyle(theme.tertiaryText)
                    Text("Keine Projekte gefunden").font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredProjects) { project in
                            projectRow(project)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func projectRow(_ project: ProjectHistory) -> some View {
        let isSelected = selectedProject?.id == project.id

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedProject = project
                selectedSession = nil
                sessionMessages = []
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? accentColor.opacity(0.2) : theme.primaryText.opacity(0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? accentColor : theme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text("\(project.sessions.count) Session\(project.sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }

                Spacer()

                // Session count badge
                Text("\(project.sessions.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(theme.primaryText.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? theme.accentBorder : .clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session list

    private func sessionList(for project: ProjectHistory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(project.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(project.sessions.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(10)

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(project.sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(8)
            }
        }
    }

    private func sessionRow(_ session: HistorySession) -> some View {
        let isSelected = selectedSession?.id == session.id

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedSession = session
            }
            Task { await loadMessages(for: session) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9)).foregroundStyle(theme.tertiaryText.opacity(0.5))
                }
                Text(session.preview.isEmpty ? "Leere Session" : session.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? theme.accentBorder : .clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session detail

    private func sessionDetail(for session: HistorySession) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(session.sessionId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()

                // Stats
                if !sessionMessages.isEmpty {
                    let totalIn  = sessionMessages.reduce(0) { $0 + $1.inputTokens }
                    let totalOut = sessionMessages.reduce(0) { $0 + $1.outputTokens }
                    HStack(spacing: 10) {
                        statBadge("\(sessionMessages.count)", icon: "message", color: accentColor)
                        statBadge("\(totalIn)↓", icon: "arrow.down", color: .green)
                        statBadge("\(totalOut)↑", icon: "arrow.up", color: .orange)
                    }
                }

                Button {
                    state.pendingChatSession = session.sessionId
                    let projectName = session.projectPath.components(separatedBy: "/").last ?? "Session"
                    state.pendingChatSessionTitle = projectName
                    state.pendingChatWorkingDirectory = session.projectPath
                } label: {
                    Label("In Chat öffnen", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .controlSize(.small)
            }
            .padding(12)

            Divider().foregroundStyle(theme.cardBorder)

            if isLoadingMessages {
                Spacer()
                ProgressView("Nachrichten werden geladen…")
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessionMessages) { msg in
                            historyMessageView(msg)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func historyMessageView(_ msg: HistoryMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .user { Spacer(minLength: 40) }

            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 3) {
                // Role header
                HStack(spacing: 4) {
                    if msg.role == .assistant, let model = msg.model {
                        Image(systemName: "cpu.fill").font(.system(size: 9)).foregroundStyle(accentColor)
                        Text(model.replacing("claude-", with: "")).font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                    }
                    if msg.role == .user {
                        Text("Du").font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                    }
                    Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(theme.tertiaryText.opacity(0.7))
                }

                // Content
                if msg.content.isEmpty && !msg.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(msg.toolCalls) { tc in
                            HStack(spacing: 4) {
                                Image(systemName: "wrench.fill").font(.system(size: 9)).foregroundStyle(.orange)
                                Text(tc.name).font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange.opacity(0.8))
                            }
                        }
                    }
                    .padding(8).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else if !msg.content.isEmpty {
                    Text(msg.content)
                        .font(.system(size: 12))
                        .foregroundStyle(msg.role == .user ? .white : theme.primaryText)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(msg.role == .user
                                      ? AnyShapeStyle(LinearGradient(
                                          colors: [accentColor, accentColor.opacity(0.75)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(theme.cardBg))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(msg.role == .user ? .clear : theme.cardBorder, lineWidth: 0.5))
                }

                // Token usage
                if msg.role == .assistant && (msg.inputTokens > 0 || msg.outputTokens > 0) {
                    HStack(spacing: 6) {
                        Text("\(msg.inputTokens)↓ \(msg.outputTokens)↑")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.tertiaryText)
                        if msg.cacheTokens > 0 {
                            Text("cache: \(msg.cacheTokens)")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.tertiaryText)
                        }
                    }
                }
            }

            if msg.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private func statBadge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(color.opacity(0.8))
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Placeholder

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 32)).foregroundStyle(theme.tertiaryText)
            Text("Session auswählen")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondaryText)
            Text("Wähle ein Projekt und eine\nSession um den Verlauf zu sehen.")
                .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load messages

    private func loadMessages(for session: HistorySession) async {
        isLoadingMessages = true
        sessionMessages = await state.historyService.loadMessages(for: session)
        isLoadingMessages = false
    }
}
