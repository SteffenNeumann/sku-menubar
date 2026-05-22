import SwiftUI
import Charts

// MARK: - HomeTileID + Identifiable
// HomeTileID is defined in CLIModels.swift; add Identifiable conformance here.

extension HomeTileID: Identifiable {
    var id: String { rawValue }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Binding var selectedSection: AppSection

    @State private var showingCustomize         = false
    @State private var showTMetricDatePicker    = false
    @State private var tmetricDraftFrom: Date   = Calendar.current.startOfDay(for: Date())
    @State private var tmetricDraftTo:   Date   = Date()
    @State private var viewAppearDate:    Date   = Date()
    @State private var selectedInquiry: CustomerInquiry?
    @State private var inquiryFilter: InquiryStatus? = nil

    private var accentColor: Color { theme.accentText }

    // Visible tiles in user-defined order
    private var orderedVisibleTiles: [HomeTileID] {
        state.homeTileOrder.filter { state.homeTileVisible.contains($0) }
    }

    // Pack tiles into rows of total colSpan ≤ 3
    private var tileRows: [[HomeTileID]] {
        var rows: [[HomeTileID]] = []
        var currentRow: [HomeTileID] = []
        var usedCols = 0
        for tile in orderedVisibleTiles {
            let span = tile.colSpan
            if usedCols + span > 3 {
                if !currentRow.isEmpty { rows.append(currentRow) }
                currentRow = [tile]
                usedCols = span
            } else {
                currentRow.append(tile)
                usedCols += span
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    tileGrid
                }
                .frame(maxWidth: 980)
                .padding(20)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingCustomize) {
            HomeTileCustomizeSheet(isPresented: $showingCustomize)
                .environmentObject(state)
                .environment(\.appTheme, theme)
        }
        .sheet(item: $selectedInquiry) { inquiry in
            InquiryDetailSheet(inquiry: inquiry, workflow: state.customerInquiryWorkflow)
                .environment(\.appTheme, theme)
        }
    }

    // MARK: - Tile Grid

