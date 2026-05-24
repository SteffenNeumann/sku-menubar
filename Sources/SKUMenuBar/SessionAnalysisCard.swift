import SwiftUI
import Charts

/// Full-width HomeView tile showing session-level token usage analysis for today.
/// Displays three columns (Sessions, MCP-Server, Model-Mix) plus a drilldown bar chart.
struct SessionAnalysisCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var selectedSessionId: String? = nil
    @State private var hoveredBar: String? = nil
    @State private var lastRefresh: Date? = nil

    private var data: SessionAnalysisData { state.sessionAnalysis }
    private var sessions: [SessionTokenSummary] { data.todaySessions.sorted { $0.totalTokens > $1.totalTokens } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            if state.sessionAnalysisIsLoading && data.todaySessions.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }
                    .padding(.vertical, 32)
            } else if data.todaySessions.isEmpty {
                emptyState
                    .padding(.vertical, 24)
            } else {
                // Summary
                summaryRow
                    .padding(.horizontal, 16).padding(.bottom, 12)

                // Three columns — each gets equal width via maxWidth:.infinity
                HStack(alignment: .top, spacing: 10) {
                    sessionsColumn
                        .frame(maxWidth: .infinity)
                    mcpServerColumn
                        .frame(maxWidth: .infinity)
                    modelMixColumn
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)

                Divider().opacity(0.2).padding(.horizontal, 16)

                // Drilldown chart
                drilldownSection
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            }

            // Footer
            footerRow
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
        }
        .padding(.bottom, 12)   // visible gap between card and window edge
        .mirrorCard()
        .onAppear {
            if data.todaySessions.isEmpty && !state.sessionAnalysisIsLoading {
                lastRefresh = Date()
                Task { await state.loadSessionAnalysis() }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.55, saturation: 0.65, brightness: 0.85),
                                 Color(hue: 0.62, saturation: 0.7, brightness: 0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Session-Analyse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Token-Nutzung nach Sessions heute")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
            Spacer()
            if state.sessionAnalysisIsLoading {
                ProgressView().scaleEffect(0.6)
            }
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        let sessionCount  = data.todaySessions.count
        let paidTokens    = data.todayPaidTokens   // matches Token-Verbrauch tile
        let totalTokens   = data.todayTotalTokens  // includes cache
        let cacheTokens   = totalTokens - paidTokens
        let totalCost     = data.todayTotalCost
        let spawns        = data.totalAgentSpawns

        return HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.accentIcon)

            Group {
                Text("\(sessionCount) Sessions")
                Text("\u{00B7}").foregroundStyle(theme.tertiaryText)
                // Primary: paid tokens (= same as Token-Verbrauch tile)
                Text(fmtTokens(paidTokens) + " tok")
                    .foregroundStyle(theme.primaryText)
                if cacheTokens > 0 {
                    Text("+("+fmtTokens(cacheTokens)+" Cache)")
                        .foregroundStyle(theme.tertiaryText)
                }
                Text("\u{00B7}").foregroundStyle(theme.tertiaryText)
                Text("~" + state.fmt(totalCost, decimals: 2))
                if spawns > 0 {
                    Text("\u{00B7}").foregroundStyle(theme.tertiaryText)
                    Text("\(spawns) Agent-Spawns")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(theme.accentIcon.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sessions Column

    private var sessionsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader(icon: "terminal.fill", label: "Sessions", color: theme.statusGreen)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(sessions.prefix(8)) { session in
                    sessionRow(session)
                }
            }

            if sessions.count > 8 {
                Text("+\(sessions.count - 8) weitere")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.top, 6)
            }

            Spacer(minLength: 4)

            // Column footer
            HStack(spacing: 4) {
                Text("\(sessions.count) Sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
                Text(fmtTokens(data.todayTotalTokens) + " total")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.top, 6)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.rowBg))
    }

    private func sessionRow(_ session: SessionTokenSummary) -> some View {
        // Use paid tokens for percentage (matches Token-Verbrauch tile scale)
        let base = data.todayPaidTokens > 0 ? data.todayPaidTokens : 1
        let pct = Double(session.paidTokens) / Double(base) * 100
        let isSelected = selectedSessionId == session.id

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedSessionId = isSelected ? nil : session.id
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(sessionDotColor(session.entrypoint))
                    .frame(width: 7, height: 7)

                // Name + start time stacked
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? theme.accentText : theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fmtStartTime(session.firstTimestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText.opacity(0.7))
                }

                Spacer(minLength: 2)

                // Fixed-width badge area prevents layout shifts
                HStack(spacing: 4) {
                    Text(entrypointLabel(session.entrypoint))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(sessionDotColor(session.entrypoint))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(sessionDotColor(session.entrypoint).opacity(0.12), in: Capsule())

                    if session.agentSpawns > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "cpu")
                                .font(.system(size: 8))
                            Text("\(session.agentSpawns)")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1), in: Capsule())
                    } else {
                        // Placeholder to keep width stable when no agent badge
                        Color.clear.frame(width: 20, height: 16)
                    }
                }
                .frame(minWidth: 72, alignment: .trailing)

                VStack(alignment: .trailing, spacing: 1) {
                    // Primary: paid tokens (matches Token-Verbrauch tile)
                    Text(fmtTokens(session.paidTokens))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                    HStack(spacing: 3) {
                        Text(String(format: "%.0f%%", pct))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                        if session.cacheReadTokens > 0 {
                            Text("+\(fmtTokens(session.cacheReadTokens))c")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? theme.accentIcon.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? theme.accentIcon.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - MCP Server Column

    private var mcpServerColumn: some View {
        let serverTotals = data.mcpServerTotals
            .map { (name: $0.key, calls: $0.value) }
            .sorted { $0.calls > $1.calls }

        let mcpColors: [Color] = [.blue, .cyan, .teal, .indigo, .purple, .mint]

        return VStack(alignment: .leading, spacing: 0) {
            columnHeader(icon: "server.rack", label: "MCP-Server", color: .blue)
                .padding(.bottom, 8)

            if serverTotals.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    Text("Keine MCP-Aufrufe")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                let totalMCP = serverTotals.reduce(0) { $0 + $1.calls }

                VStack(spacing: 5) {
                    ForEach(Array(serverTotals.prefix(6).enumerated()), id: \.element.name) { idx, server in
                        let color = mcpColors[idx % mcpColors.count]
                        mcpServerRow(name: server.name, calls: server.calls, color: color)
                    }
                }

                if serverTotals.count > 6 {
                    Text("+\(serverTotals.count - 6) weitere")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.top, 4)
                }

                Spacer(minLength: 4)

                // Column footer
                let mcpPct = data.todayTotalTokens > 0
                    ? Double(totalMCP) / Double(data.todayTotalTokens) * 100
                    : 0
                HStack(spacing: 4) {
                    Text("\(totalMCP) Aufrufe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                    if mcpPct > 0 {
                        Text(String(format: "%.0f%% MCP", mcpPct))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.rowBg))
    }

    private func mcpServerRow(name: String, calls: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(cleanServerName(name))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)   // full name on hover
            Spacer(minLength: 2)
            Text("\(calls)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text("Aufrufe")
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.04)))
    }

    // MARK: - Model Mix Column

    private var modelMixColumn: some View {
        let modelTotals = data.modelTotals
            .map { (model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        let totalModelTokens = modelTotals.reduce(0) { $0 + $1.tokens }
        let dominantModel = modelTotals.first

        return VStack(alignment: .leading, spacing: 0) {
            columnHeader(icon: "cpu", label: "Model-Mix", color: .purple)
                .padding(.bottom, 8)

            if modelTotals.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    Text("Keine Daten")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Donut chart
                HStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        Chart {
                            ForEach(modelTotals, id: \.model) { entry in
                                SectorMark(
                                    angle: .value("Tokens", entry.tokens),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(modelColor(entry.model))
                                .cornerRadius(3)
                            }
                        }
                        .chartLegend(.hidden)
                        .frame(width: 80, height: 80)

                        // Center label
                        if let dominant = dominantModel {
                            VStack(spacing: 0) {
                                Text(modelShortName(dominant.model))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(modelColor(dominant.model))
                                if totalModelTokens > 0 {
                                    Text(String(format: "%.0f%%", Double(dominant.tokens) / Double(totalModelTokens) * 100))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                // Legend
                VStack(spacing: 4) {
                    ForEach(modelTotals, id: \.model) { entry in
                        let pct = totalModelTokens > 0
                            ? Double(entry.tokens) / Double(totalModelTokens) * 100
                            : 0
                        HStack(spacing: 6) {
                            Circle()
                                .fill(modelColor(entry.model))
                                .frame(width: 7, height: 7)
                            Text(modelShortName(entry.model))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Spacer(minLength: 2)
                            Text(String(format: "%.0f%%", pct))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(modelColor(entry.model))
                            Text(fmtTokens(entry.tokens))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                }

                Spacer(minLength: 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.rowBg))
    }

    // MARK: - Drilldown Section

    private var drilldownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sessionId = selectedSessionId,
               let session = data.todaySessions.first(where: { $0.id == sessionId }) {
                // Drilldown: selected session tool breakdown
                drilldownSessionDetail(session)
            } else {
                // Overview: all sessions bar chart
                drilldownOverview
            }
        }
    }

    private var drilldownOverview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                Text("Session antippen fuer Tool-Details")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let hov = hoveredBar,
                   let session = sessions.first(where: { $0.id == hov }) {
                    Text(fmtTokens(session.totalTokens) + " tok")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accentText)
                        .transition(.opacity)
                }
            }

            if sessions.isEmpty {
                Text("Keine Daten")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    ForEach(sessions) { session in
                        BarMark(
                            x: .value("Session", session.displayName),
                            y: .value("Tokens", session.totalTokens)
                        )
                        .foregroundStyle(
                            hoveredBar == session.id
                                ? AnyShapeStyle(theme.accentIcon.opacity(0.95))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [theme.accentIcon.opacity(0.4), theme.accentIcon.opacity(0.8)],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                        )
                        .cornerRadius(4)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let d = val.as(Int.self) {
                                Text(fmtTokens(d))
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            if let s = val.as(String.self) {
                                Text(s)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let x = loc.x - (proxy.plotFrame.map { geo[$0].origin.x } ?? 0)
                                    if let lbl: String = proxy.value(atX: x, as: String.self) {
                                        hoveredBar = sessions.first(where: { $0.displayName == lbl })?.id
                                    }
                                case .ended:
                                    hoveredBar = nil
                                }
                            }
                            .onTapGesture { location in
                                let x = location.x - (proxy.plotFrame.map { geo[$0].origin.x } ?? 0)
                                if let lbl: String = proxy.value(atX: x, as: String.self),
                                   let session = sessions.first(where: { $0.displayName == lbl }) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        selectedSessionId = session.id
                                    }
                                }
                            }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.rowBg))
    }

    private func drilldownSessionDetail(_ session: SessionTokenSummary) -> some View {
        let toolItems = session.toolCalls
            .map { (tool: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        let mcpServerNames = Set(session.mcpServers.keys)

        return VStack(alignment: .leading, spacing: 8) {
            // Back button + session info
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedSessionId = nil
                        hoveredBar = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Alle Sessions")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(theme.accentText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.accentIcon.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(session.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    HStack(spacing: 6) {
                        Text(fmtTokens(session.totalTokens) + " tok")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                        if session.duration > 0 {
                            Text(fmtDuration(session.duration))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }
            }

            // Tool calls bar chart
            if toolItems.isEmpty {
                Text("Keine Tool-Aufrufe")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                    Text("Tool-Aufrufe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    if let hov = hoveredBar,
                       let item = toolItems.first(where: { $0.tool == hov }) {
                        Text("\(item.count)x")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accentText)
                            .transition(.opacity)
                    }
                }

                Chart {
                    ForEach(toolItems.prefix(12), id: \.tool) { item in
                        BarMark(
                            x: .value("Tool", item.tool),
                            y: .value("Aufrufe", item.count)
                        )
                        .foregroundStyle(
                            hoveredBar == item.tool
                                ? AnyShapeStyle(theme.accentIcon.opacity(0.95))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [theme.accentIcon.opacity(0.35), theme.accentIcon.opacity(0.75)],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                        )
                        .cornerRadius(3)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let d = val.as(Int.self) {
                                Text("\(d)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            if let s = val.as(String.self) {
                                Text(s)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let x = loc.x - (proxy.plotFrame.map { geo[$0].origin.x } ?? 0)
                                    if let lbl: String = proxy.value(atX: x, as: String.self) {
                                        hoveredBar = toolItems.first(where: { $0.tool == lbl })?.tool
                                    }
                                case .ended:
                                    hoveredBar = nil
                                }
                            }
                    }
                }
                .frame(height: 130)

                // Tool list with MCP highlights
                Divider().opacity(0.15).padding(.vertical, 4)

                VStack(spacing: 3) {
                    ForEach(toolItems.prefix(10), id: \.tool) { item in
                        let isMCP = mcpServerNames.contains(where: { item.tool.lowercased().contains($0.lowercased()) })
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isMCP ? Color.blue : theme.tertiaryText.opacity(0.4))
                                .frame(width: 5, height: 5)
                            Text(item.tool)
                                .font(.system(size: 11, weight: isMCP ? .semibold : .regular))
                                .foregroundStyle(isMCP ? .blue : theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if isMCP {
                                Text("MCP")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                            Spacer()
                            Text("\(item.count)x")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                    }
                }

                if toolItems.count > 10 {
                    Text("+\(toolItems.count - 10) weitere Tools")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.rowBg))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.tertiaryText.opacity(0.5))
            Text("Keine Sessions heute")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
            Text("Session-Daten werden nach der ersten Claude-Nutzung angezeigt.")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            if let refresh = lastRefresh {
                Text("Aktualisiert \(relativeTime(refresh))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
            Spacer()
            Button {
                lastRefresh = Date()
                Task { await state.loadSessionAnalysis() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .rotationEffect(.degrees(state.sessionAnalysisIsLoading ? 360 : 0))
                    .animation(
                        state.sessionAnalysisIsLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: state.sessionAnalysisIsLoading
                    )
            }
            .buttonStyle(.plain)
            .help("Session-Analyse aktualisieren")
        }
    }

    // MARK: - Column Header

    private func columnHeader(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.6)
            Spacer()
        }
    }

    // MARK: - Formatting Helpers

    private func fmtTokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
        : n >= 1_000   ? String(format: "%.0fK", Double(n) / 1_000)
        : "\(n)"
    }

    private func sessionDotColor(_ entrypoint: String) -> Color {
        switch entrypoint {
        case "cli":         return theme.statusGreen
        case "sdk-cli":     return .purple
        default:            return .blue
        }
    }

    private func entrypointLabel(_ entrypoint: String) -> String {
        switch entrypoint {
        case "cli":     return "CLI"
        case "sdk-cli": return "SDK"
        default:        return "Desktop"
        }
    }

    private func modelColor(_ model: String) -> Color {
        let m = model.lowercased()
        if m.contains("opus")  { return .purple }
        if m.contains("haiku") { return .teal }
        return .blue // sonnet
    }

    private func modelShortName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus")  { return "Opus" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("sonnet") { return "Sonnet" }
        return model
    }

    private func cleanServerName(_ raw: String) -> String {
        // Keep up to 18 chars; SwiftUI's .truncationMode(.middle) handles the rest
        if raw.count > 18 { return String(raw.prefix(9)) + "\u{2026}" + String(raw.suffix(8)) }
        return raw.capitalized
    }

    private func fmtDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let hrs  = mins / 60
        if hrs > 0 {
            return "\(hrs)h \(mins % 60)m"
        } else if mins > 0 {
            return "\(mins)m"
        } else {
            return "<1m"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "vor \(max(1, diff))s" }
        let mins = diff / 60
        if mins < 60 { return "vor \(mins) Min" }
        let hrs = mins / 60
        return "vor \(hrs)h"
    }

    /// Short clock time for the session start, e.g. "14:32"
    private func fmtStartTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
