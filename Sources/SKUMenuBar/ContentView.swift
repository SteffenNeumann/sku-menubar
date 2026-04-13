import SwiftUI
import AppKit

// MARK: - NSVisualEffect background (blurs the desktop behind the panel)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Reusable Glass Card modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var refreshRotation: Double = 0

    // MARK: - Derived costs

    private var copilotMonthCost: Double {
        state.monthByProduct
            .filter { $0.key.lowercased().contains("copilot") }
            .values.reduce(0, +)
    }

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var claudeConfigured: Bool { !state.settings.anthropicAdminKey.isEmpty }

    // Budget helpers
    private var dailyRef: Double {
        guard state.settings.budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.settings.budget / Double(days)
    }
    private var copilotPct: Double {
        state.settings.budget > 0 ? min(1, copilotMonthCost / state.settings.budget) : 0
    }
    private var claudePct: Double {
        if state.settings.claudeWeeklyCostLimit > 0 {
            let monthly = state.settings.claudeWeeklyCostLimit * 4.33
            return min(1, state.claudeMonthCost / monthly)
        }
        return state.settings.budget > 0 ? min(1, state.claudeMonthCost / state.settings.budget) : 0
    }
    private var remainPct: Double { state.settings.budget > 0 ? state.remain / state.settings.budget : 1 }
    private func consumedColor(_ p: Double) -> Color { p > 0.9 ? .red : p > 0.75 ? .orange : accentColor }
    private func remainColor(_ p: Double) -> Color   { p < 0.2 ? .red : p < 0.4 ? .orange : .green }

    // MARK: - Copilot chart data (from historicalMonths)

    private var currentMonthId: String {
        let cal = Calendar.current
        let now = Date()
        return String(format: "%04d-%02d",
            cal.component(.year,  from: now),
            cal.component(.month, from: now))
    }

    private var copilotMonthlyData: [(id: String, label: String, value: Double)] {
        let cur = currentMonthId
        return state.historicalMonths
            .filter { $0.total > 0 || $0.id == cur }
            .map { m in
                (id: m.id, label: m.shortName, value: m.total)
            }
    }

    private var copilotDailyData: [String: Double] {
        var result: [String: Double] = [:]
        for m in state.historicalMonths {
            for (dateStr, amount) in m.byDay {
                result[dateStr, default: 0] += amount
            }
        }
        return result
    }

    // MARK: - Combined (Copilot + Claude) chart data

    private var combinedMonthlyData: [(id: String, label: String, value: Double)] {
        var totals: [String: Double] = [:]
        for item in copilotMonthlyData { totals[item.id, default: 0] += item.value }
        for item in claudeMonthlyData  { totals[item.id, default: 0] += item.value }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale     = Locale(identifier: "de_DE")
        return totals.compactMap { (monthId, value) -> (id: String, label: String, value: Double)? in
            guard let date = df.date(from: monthId) else { return nil }
            let label = DateFormatter().shortMonthSymbols[Calendar.current.component(.month, from: date) - 1]
            return (id: monthId, label: label, value: value)
        }
        .filter { $0.value > 0 || $0.id == currentMonthId }
        .sorted { $0.id < $1.id }
    }

    private var combinedDailyData: [String: Double] {
        var result: [String: Double] = [:]
        for (k, v) in copilotDailyData   { result[k, default: 0] += v }
        for (k, v) in claudeDailySource  { result[k, default: 0] += v }
        return result
    }

    // MARK: - Claude chart data (from claudeYearDailyByDate)

    /// Local JSONL data for chart (consistent with sidebar estimates).
    /// API data is used only for Today/Week/Month summary cards.
    private var claudeDailySource: [String: Double] {
        state.localDailyByDate
    }

    private var claudeIsLocalSource: Bool { state.claudeYearDailyByDate.isEmpty }

    private var claudeMonthlyData: [(id: String, label: String, value: Double)] {
        var monthTotals: [String: Double] = [:]
        for (dateStr, cost) in claudeDailySource {
            let monthId = String(dateStr.prefix(7))
            monthTotals[monthId, default: 0] += cost
        }
        // Always include current month even if no data yet
        let cur = currentMonthId
        if monthTotals[cur] == nil { monthTotals[cur] = 0 }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale     = Locale(identifier: "de_DE")
        let shortDf   = DateFormatter()
        shortDf.locale = Locale(identifier: "de_DE")
        return monthTotals.compactMap { (monthId, value) -> (id: String, label: String, value: Double)? in
            guard let date = df.date(from: monthId) else { return nil }
            let label = shortDf.shortMonthSymbols[Calendar.current.component(.month, from: date) - 1]
            return (id: monthId, label: label, value: value)
        }
        .filter { $0.value > 0 || $0.id == cur }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {

                // -- Page title row --
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("Echtzeit-Verbrauch und Budget-Tracking.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Circle().fill(state.errorMsg != nil ? Color.red : Color.green)
                                .frame(width: 6, height: 6)
                            Text(state.errorMsg != nil ? "FEHLER" : "LIVE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(state.errorMsg != nil ? Color.red : Color.green)
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.errorMsg != nil ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(state.errorMsg != nil ? Color.red.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1))
                        )
                        Button {
                            withAnimation(.linear(duration: 0.6)) { refreshRotation += 360 }
                            Task {
                                await state.refresh()
                                await state.refreshClaude()
                                state.activeSessions = state.cliService.loadActiveSessions()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .rotationEffect(.degrees(refreshRotation))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8).fill(theme.cardSurface)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardBorder, lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)

                // Error banner
                if let err = state.errorMsg {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.system(size: 13)).foregroundStyle(theme.primaryText).lineLimit(3)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)))
                }

                // -- KPI Cards --
                if claudeConfigured {
                    HStack(spacing: 12) {
                        kpiCard(
                            label: "COPILOT",
                            icon: "person.fill.checkmark",
                            iconColor: .blue,
                            value: state.fmt(copilotMonthCost),
                            badge: "+\(Int(copilotPct * 100))%",
                            badgeColor: consumedColor(copilotPct),
                            pct: copilotPct, barColor: .blue,
                            sub: state.settings.budget > 0 ? "von \(state.fmt(state.settings.budget))" : "Kein Limit"
                        )
                        kpiCard(
                            label: "CLAUDE API",
                            icon: "sparkles",
                            iconColor: .purple,
                            value: state.fmt(state.claudeMonthCost),
                            badge: "+\(Int(claudePct * 100))%",
                            badgeColor: consumedColor(claudePct),
                            pct: claudePct, barColor: .purple,
                            sub: state.settings.claudeWeeklyCostLimit > 0
                                ? "Limit: \(state.fmt(state.settings.claudeWeeklyCostLimit))/Wo."
                                : "Kein Limit"
                        )
                        kpiCard(
                            label: "VERBLEIBEND",
                            icon: "building.columns.fill",
                            iconColor: remainColor(remainPct),
                            value: state.settings.budget > 0 ? state.fmt(state.remain) : "\u{2013}",
                            badge: "\(Int(remainPct * 100))%",
                            badgeColor: remainColor(remainPct),
                            pct: remainPct, barColor: remainColor(remainPct),
                            sub: state.settings.budget > 0 ? "Ziel: \(state.fmt(state.settings.budget))/Mo." : "Kein Budget"
                        )
                    }
                } else {
                    HStack(spacing: 12) {
                        kpiCard(
                            label: "DIESEN MONAT",
                            icon: "calendar",
                            iconColor: .blue,
                            value: state.fmt(state.monthCost),
                            badge: "+\(Int(state.monthPct * 100))%",
                            badgeColor: consumedColor(state.monthPct),
                            pct: state.monthPct, barColor: .blue,
                            sub: state.settings.budget > 0 ? "von \(state.fmt(state.settings.budget))" : "Kein Limit"
                        )
                        kpiCard(
                            label: "HEUTE",
                            icon: "calendar.badge.clock",
                            iconColor: accentColor,
                            value: state.fmt(state.todayCost),
                            badge: dailyRef > 0 ? "+\(Int(min(1, state.todayCost / dailyRef) * 100))%" : "\u{2013}",
                            badgeColor: accentColor,
                            pct: dailyRef > 0 ? min(1, state.todayCost / dailyRef) : 0,
                            barColor: accentColor,
                            sub: dailyRef > 0 ? "Limit: \(state.fmt(dailyRef))" : "Kein Limit"
                        )
                        kpiCard(
                            label: "VERBLEIBEND",
                            icon: "building.columns.fill",
                            iconColor: remainColor(remainPct),
                            value: state.settings.budget > 0 ? state.fmt(state.remain) : "\u{2013}",
                            badge: "\(Int(remainPct * 100))%",
                            badgeColor: remainColor(remainPct),
                            pct: remainPct, barColor: remainColor(remainPct),
                            sub: state.settings.budget > 0 ? "Ziel: \(state.fmt(state.settings.budget))/Mo." : "Kein Budget"
                        )
                    }
                }

                // -- Drill-down Charts --
                if claudeConfigured {
                    // Source charts side-by-side
                    HStack(alignment: .top, spacing: 12) {
                        DrilldownChartCard(
                            title:       "GitHub Copilot",
                            subtitle:    "Nur Copilot · GitHub Billing API",
                            icon:        "person.fill.checkmark",
                            accentColor: .blue,
                            monthlyData: copilotMonthlyData,
                            dailyData:   copilotDailyData,
                            fmtFn:       { state.fmt($0) },
                            isLoading:   state.isLoadingHistory
                        )
                        .frame(maxWidth: .infinity)

                        DrilldownChartCard(
                            title:       "Claude Code",
                            subtitle:    "Nur Claude · CLI (lokal)",
                            icon:        "sparkles",
                            accentColor: .purple,
                            monthlyData: claudeMonthlyData,
                            dailyData:   claudeDailySource,
                            fmtFn:       { state.fmt($0) },
                            isLoading:   state.claudeIsLoading,
                            errorMsg:    state.claudeError
                        )
                        .frame(maxWidth: .infinity)
                    }

                    // Combined total chart (full width)
                    DrilldownChartCard(
                        title:       "Gesamt",
                        subtitle:    "Copilot + Claude kombiniert",
                        icon:        "chart.bar.fill",
                        accentColor: accentColor,
                        monthlyData: combinedMonthlyData,
                        dailyData:   combinedDailyData,
                        fmtFn:       { state.fmt($0) },
                        isLoading:   state.isLoadingHistory || state.claudeIsLoading
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    DrilldownChartCard(
                        title:       "GitHub Copilot",
                        subtitle:    "Nur Copilot · GitHub Billing API",
                        icon:        "person.fill.checkmark",
                        accentColor: accentColor,
                        monthlyData: copilotMonthlyData,
                        dailyData:   copilotDailyData,
                        fmtFn:       { state.fmt($0) },
                        isLoading:   state.isLoadingHistory
                    )
                    .frame(maxWidth: .infinity)
                }

                // -- Statistics Section --
                Divider().opacity(0.2).padding(.vertical, 4)
                StatisticsDashboardSection()

                // Footer
                HStack {
                    if let t = state.lastUpdate {
                        Label(t.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                            .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 900)
            .padding(20)
            Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let year = Calendar.current.component(.year, from: Date())
            async let history: () = {
                if state.historicalMonths.isEmpty && !state.isLoadingHistory {
                    await state.loadHistory(year: year)
                }
            }()
            async let claude: () = {
                // Force-refresh Claude year data if not yet available
                if state.claudeYearDailyByDate.isEmpty && !state.claudeIsLoading
                    && !state.settings.anthropicAdminKey.isEmpty {
                    await state.refreshClaude(force: true)
                }
            }()
            _ = await (history, claude)
        }
    }

    // MARK: - KPI Card (uniform size)

    private func kpiCard(label: String, icon: String, iconColor: Color,
                         value: String, badge: String, badgeColor: Color,
                         pct: Double, barColor: Color, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .kerning(0.8)
                Spacer()
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12), in: Capsule())
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.5)
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.cardBorder)
                        Capsule().fill(barColor)
                            .frame(width: geo.size.width * max(0, min(1, pct)))
                            .animation(.spring(response: 0.5), value: pct)
                    }
                }
                .frame(height: 3)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))
    }
}
