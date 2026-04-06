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

    @State private var showingCustomize = false

    private var accentColor: Color { theme.accentText }

    // Visible tiles in user-defined order
    private var orderedVisibleTiles: [HomeTileID] {
        state.homeTileOrder.filter { state.homeTileVisible.contains($0) }
    }

    // Split into rows of 3
    private var tileRows: [[HomeTileID]] {
        stride(from: 0, to: orderedVisibleTiles.count, by: 3).map {
            Array(orderedVisibleTiles[$0 ..< min($0 + 3, orderedVisibleTiles.count)])
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
            // Use Grid for equal row heights
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(tileRows.indices, id: \.self) { rowIndex in
                    GridRow {
                        let row = tileRows[rowIndex]
                        ForEach(row) { tileID in
                            tileView(for: tileID)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        // Fill missing columns so layout stays aligned
                        if row.count < 3 {
                            ForEach(0 ..< (3 - row.count), id: \.self) { _ in
                                Color.clear
                            }
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
                .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 12))
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
                            .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 11, weight: .medium))
                        Text("Bearbeiten")
                            .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cost Today Card

    private var costTodayCard: some View {
        let budget = state.settings.budget
        let weekLimit = state.settings.claudeWeeklyCostLimit
        let effectiveWeekLimit = weekLimit > 0 ? weekLimit : budget
        let weekPct: Double = effectiveWeekLimit > 0 ? min(1.0, state.localWeekCost / effectiveWeekLimit) : 0
        let barColor: Color = weekPct > 0.9 ? .red : weekPct > 0.7 ? .orange : theme.accentFull

        return HomeTile(title: "Kosten Heute", icon: "eurosign.circle.fill", iconColor: .orange, theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fmt(state.localTodayCost))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("Heute")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diese Woche")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(state.fmt(state.localWeekCost))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(barColor)
                    }
                    if effectiveWeekLimit > 0 {
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
                        Text("Limit: \(state.fmt(effectiveWeekLimit))")
                            .font(.system(size: 10))
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
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.orange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(theme.primaryText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if let s = session {
                                            Text(s.preview.isEmpty ? "Kein Vorschau-Text" : s.preview)
                                                .font(.system(size: 10))
                                                .foregroundStyle(theme.tertiaryText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        } else {
                                            Text("\(project.sessions.count) Sessions")
                                                .font(.system(size: 10))
                                                .foregroundStyle(theme.tertiaryText)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
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
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(theme.primaryText)
                                            .lineLimit(1)
                                        Text(session.kind.isEmpty ? "claude" : session.kind)
                                            .font(.system(size: 10))
                                            .foregroundStyle(theme.tertiaryText)
                                    }
                                    Spacer()
                                    Text(session.startedAt, style: .relative)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
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
                                .font(.system(size: 10))
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
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(1)
                                Spacer()
                                if agent.isActive {
                                    Text("aktiv")
                                        .font(.system(size: 9, weight: .semibold))
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
                            .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 10))
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
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diese Woche")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(formatTokens(weekIn) + " tok")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
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
                .font(.system(size: 11))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
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
                        .font(.system(size: 11))
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
                        .font(.system(size: 12))
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