    @ViewBuilder
    private var tileGrid: some View {
        if orderedVisibleTiles.isEmpty {
            emptyDashboard
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(tileRows.indices, id: \.self) { rowIndex in
                    GridRow {
                        let row = tileRows[rowIndex]
                        let usedCols = row.reduce(0) { $0 + $1.colSpan }
                        ForEach(row) { tileID in
                            tileView(for: tileID)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .gridCellColumns(tileID.colSpan)
                        }
                        if usedCols < 3 {
                            Color.clear
                                .gridCellColumns(3 - usedCols)
                        }
                    }
                }
            }
        }
    }

    private var emptyDashboard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.tertiaryText)
            Text("Alle Tiles ausgeblendet.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
            Button("Tiles verwalten") { showingCustomize = true }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Tile Dispatch

    @ViewBuilder
    private func tileView(for id: HomeTileID) -> some View {
        switch id {
        case .quickActions:   quickActionsCard
        case .costToday:      costTodayCard
        case .recentProjects: recentProjectsCard
        case .activeSessions: activeSessionsCard
        case .agents:         agentsCard
        case .tokenUsage:     tokenUsageCard
        case .zeiterfassung:  zeiterfassungCard
        case .kundenanfragen: kundenanfragenCard
        case .gitStatus:      gitStatusCard
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Dein Claude Code Dashboard auf einen Blick.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            HStack(spacing: 8) {
                if !state.activeSessions.isEmpty {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(theme.statusGreen.opacity(0.25)).frame(width: 10, height: 10)
                            Circle().fill(theme.statusGreen).frame(width: 6, height: 6)
                        }
                        Text("\(state.activeSessions.count) aktiv")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.statusGreen)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.statusGreen.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.statusGreen.opacity(0.25), lineWidth: 1))
                }

                Button {
                    showingCustomize = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                        Text("Bearbeiten")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default:      return "Gute Nacht"
        }
    }

    // MARK: - Quick Actions Card

    private var quickActionsCard: some View {
        HomeTile(title: "Schnellzugriff", icon: "bolt.fill", iconColor: accentColor, theme: theme) {
            VStack(spacing: 8) {
                quickActionButton(label: "Neuer Chat",    icon: "bubble.left.and.bubble.right.fill", color: theme.statusGreen)  { selectedSection = .chat }
                quickActionButton(label: "File Explorer", icon: "folder.fill",                        color: .indigo) { selectedSection = .files }
                quickActionButton(label: "Code Review",   icon: "checklist",                          color: .mint)   { selectedSection = .codeReview }
                quickActionButton(label: "Agents",        icon: "cpu.fill",                           color: .purple) { selectedSection = .agents }
            }
        }
    }

    private func quickActionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() } }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM tok", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fK tok", Double(n) / 1_000) }
        return "\(n) tok"
    }

    // MARK: - Cost Today Card

    private var costTodayCard: some View {
        let weekTokenLimit = state.settings.claudeWeeklyTokenLimit
        let weekTokens     = state.localWeekTokens
        let weekPct: Double = weekTokenLimit > 0 ? min(1.0, Double(weekTokens) / Double(weekTokenLimit)) : 0
        let barColor: Color = weekPct > 0.9 ? theme.statusRed : weekPct > 0.7 ? theme.statusOrange : theme.accentIcon

        return HomeTile(title: "Kosten Heute", icon: "eurosign.circle.fill", iconColor: theme.statusOrange, theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fmt(state.localTodayCost))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("Heute")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diese Woche")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(weekTokenLimit > 0
                             ? fmtTok(weekTokens)
                             : state.fmt(state.localWeekCost))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(barColor)
                    }
                    if weekTokenLimit > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                                Capsule()
                                    .fill(barColor)
                                    .frame(width: geo.size.width * weekPct)
                                    .animation(.spring(response: 0.5), value: weekPct)
                            }
                        }
                        .frame(height: 4)
                        Text("Limit: \(fmtTok(weekTokenLimit))")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Recent Projects Card

    private var recentProjectsCard: some View {
        let projects = Array(state.historyService.projects.prefix(3))

        return HomeTile(title: "Letzte Projekte", icon: "clock.arrow.circlepath", iconColor: theme.statusOrange, theme: theme) {
            VStack(alignment: .leading, spacing: 0) {
                if projects.isEmpty {
                    emptyState(icon: "folder.badge.questionmark", text: "Noch keine Projekte vorhanden.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(projects) { project in
                            let session = project.sessions.first
                            Button {
                                if let s = session {
                                    state.pendingChatSession = s.sessionId
                                    state.pendingChatWorkingDirectory = s.projectPath
                                } else {
                                    state.pendingChatNewProject = project.path
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedSection = .chat
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(theme.statusOrange.opacity(0.12))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(theme.statusOrange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.displayName)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(theme.primaryText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if let s = session {
                                            Text(s.preview.isEmpty ? "Kein Vorschau-Text" : s.preview)
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.tertiaryText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        } else {
                                            Text("\(project.sessions.count) Sessions")
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.tertiaryText)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Active Sessions Card

    private var activeSessionsCard: some View {
        HomeTile(title: "Aktive Sessions", icon: "terminal.fill", iconColor: theme.statusGreen, theme: theme) {
            VStack(alignment: .leading, spacing: 0) {
                if state.activeSessions.isEmpty {
                    emptyState(icon: "terminal", text: "Keine aktiven Prozesse.")
                } else {
                    VStack(spacing: 6) {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(state.activeSessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                        .frame(maxHeight: 200)

                        HStack(spacing: 8) {
                            Spacer()
                            Button {
                                refreshActiveSessions()
                            } label: {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Button {
                                terminateAllSessions()
                            } label: {
                                Label("Alle beenden", systemImage: "xmark.circle")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.statusRed)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sessionRow(_ session: ActiveCLISession) -> some View {
        Button {
            state.pendingChatSession = session.sessionId
            state.pendingChatWorkingDirectory = session.cwd
            selectedSection = .chat
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(theme.statusGreen.opacity(0.20)).frame(width: 8, height: 8)
                    Circle().fill(theme.statusGreen).frame(width: 5, height: 5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.cwdDisplay)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(session.entrypointLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.primaryText.opacity(0.08), in: Capsule())
                    }
                    if !session.topic.isEmpty {
                        Text(session.topic)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(session.startedAt, style: .relative)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                        if !session.version.isEmpty {
                            Text("v\(session.version)")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }
                Spacer()

                Button {
                    terminateSession(session)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Session beenden (PID \(session.pid))")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.statusGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func terminateSession(_ session: ActiveCLISession) {
        kill(Int32(session.pid), SIGTERM)
        let sessionFile = NSHomeDirectory() + "/.claude/sessions/\(session.pid).json"
        try? FileManager.default.removeItem(atPath: sessionFile)
        refreshActiveSessions()
    }

    private func terminateAllSessions() {
        for session in state.activeSessions {
            kill(Int32(session.pid), SIGTERM)
            let sessionFile = NSHomeDirectory() + "/.claude/sessions/\(session.pid).json"
            try? FileManager.default.removeItem(atPath: sessionFile)
        }
        refreshActiveSessions()
    }

    private func refreshActiveSessions() {
        Task {
            let sessions = await Task.detached(priority: .utility) {
                ClaudeCLIService.loadActiveSessionsSync()
            }.value
            state.activeSessions = sessions
        }
    }

    // MARK: - Agents Card

    private var agentsCard: some View {
        let agents = state.agentService.agents
        let activeAgents = agents.filter { $0.isActive }

        return HomeTile(title: "Agents", icon: "cpu.fill", iconColor: .purple, theme: theme) {
            if agents.isEmpty {
                emptyState(icon: "cpu", text: "Keine Agents definiert.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        agentStat(value: "\(agents.count)", label: "Gesamt", color: .purple)
                        agentStat(value: "\(activeAgents.count)", label: "Aktiv", color: theme.statusGreen)
                    }

                    Divider().opacity(0.3)

                    VStack(spacing: 5) {
                        ForEach(agents.prefix(3)) { agent in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(agent.dotColor)
                                    .frame(width: 7, height: 7)
                                Text(agent.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(1)
                                Spacer()
                                if agent.isActive {
                                    Text("aktiv")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.statusGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.statusGreen.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedSection = .agents
                        }
                    } label: {
                        Text("Alle anzeigen")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                            .background(theme.accentIcon.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func agentStat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    // MARK: - Token Usage Card

    private var tokenUsageCard: some View {
        let todayIn = state.localTodayTokens
        let weekIn  = state.localWeekTokens
        let ratio: Double = weekIn > 0 ? min(1.0, Double(todayIn) / Double(weekIn)) : 0

        return HomeTile(title: "Token-Verbrauch", icon: "chart.bar.fill", iconColor: accentColor, theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTokens(todayIn))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("Tokens heute")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diese Woche")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(formatTokens(weekIn) + " tok")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                            Capsule()
                                .fill(theme.accentIcon)
                                .frame(width: geo.size.width * max(0.02, ratio))
                                .animation(.spring(response: 0.5), value: ratio)
                        }
                    }
                    .frame(height: 4)
                    Text("Heute ist \(Int(ratio * 100))% der Woche")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Zeiterfassung Card

    private var zeiterfassungCard: some View {
        HomeTile(title: "Zeiterfassung", icon: "timer", iconColor: .indigo, theme: theme) {
            VStack(alignment: .leading, spacing: 0) {
                let _ = viewAppearDate
                if state.settings.tmetricApiToken.isEmpty {
                    VStack(spacing: 10) {
                        emptyState(icon: "timer", text: "TMetric API-Token in den Einstellungen hinterlegen.")
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedSection = .settings
                            }
                        } label: {
                            Text("Einstellungen öffnen")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // ── Period chips + custom date ────────────────────────
                    HStack(spacing: 4) {
                        ForEach(TMetricPeriod.allCases, id: \.self) { p in
                            let active = !state.tmetricIsCustomRange && state.tmetricPeriod == p
                            Text(p.label)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Color.indigo : theme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(active ? Color.indigo.opacity(0.13) : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                                .onTapGesture {
                                    state.tmetricIsCustomRange = false
                                    state.tmetricPeriod = p
                                }
                        }
                        Spacer(minLength: 0)
                        Button {
                            tmetricDraftFrom = state.tmetricIsCustomRange ? state.tmetricCustomFrom : Calendar.current.startOfDay(for: Date())
                            tmetricDraftTo   = state.tmetricIsCustomRange ? state.tmetricCustomTo   : Date()
                            showTMetricDatePicker = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar").font(.system(size: 10, weight: .medium))
                                if state.tmetricIsCustomRange { Text(tmetricCustomRangeLabel).font(.system(size: 10, weight: .medium)) }
                            }
                            .foregroundStyle(state.tmetricIsCustomRange ? Color.indigo : theme.tertiaryText)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(state.tmetricIsCustomRange ? Color.indigo.opacity(0.13) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showTMetricDatePicker, arrowEdge: .bottom) {
                            TMetricDateRangePopover(from: $tmetricDraftFrom, to: $tmetricDraftTo) {
                                state.tmetricCustomFrom    = tmetricDraftFrom
                                state.tmetricCustomTo      = tmetricDraftTo
                                state.tmetricIsCustomRange = true
                                showTMetricDatePicker      = false
                                state.tmetricLastUpdated   = nil
                                Task { await state.refreshTMetric(force: true) }
                            }
                        }
                    }
                    .padding(.bottom, 10)

                    let displayedProjects: [TMetricProjectSummary] = {
                        if let id = state.tmetricSelectedProjectId {
                            return state.tmetricProjects.filter { $0.id == id }
                        }
                        return state.tmetricProjects
                    }()

                    if state.tmetricIsLoading && state.tmetricProjects.isEmpty {
                        HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }
                            .padding(.top, 12)
                    } else if let err = state.tmetricError {
                        emptyState(icon: "exclamationmark.triangle", text: err)
                    } else if displayedProjects.isEmpty {
                        emptyState(icon: "timer", text: state.tmetricIsCustomRange
                            ? "Keine Zeit in diesem Zeitraum."
                            : state.tmetricPeriod.emptyText)
                    } else {
                        // ── Gesamt + Donut + Top-3-Cards ─────────────────
                        let totalSeconds = displayedProjects.map(\.totalSeconds).reduce(0, +)
                        let chartColors: [Color] = [.indigo, .blue, .cyan, .teal, .purple, .pink, theme.statusOrange, theme.statusGreen]

                        HStack(alignment: .center, spacing: 18) {
                            // ── Donut (A: größer, Gesamtzeit + Label) ────────
                            Chart(Array(displayedProjects.prefix(8).enumerated()), id: \.element.id) { idx, project in
                                SectorMark(
                                    angle: .value("Zeit", project.totalSeconds),
                                    innerRadius: .ratio(0.58),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(chartColors[idx % chartColors.count])
                                .cornerRadius(3)
                            }
                            .frame(width: 148, height: 148)
                            .overlay {
                                VStack(spacing: 2) {
                                    let h = totalSeconds / 3600
                                    let m = (totalSeconds % 3600) / 60
                                    Text(h > 0 ? "\(h)h" : "\(m)m")
                                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                                        .foregroundStyle(theme.primaryText)
                                    if h > 0 {
                                        Text("\(m)m")
                                            .font(.system(size: 13).monospacedDigit())
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    Text("Gesamt")
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                            }

                            // ── Top-3-Cards (C: Akzentbalken + Fortschritt) ──
                            VStack(spacing: 7) {
                                ForEach(Array(displayedProjects.prefix(3).enumerated()), id: \.element.id) { idx, p in
                                    let pct = totalSeconds > 0 ? Double(p.totalSeconds) / Double(totalSeconds) : 0
                                    let color = chartColors[idx % chartColors.count]
                                    let pctInt = Int(pct * 100)

                                    // Ø pro Tag
                                    let (periodFrom, periodTo) = state.tmetricIsCustomRange
                                        ? (state.tmetricCustomFrom, state.tmetricCustomTo)
                                        : state.tmetricPeriod.dateRange()
                                    let daysInPeriod = max(1, Int(ceil(periodTo.timeIntervalSince(periodFrom) / 86400)))
                                    let avgSecs = p.totalSeconds / daysInPeriod
                                    let avgStr: String = {
                                        let h = avgSecs / 3600; let m = (avgSecs % 3600) / 60
                                        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
                                    }()

                                    // Trend
                                    let prevProject = state.tmetricPreviousProjects.first(where: { $0.id == p.id })
                                    let trendPct: Double? = {
                                        guard let prev = prevProject, prev.totalSeconds > 0 else { return nil }
                                        return Double(p.totalSeconds - prev.totalSeconds) / Double(prev.totalSeconds)
                                    }()

                                    HStack(spacing: 0) {
                                        // Farbiger Akzentbalken links
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(color)
                                            .frame(width: 3)

                                        VStack(alignment: .leading, spacing: 4) {
                                            // Zeile 1: Name + Zeit + %
                                            HStack(alignment: .center, spacing: 6) {
                                                Text(p.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(theme.primaryText)
                                                    .lineLimit(1)
                                                Spacer(minLength: 4)
                                                // Trend-Pfeil
                                                if let trend = trendPct {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                                                            .font(.system(size: 9, weight: .semibold))
                                                        Text("\(Int(abs(trend * 100)))%")
                                                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                                    }
                                                    .foregroundStyle(trend >= 0 ? theme.statusGreen : theme.statusOrange)
                                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background((trend >= 0 ? theme.statusGreen : theme.statusOrange).opacity(0.12), in: Capsule())
                                                }
                                                Text(p.formattedDuration)
                                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                                    .foregroundStyle(color)
                                                Text("\(pctInt)%")
                                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                                    .foregroundStyle(color.opacity(0.75))
                                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background(color.opacity(0.12), in: Capsule())
                                            }
                                            // Zeile 2: Client · Ø/Tag · Sessions
                                            HStack(spacing: 0) {
                                                if !p.clientName.isEmpty {
                                                    Text(p.clientName)
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(theme.tertiaryText)
                                                    Text("  ·  ")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(theme.tertiaryText)
                                                }
                                                Text("Ø \(avgStr)/Tag")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(theme.tertiaryText)
                                                Text("  ·  \(p.entryCount) Sessions")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(theme.tertiaryText)
                                            }
                                            .lineLimit(1)
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 8)
                                    }
                                    .background {
                                        // Background-Fill: subtile Flächenfüllung bis zum %-Anteil
                                        GeometryReader { geo in
                                            HStack(spacing: 0) {
                                                Rectangle()
                                                    .fill(color.opacity(0.07))
                                                    .frame(width: max(3, geo.size.width * pct))
                                                Spacer(minLength: 0)
                                            }
                                        }
                                    }
                                    .background(theme.rowBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 8)

                        // ── Restliche Projekte (4+) als kompakte Einzeiler ─
                        if displayedProjects.count > 3 {
                            VStack(spacing: 0) {
                                Divider().padding(.bottom, 6)
                                ForEach(Array(displayedProjects.dropFirst(3).prefix(5).enumerated()), id: \.element.id) { idx, project in
                                    let color = chartColors[(idx + 3) % chartColors.count]
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 6, height: 6)
                                        Text(project.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(theme.primaryText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if !project.clientName.isEmpty {
                                            Text("· \(project.clientName)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(theme.tertiaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        Text(project.formattedDuration)
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(color)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(.bottom, 4)
                        }

                        // ── Dot-Timeline (nur Heute) ──────────────────────
                        if state.tmetricPeriod == .today && !state.tmetricIsCustomRange
                            && !state.tmetricTimelineEntries.isEmpty {
                            Divider().padding(.vertical, 6)
                            TMetricDotTimeline(
                                entries:     state.tmetricTimelineEntries,
                                summaries:   state.tmetricProjects,
                                chartColors: chartColors,
                                now:         Date()
                            )
                        }

                        // ── Footer ────────────────────────────────────────
                        HStack {
                            if let updated = state.tmetricLastUpdated {
                                let fmt = RelativeDateTimeFormatter()
                                Text("Aktualisiert \(fmt.localizedString(for: updated, relativeTo: Date()))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            Spacer()
                            Button { Task { await state.refreshTMetric(force: true) } } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.tertiaryText)
                                    .rotationEffect(.degrees(state.tmetricIsLoading ? 360 : 0))
                                    .animation(
                                        state.tmetricIsLoading
                                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                                            : .default,
                                        value: state.tmetricIsLoading)
                            }
                            .buttonStyle(.plain)
                            .help("Zeitdaten neu laden")
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://app.tmetric.com/#/tracker/276655/")!)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .help("In TMetric öffnen")
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .onAppear { viewAppearDate = Date() }
        }
    }

    private func formatElapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private var tmetricCustomRangeLabel: String {
        let df = DateFormatter()
        df.dateFormat = "d.M."
        return "\(df.string(from: state.tmetricCustomFrom))–\(df.string(from: state.tmetricCustomTo))"
    }

    // MARK: - Git Status Card

    @State private var expandedRepo: String? = nil

    private var gitStatusCard: some View {
        let repos = state.gitRepoStatuses
        let dirtyRepos = repos.filter { $0.hasChanges }
        let totalChanges = dirtyRepos.reduce(0) { $0 + $1.totalChanges }

        return HomeTile(title: "Git Status", icon: "arrow.triangle.branch", iconColor: .orange, theme: theme) {
            VStack(alignment: .leading, spacing: 0) {
                if state.gitStatusIsLoading && repos.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }
                        .padding(.vertical, 16)
                } else if repos.isEmpty {
                    emptyState(icon: "arrow.triangle.branch", text: "Keine Git-Repos gefunden.")
                } else if dirtyRepos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(theme.statusGreen)
                        Text("Alle \(repos.count) Repos sauber")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.statusGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Summary header
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(dirtyRepos.count)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text(dirtyRepos.count == 1 ? "Repo" : "Repos")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(totalChanges)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.statusOrange)
                            Text("Änderungen")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 10)

                    Divider().opacity(0.3).padding(.bottom, 8)

                    // Repo list
                    VStack(spacing: 6) {
                        ForEach(dirtyRepos) { repo in
                            gitRepoRow(repo)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Footer
                HStack {
                    Text("\(repos.count) Repos")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                    Button {
                        Task { await state.refreshGitStatuses() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                            .rotationEffect(.degrees(state.gitStatusIsLoading ? 360 : 0))
                            .animation(
                                state.gitStatusIsLoading
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: state.gitStatusIsLoading)
                    }
                    .buttonStyle(.plain)
                    .help("Git Status aktualisieren")
                }
                .padding(.top, 8)
            }
        }
    }

    private func gitRepoRow(_ repo: GitRepoStatus) -> some View {
        let isExpanded = expandedRepo == repo.id
        let modified  = repo.changedFiles.filter { $0.statusCode == "M" }.count
        let untracked = repo.changedFiles.filter { $0.statusCode == "??" }.count
        let added     = repo.changedFiles.filter { $0.statusCode == "A" }.count
        let deleted   = repo.changedFiles.filter { $0.statusCode == "D" }.count

        return VStack(alignment: .leading, spacing: 0) {
            // Repo header row
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    expandedRepo = isExpanded ? nil : repo.id
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(repo.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                            Text(repo.branch)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.10), in: Capsule())
                        }
                        HStack(spacing: 8) {
                            if modified > 0 {
                                gitBadge(count: modified, label: "M", color: .orange)
                            }
                            if untracked > 0 {
                                gitBadge(count: untracked, label: "?", color: .blue)
                            }
                            if added > 0 {
                                gitBadge(count: added, label: "+", color: theme.statusGreen)
                            }
                            if deleted > 0 {
                                gitBadge(count: deleted, label: "−", color: theme.statusRed)
                            }
                            if repo.aheadCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up").font(.system(size: 8, weight: .bold))
                                    Text("\(repo.aheadCount)")
                                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                }
                                .foregroundStyle(theme.statusGreen)
                            }
                            if repo.behindCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold))
                                    Text("\(repo.behindCount)")
                                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                }
                                .foregroundStyle(theme.statusRed)
                            }
                        }
                    }
                    Spacer()
                    Text("\(repo.totalChanges)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            // Expanded file list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(repo.changedFiles.prefix(15)) { file in
                        HStack(spacing: 8) {
                            Image(systemName: file.statusIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(gitFileColor(file.statusCode))
                                .frame(width: 16)
                            Text(file.filePath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(file.statusLabel)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(gitFileColor(file.statusCode))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(gitFileColor(file.statusCode).opacity(0.12), in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    if repo.changedFiles.count > 15 {
                        Text("… und \(repo.changedFiles.count - 15) weitere")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
                .background(theme.rowBg.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 2)
            }
        }
    }

    private func gitBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func gitFileColor(_ code: String) -> Color {
        switch code {
        case "M":  return .orange
        case "A":  return theme.statusGreen
        case "D":  return theme.statusRed
        case "R":  return .blue
        case "??": return .blue
        case "UU": return theme.statusRed
        default:   return theme.secondaryText
        }
    }

    // MARK: - Helpers

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
        : n >= 1_000   ? String(format: "%.0fK", Double(n) / 1_000)
        : "\(n)"
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.tertiaryText)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Kundenanfragen Card

    private var kundenanfragenCard: some View {
        let wf        = state.customerInquiryWorkflow
        let all       = wf.recentInquiries
        let visible   = all.filter { !$0.isArchived }
        let archived  = all.filter { $0.isArchived }.count
        let pending   = visible.filter { $0.status == .pending || $0.status == .analyzing }.count
        let waiting   = visible.filter { $0.status == .waitingForCustomer }.count
        let working   = visible.filter { $0.status == .inProgress }.count
        let done      = visible.filter { $0.status == .completed }.count
        let failed    = visible.filter { $0.status == .failed || $0.status == .blocked }.count
        let polling   = state.emailPollingService

        let filtered: [CustomerInquiry] = {
            switch inquiryFilter {
            case .none:                return Array(visible.prefix(12))
            case .pending, .analyzing: return visible.filter { $0.status == .pending || $0.status == .analyzing }
            case .waitingForCustomer:  return visible.filter { $0.status == .waitingForCustomer }
            case .inProgress:          return visible.filter { $0.status == .inProgress }
            case .completed:           return visible.filter { $0.status == .completed }
            case .failed, .blocked:    return visible.filter { $0.status == .failed || $0.status == .blocked }
            }
        }()

        return HomeTile(title: "Kundenanfragen", icon: "envelope.badge.fill", iconColor: .teal, theme: theme) {
            if let err = polling.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.statusOrange).font(.system(size: 11))
                    Text(err).font(.system(size: 11)).foregroundStyle(theme.statusOrange).lineLimit(2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.statusOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
            }

            if visible.isEmpty && archived == 0 {
                emptyState(icon: "envelope", text: "Noch keine Anfragen.\nMail-Routing in einem Persona-Agent konfigurieren.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Stats row — tappable filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            inquiryStatChip(value: "\(visible.count)", label: "Gesamt", color: .teal, filterVal: nil)
                            if pending > 0 { inquiryStatChip(value: "\(pending)", label: "Neu",       color: theme.statusOrange, filterVal: .analyzing) }
                            if waiting > 0 { inquiryStatChip(value: "\(waiting)", label: "Wartet",    color: .yellow, filterVal: .waitingForCustomer) }
                            if working > 0 { inquiryStatChip(value: "\(working)", label: "In Arbeit", color: .blue,   filterVal: .inProgress) }
                            if done    > 0 { inquiryStatChip(value: "\(done)",    label: "Fertig",    color: theme.statusGreen,  filterVal: .completed) }
                            if failed  > 0 { inquiryStatChip(value: "\(failed)",  label: "Fehler",    color: theme.statusRed,    filterVal: .failed) }
                            Spacer(minLength: 0)
                            if polling.isPolling { ProgressView().controlSize(.mini).padding(.trailing, 4) }
                        }
                        .padding(.horizontal, 12)
                    }

                    if inquiryFilter != nil {
                        HStack(spacing: 6) {
                            Text("\(filtered.count) Ergebnis\(filtered.count == 1 ? "" : "se")")
                                .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                            Button { inquiryFilter = nil } label: {
                                Label("Filter aufheben", systemImage: "xmark.circle.fill")
                                    .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                    }

                    Divider().opacity(0.2)

                    // Inquiry list
                    VStack(spacing: 4) {
                        ForEach(filtered) { inquiry in
                            inquiryDetailRow(inquiry)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { selectedInquiry = inquiry }
                        }
                        if filtered.isEmpty {
                            Text("Keine Einträge für diesen Filter.")
                                .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                                .padding(.vertical, 8).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

            // Footer
            HStack(spacing: 8) {
                if polling.isPolling {
                    ProgressView().controlSize(.mini)
                    Text("Prüfe…").font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                } else if let lp = polling.lastPollDate {
                    Text("Zuletzt: \(lp, style: .relative)")
                        .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                } else {
                    Text("Noch kein Poll").font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                }
                if archived > 0 {
                    Button {
                        wf.deleteArchived()
                    } label: {
                        Text("\(archived) archiviert — Leeren")
                            .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    Task { await state.emailPollingService.poll() }
                } label: {
                    Label("Jetzt prüfen", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.teal)
                }
                .buttonStyle(.plain)
                .disabled(polling.isPolling)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func inquiryStatChip(value: String, label: String, color: Color, filterVal: InquiryStatus?) -> some View {
        let isActive = inquiryFilter == filterVal
        return Button {
            inquiryFilter = isActive ? nil : filterVal
        } label: {
            VStack(spacing: 2) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(label).font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isActive ? color.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(isActive ? RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.3), lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
    }

    private func inquiryDetailRow(_ inquiry: CustomerInquiry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + sender + time
            HStack(spacing: 8) {
                Circle().fill(inquiryStatusColor(inquiry.status)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(inquiry.suggestedLinearTitle ?? inquiry.subject)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(inquiry.senderName.isEmpty ? inquiry.senderAddress : "\(inquiry.senderName) <\(inquiry.senderAddress)>")
                            .font(.system(size: 10)).foregroundStyle(theme.tertiaryText).lineLimit(1)
                        if let slug = inquiry.projectSlug {
                            Text(slug)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.teal.opacity(0.1), in: Capsule())
                        }
                        if let lid = inquiry.linearIssueIdentifier {
                            Text(lid)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.indigo.opacity(0.1), in: Capsule())
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(inquiry.receivedAt, style: .relative)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.tertiaryText)
                    if let p = inquiry.priority {
                        HStack(spacing: 2) {
                            Image(systemName: p <= 2 ? "exclamationmark.triangle.fill" : "flag.fill")
                                .font(.system(size: 8))
                            Text(["", "Dringend", "Hoch", "Mittel", "Niedrig"][min(p, 4)])
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(p == 1 ? theme.statusRed : p == 2 ? theme.statusOrange : .secondary)
                    }
                }
                // Archive button for completed entries
                if inquiry.status == .completed {
                    Button {
                        state.customerInquiryWorkflow.archive(inquiry)
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Archivieren")
                }
            }

            if inquiry.status == .completed {
                // Compact: just completion result — no phase pipeline
                if let result = inquiry.completionSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.statusGreen).font(.system(size: 10))
                        Text(result).font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    }
                    .padding(.leading, 16)
                }
            } else {
                // Full: phase pipeline + status detail
                HStack(spacing: 0) {
                    inquiryPhaseStep("Eingang",   icon: "envelope.open.fill",    done: true, active: inquiry.status == .pending)
                    phaseConnector(done: inquiry.status != .pending)
                    inquiryPhaseStep("Analyse",   icon: "brain",                 done: phaseCompleted(inquiry, .analyzing), active: inquiry.status == .analyzing)
                    phaseConnector(done: phaseCompleted(inquiry, .analyzing))
                    inquiryPhaseStep("Linear",    icon: "arrow.triangle.2.circlepath", done: inquiry.linearIssueId != nil, active: inquiry.linearIssueId != nil && inquiry.status == .analyzing)
                    phaseConnector(done: inquiry.linearIssueId != nil)
                    inquiryPhaseStep(inquiry.missingInfo.isEmpty ? "Bearbeitung" : "Rückfrage",
                                     icon: inquiry.missingInfo.isEmpty ? "gearshape.fill" : "questionmark.bubble.fill",
                                     done: phaseCompleted(inquiry, .inProgress) || inquiry.status == .completed,
                                     active: inquiry.status == .waitingForCustomer || inquiry.status == .inProgress)
                    phaseConnector(done: inquiry.status == .completed)
                    inquiryPhaseStep("Fertig", icon: "checkmark.seal.fill", done: inquiry.status == .completed, active: false)
                }
                .padding(.leading, 16)

                if inquiry.status == .failed || inquiry.status == .blocked, let err = inquiry.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.statusRed).font(.system(size: 10))
                        Text(err).font(.system(size: 10)).foregroundStyle(theme.statusRed).lineLimit(2)
                    }
                    .padding(.leading, 16)
                } else if inquiry.status == .waitingForCustomer, !inquiry.missingInfo.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill").foregroundStyle(.yellow).font(.system(size: 10))
                        Text("Wartet auf: \(inquiry.missingInfo.joined(separator: ", "))").font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(2)
                    }
                    .padding(.leading, 16)
                } else if let summary = inquiry.analysisSummary {
                    Text(summary).font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(2).padding(.leading, 16)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.rowBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func inquiryPhaseStep(_ label: String, icon: String, done: Bool, active: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(done ? Color.teal.opacity(0.15) : active ? Color.blue.opacity(0.12) : theme.rowBg)
                    .frame(width: 22, height: 22)
                if active && !done {
                    Circle().strokeBorder(Color.blue, lineWidth: 1.5).frame(width: 22, height: 22)
                }
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(done ? .teal : active ? .blue : theme.tertiaryText)
            }
            Text(label)
                .font(.system(size: 8, weight: done ? .semibold : .regular))
                .foregroundStyle(done ? theme.primaryText : active ? .blue : theme.tertiaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 44)
    }

    private func phaseConnector(done: Bool) -> some View {
        Rectangle()
            .fill(done ? Color.teal.opacity(0.4) : theme.tertiaryText.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: 24)
            .offset(y: -6)
    }

    private func phaseCompleted(_ inquiry: CustomerInquiry, _ phase: InquiryStatus) -> Bool {
        let order: [InquiryStatus] = [.pending, .analyzing, .waitingForCustomer, .inProgress, .completed]
        guard let phaseIdx = order.firstIndex(of: phase),
              let currentIdx = order.firstIndex(of: inquiry.status) else { return false }
        return currentIdx > phaseIdx
    }

    private func inquiryStatusColor(_ status: InquiryStatus) -> Color {
        switch status {
        case .pending, .analyzing:    return theme.statusOrange
        case .waitingForCustomer:     return .yellow
        case .inProgress:             return .blue
        case .completed:              return theme.statusGreen
        case .blocked, .failed:       return theme.statusRed
        }
    }
}

// MARK: - HomeTile

private struct HomeTile<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let theme: AppTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .kerning(0.8)
                Spacer()
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - HomeTileCustomizeSheet

private struct HomeTileCustomizeSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dashboard anpassen")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Tiles ein-/ausblenden und neu anordnen.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.tertiaryText)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.4)

            List {
                ForEach(state.homeTileOrder) { tileID in
                    HStack(spacing: 12) {
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)

                        Text(tileID.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.primaryText)

                        Spacer()

                        Toggle(
                            isOn: Binding(
                                get: { state.homeTileVisible.contains(tileID) },
                                set: { enabled in
                                    if enabled {
                                        state.homeTileVisible.insert(tileID)
                                    } else {
                                        state.homeTileVisible.remove(tileID)
                                    }
                                }
                            )
                        ) {
                            EmptyView()
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    state.homeTileOrder.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.4)

            // Footer
            HStack {
                Button {
                    state.homeTileOrder = HomeTileID.allCases
                    state.homeTileVisible = Set(HomeTileID.allCases)
                } label: {
                    Text("Zurücksetzen")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Fertig")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 360, height: 420)
        .background(theme.cardSurface)
    }
}

// MARK: - TMetric Date Range Popover

private struct TMetricDateRangePopover: View {
    @Environment(\.appTheme) var theme
    @Binding var from: Date
    @Binding var to:   Date
    let onApply: () -> Void

    private var iso: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone.current; return c
    }
    private var greg: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            Text("Zeitraum wählen")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            // Von / Bis card
            VStack(spacing: 0) {
                dateRow(label: "Von") {
                    DatePicker("", selection: $from, displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                }
                Divider().padding(.leading, 44)
                dateRow(label: "Bis") {
                    DatePicker("", selection: $to, displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                }
            }
            .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

            // Schnellauswahl
            VStack(alignment: .leading, spacing: 10) {
                Text("Schnellauswahl")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        quickChip("Diese Woche") {
                            let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
                            from = iso.date(from: c) ?? iso.startOfDay(for: Date())
                            to   = Date()
                        }
                        quickChip("Letzte Woche") {
                            let now  = Date()
                            let c    = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                            let w0   = iso.date(from: c) ?? iso.startOfDay(for: now)
                            from = iso.date(byAdding: .weekOfYear, value: -1, to: w0) ?? w0
                            to   = iso.date(byAdding: .second, value: -1, to: w0) ?? now
                        }
                    }
                    GridRow {
                        quickChip("Dieser Monat") {
                            from = greg.date(from: greg.dateComponents([.year, .month], from: Date())) ?? Date()
                            to   = Date()
                        }
                        quickChip("Letzter Monat") {
                            let now  = Date()
                            let m0   = greg.date(from: greg.dateComponents([.year, .month], from: now)) ?? now
                            from = greg.date(byAdding: .month, value: -1, to: m0) ?? m0
                            to   = greg.date(byAdding: .second, value: -1, to: m0) ?? now
                        }
                    }
                }
            }

            // Apply
            Button(action: onApply) {
                Text("Anwenden")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 300)
        .background(theme.cardSurface.ignoresSafeArea())
    }

    private func dateRow<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.indigo.opacity(0.13))
                    .frame(width: 30, height: 30)
                Image(systemName: label == "Von" ? "calendar.badge.clock" : "calendar.badge.checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.indigo)
            }
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func quickChip(_ label: String, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.indigo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onTapGesture(perform: action)
    }
}

// MARK: - InquiryDetailSheet

private struct InquiryDetailSheet: View {
    let inquiry: CustomerInquiry
    @ObservedObject var workflow: CustomerInquiryWorkflow
    @Environment(\.appTheme) var theme
    @Environment(\.dismiss) var dismiss
    @State private var isReprocessing = false

    private var liveInquiry: CustomerInquiry {
        workflow.recentInquiries.first(where: { $0.id == inquiry.id }) ?? inquiry
    }

    var body: some View {
        let inq = liveInquiry
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inq.suggestedLinearTitle ?? inq.subject)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    HStack(spacing: 8) {
                        statusBadge(inq)
                        if let lid = inq.linearIssueIdentifier {
                            Text(lid)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.1), in: Capsule())
                        }
                        if let p = inq.priority {
                            priorityBadge(p)
                        }
                    }
                }
                Spacer()
                // Reprocess button
                Button {
                    isReprocessing = true
                    Task {
                        await workflow.reprocess(inquiry)
                        isReprocessing = false
                    }
                } label: {
                    if isReprocessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Erneut bearbeiten", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.teal)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isReprocessing || inq.status == .inProgress || inq.status == .analyzing)
                .padding(.trailing, 8)

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.3)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Progress indicator during reprocessing
                    if isReprocessing || inq.status == .analyzing || inq.status == .inProgress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(inq.status == .analyzing ? "Analysiere…" : inq.status == .inProgress ? "Agent arbeitet…" : "Verarbeite…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Sender + Date
                    detailSection("Absender") {
                        HStack(spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                if !inq.senderName.isEmpty {
                                    Text(inq.senderName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                }
                                Text(inq.senderAddress)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            Text(inq.receivedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }

                    // Matched Persona
                    if let pid = inq.matchedPersonaId {
                        detailSection("Zugewiesener Agent") {
                            HStack(spacing: 6) {
                                Image(systemName: "cpu.fill").foregroundStyle(.purple).font(.system(size: 12))
                                Text(pid).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.primaryText)
                            }
                        }
                    }

                    // Analysis Summary
                    if let summary = inq.analysisSummary {
                        detailSection("Analyse") {
                            Text(summary)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    // Missing Info
                    if !inq.missingInfo.isEmpty {
                        detailSection("Fehlende Informationen") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(inq.missingInfo, id: \.self) { item in
                                    HStack(spacing: 6) {
                                        Image(systemName: "questionmark.circle.fill")
                                            .font(.system(size: 10)).foregroundStyle(.yellow)
                                        Text(item).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                                    }
                                }
                            }
                        }
                    }

                    // Project + Repo
                    if let projName = inq.linearProjectName ?? inq.projectSlug {
                        detailSection("Projekt") {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(.teal)
                                Text(projName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Spacer()
                                if let rp = inq.repoPath {
                                    Button {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: rp)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "folder.badge.gearshape").font(.system(size: 10))
                                            Text("Im Finder").font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if let rp = inq.repoPath {
                                Text(rp.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                    }

                    // Linear Issue
                    if inq.linearIssueId != nil {
                        detailSection("Linear") {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12)).foregroundStyle(.indigo)
                                if let identifier = inq.linearIssueIdentifier {
                                    Text(identifier)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.indigo)
                                }
                                Text("Issue erstellt")
                                    .font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                            }
                        }
                    }

                    // Result / Completion
                    if let result = inq.completionSummary, !result.isEmpty {
                        detailSection("Ergebnis") {
                            Text(result)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.primaryText)
                                .textSelection(.enabled)
                        }
                    }

                    // Error
                    if let err = inq.errorMessage {
                        detailSection("Fehler") {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(theme.statusRed).font(.system(size: 12))
                                Text(err).font(.system(size: 12)).foregroundStyle(theme.statusRed)
                            }
                        }
                    }

                    // Original Email
                    detailSection("Original-E-Mail") {
                        Text(String(inq.body.prefix(3000)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 520)
        .background(theme.cardSurface)
    }

    private func statusBadge(_ inq: CustomerInquiry) -> some View {
        let (label, color): (String, Color) = {
            switch inq.status {
            case .pending:            return ("Neu", theme.statusOrange)
            case .analyzing:          return ("Analyse…", theme.statusOrange)
            case .waitingForCustomer: return ("Wartet auf Kunde", .yellow)
            case .inProgress:         return ("In Bearbeitung", .blue)
            case .completed:          return ("Abgeschlossen", theme.statusGreen)
            case .blocked:            return ("Blockiert", theme.statusRed)
            case .failed:             return ("Fehler", theme.statusRed)
            }
        }()
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func priorityBadge(_ p: Int) -> some View {
        let (label, color): (String, Color) = {
            switch p {
            case 1: return ("Dringend", theme.statusRed)
            case 2: return ("Hoch", theme.statusOrange)
            case 3: return ("Mittel", .secondary)
            default: return ("Niedrig", .secondary)
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: p <= 2 ? "exclamationmark.triangle.fill" : "flag.fill").font(.system(size: 9))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
    }

    private func detailSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.rowBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - TMetric Dot-Timeline

private struct TMetricDotTimeline: View {
    let entries:    [TMetricTimelineEntry]
    let summaries:  [TMetricProjectSummary]
    let chartColors: [Color]
    let now:        Date

    @Environment(\.appTheme) var theme

    private static let hourFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var sorted: [TMetricTimelineEntry] { entries.sorted { $0.start < $1.start } }

    private var timelineStart: Date { sorted.first?.start ?? now }
    private var timelineEnd:   Date { max(now, sorted.compactMap(\.end).max() ?? now) }
    private var totalRange: Double  { max(1.0, timelineEnd.timeIntervalSince(timelineStart)) }

    private func frac(_ d: Date) -> Double {
        max(0, min(1, d.timeIntervalSince(timelineStart) / totalRange))
    }
    private func colorFor(_ entry: TMetricTimelineEntry) -> Color {
        let idx = summaries.firstIndex(where: { $0.id == entry.projectId }) ?? 0
        return chartColors[idx % chartColors.count]
    }

    private var hourMarks: [Date] {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: timelineStart)
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0; comps.second = 0
        guard var d = cal.date(from: comps) else { return [] }
        var marks: [Date] = []
        while d <= timelineEnd {
            marks.append(d)
            d = d.addingTimeInterval(3600)
        }
        return marks
    }

    var body: some View {
        if !sorted.isEmpty {
            VStack(spacing: 3) {
                // ── Chips + Track ───────────────────────────────────────
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        // Track background
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: w, height: 20)
                            .offset(y: 22)

                        ForEach(sorted) { entry in
                            let color   = colorFor(entry)
                            let x       = CGFloat(frac(entry.start)) * w
                            let endDate = entry.end ?? now
                            let segW    = max(4, CGFloat(frac(endDate)) * w - x)
                            let isRunning = entry.end == nil
                            let dur     = max(0, Int(endDate.timeIntervalSince(entry.start)))
                            let h = dur / 3600; let m = (dur % 3600) / 60
                            let durStr  = h > 0 ? "\(h)h \(m)m" : "\(m)m"

                            // Segment bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(isRunning ? 1.0 : 0.78))
                                .frame(width: segW, height: 20)
                                .offset(x: x, y: 22)

                            // Running glow at right edge
                            if isRunning {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(colors: [color.opacity(0), color.opacity(0.4)],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: min(segW, 30), height: 20)
                                    .offset(x: x + segW - min(segW, 30), y: 22)
                            }

                            // Chip above segment
                            if segW > 40 {
                                let namePrefix = segW > 90 ? String(entry.projectName.prefix(10)) : ""
                                let label = isRunning
                                    ? "▶ \(durStr)"
                                    : (namePrefix.isEmpty ? durStr : "\(namePrefix)  \(durStr)")
                                Text(label)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(color)
                                    .lineLimit(1)
                                    .offset(x: x + 4, y: 5)
                            }
                        }
                    }
                }
                .frame(height: 44)

                // ── Time axis ───────────────────────────────────────────
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        ForEach(hourMarks.indices, id: \.self) { i in
                            let x = CGFloat(frac(hourMarks[i])) * w
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 1, height: 4)
                                .offset(x: x)
                            Text(Self.hourFmt.string(from: hourMarks[i]))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(theme.tertiaryText)
                                .offset(x: max(0, x - 13), y: 5)
                        }
                    }
                }
                .frame(height: 16)
            }
        }
    }
}
