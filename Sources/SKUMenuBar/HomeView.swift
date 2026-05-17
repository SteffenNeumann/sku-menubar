import SwiftUI

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

    private var accentColor: Color { theme.accentText }

    // Visible tiles in user-defined order
    private var orderedVisibleTiles: [HomeTileID] {
        state.homeTileOrder.filter { state.homeTileVisible.contains($0) }
    }

    // Normal tiles (3-column rows) and full-width tiles (own row at bottom)
    private var normalTiles: [HomeTileID] {
        orderedVisibleTiles.filter { !$0.isFullWidth }
    }
    private var fullWidthTiles: [HomeTileID] {
        orderedVisibleTiles.filter { $0.isFullWidth }
    }
    private var tileRows: [[HomeTileID]] {
        stride(from: 0, to: normalTiles.count, by: 3).map {
            Array(normalTiles[$0 ..< min($0 + 3, normalTiles.count)])
        }
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
    }

    // MARK: - Tile Grid

    @ViewBuilder
    private var tileGrid: some View {
        if orderedVisibleTiles.isEmpty {
            emptyDashboard
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                // Normal 3-column rows
                ForEach(tileRows.indices, id: \.self) { rowIndex in
                    GridRow {
                        let row = tileRows[rowIndex]
                        ForEach(row) { tileID in
                            tileView(for: tileID)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if row.count < 3 {
                            ForEach(0 ..< (3 - row.count), id: \.self) { _ in
                                Color.clear
                            }
                        }
                    }
                }
                // Full-width tiles — each spans all 3 columns
                ForEach(fullWidthTiles) { tileID in
                    GridRow {
                        tileView(for: tileID)
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(3)
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
                            Circle().fill(.green.opacity(0.25)).frame(width: 10, height: 10)
                            Circle().fill(.green).frame(width: 6, height: 6)
                        }
                        Text("\(state.activeSessions.count) aktiv")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(.green.opacity(0.25), lineWidth: 1))
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
                quickActionButton(label: "Neuer Chat",    icon: "bubble.left.and.bubble.right.fill", color: .green)  { selectedSection = .chat }
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
        let barColor: Color = weekPct > 0.9 ? .red : weekPct > 0.7 ? .orange : theme.accentFull

        return HomeTile(title: "Kosten Heute", icon: "eurosign.circle.fill", iconColor: .orange, theme: theme) {
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

        return HomeTile(title: "Letzte Projekte", icon: "clock.arrow.circlepath", iconColor: .orange, theme: theme) {
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
                                            .fill(Color.orange.opacity(0.12))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.orange)
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
        HomeTile(title: "Aktive Sessions", icon: "terminal.fill", iconColor: .green, theme: theme) {
            VStack(alignment: .leading, spacing: 0) {
                if state.activeSessions.isEmpty {
                    emptyState(icon: "terminal", text: "Keine aktiven Prozesse.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(state.activeSessions.prefix(4)) { session in
                            Button {
                                state.pendingChatSession = session.sessionId
                                state.pendingChatWorkingDirectory = session.cwd
                                selectedSection = .chat
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(.green.opacity(0.20)).frame(width: 8, height: 8)
                                        Circle().fill(.green).frame(width: 5, height: 5)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session.cwdDisplay)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(theme.primaryText)
                                            .lineLimit(1)
                                        Text(session.kind.isEmpty ? "claude" : session.kind)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.tertiaryText)
                                    }
                                    Spacer()
                                    Text(session.startedAt, style: .relative)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                        if state.activeSessions.count > 4 {
                            Text("+ \(state.activeSessions.count - 4) weitere")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
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
                        agentStat(value: "\(activeAgents.count)", label: "Aktiv", color: .green)
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
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.12), in: Capsule())
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
                            .background(theme.accentFull.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                                .fill(theme.accentFull)
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
                    // Period chips + date range button
                    HStack(spacing: 4) {
                        ForEach(TMetricPeriod.allCases, id: \.self) { p in
                            let active = !state.tmetricIsCustomRange && state.tmetricPeriod == p
                            Text(p.label)
                                .font(.system(size: 12, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Color.indigo : theme.secondaryText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(active ? Color.indigo.opacity(0.13) : Color.clear,
                                            in: Capsule())
                                .contentShape(Capsule())
                                .onTapGesture {
                                    state.tmetricIsCustomRange = false
                                    state.tmetricPeriod = p
                                }
                        }
                        Spacer(minLength: 0)
                        Button {
                            tmetricDraftFrom = state.tmetricIsCustomRange
                                ? state.tmetricCustomFrom
                                : Calendar.current.startOfDay(for: Date())
                            tmetricDraftTo = state.tmetricIsCustomRange
                                ? state.tmetricCustomTo
                                : Date()
                            showTMetricDatePicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11, weight: .medium))
                                if state.tmetricIsCustomRange {
                                    Text(tmetricCustomRangeLabel)
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundStyle(state.tmetricIsCustomRange ? Color.indigo : theme.tertiaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(state.tmetricIsCustomRange ? Color.indigo.opacity(0.13) : Color.clear,
                                        in: Capsule())
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

                    if state.tmetricIsLoading && state.tmetricProjects.isEmpty {
                        HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }
                            .padding(.top, 12)
                    } else if let err = state.tmetricError {
                        emptyState(icon: "exclamationmark.triangle", text: err)
                    } else if state.tmetricProjects.isEmpty {
                        emptyState(icon: "timer", text: state.tmetricIsCustomRange
                            ? "Keine Zeit in diesem Zeitraum."
                            : state.tmetricPeriod.emptyText)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(state.tmetricProjects.prefix(8)) { project in
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.indigo.opacity(0.12))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.indigo)
                                    }
                                    Text(project.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(project.formattedDuration)
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(.indigo)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }

                        Spacer(minLength: 0)

                        HStack {
                            if let updated = state.tmetricLastUpdated {
                                let fmt = RelativeDateTimeFormatter()
                                Text("Aktualisiert \(fmt.localizedString(for: updated, relativeTo: Date()))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            Spacer()
                            Button {
                                Task { await state.refreshTMetric(force: true) }
                            } label: {
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
                }       // end outer else (token not empty)
            }
        }
    }

    private var tmetricCustomRangeLabel: String {
        let df = DateFormatter()
        df.dateFormat = "d.M."
        return "\(df.string(from: state.tmetricCustomFrom))–\(df.string(from: state.tmetricCustomTo))"
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
