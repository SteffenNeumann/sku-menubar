import SwiftUI
import Charts

// MARK: - Statistics Dashboard Section

/// Two-column layout that proposes the same height (max of both columns) to every child.
private struct EqualHeightHStack: Layout {
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let n = CGFloat(subviews.count)
        let colWidth = max(0, ((proposal.width ?? 0) - spacing * (n - 1)) / n)
        let maxH = subviews.map { $0.sizeThatFits(.init(width: colWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: maxH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let n = CGFloat(subviews.count)
        let colWidth = max(0, (bounds.width - spacing * (n - 1)) / n)
        let colProposal = ProposedViewSize(width: colWidth, height: bounds.height)
        for (i, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (colWidth + spacing), y: bounds.minY),
                      anchor: .topLeading, proposal: colProposal)
        }
    }
}

struct StatisticsDashboardSection: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var hoveredValue: (label: String, amount: Double)?

    // MARK: Computed data

    private var availableYears: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((max(2024, y - 2)...y))
    }

    private var months: [MonthlyUsage] { state.historicalMonths }
    private var activeMonths: [MonthlyUsage] { months.filter { $0.total > 0 } }

    /// Daily Claude costs — prefers Anthropic API, falls back to local CLI.
    private var claudeDailyForStats: [String: Double] {
        state.claudeYearDailyByDate.isEmpty ? state.localDailyByDate : state.claudeYearDailyByDate
    }

    /// Extra Claude cost for a given Copilot month (keyed "yyyy-MM").
    private func claudeCostForMonth(_ monthId: String) -> Double {
        claudeDailyForStats
            .filter { $0.key.hasPrefix(monthId) }
            .values.reduce(0, +)
    }

    /// Combined (Copilot + Claude) total for the year.
    private var yearTotal: Double {
        months.reduce(0) { $0 + $1.total + claudeCostForMonth($1.id) }
    }

    private var avgMonthly: Double { activeMonths.isEmpty ? 0 : yearTotal / Double(activeMonths.count) }
    private var peakMonth: MonthlyUsage? { months.max(by: { $0.total + claudeCostForMonth($0.id) < $1.total + claudeCostForMonth($1.id) }) }
    private var cheapestMonth: MonthlyUsage? { activeMonths.min(by: { $0.total + claudeCostForMonth($0.id) < $1.total + claudeCostForMonth($1.id) }) }

    private var claudeConfigured: Bool { !state.settings.anthropicAdminKey.isEmpty || !claudeDailyForStats.isEmpty }

    private var overBudgetCount: Int {
        guard state.settings.budget > 0 else { return 0 }
        return activeMonths.filter { $0.total + claudeCostForMonth($0.id) > state.settings.budget }.count
    }

    private var trendData: (last: MonthlyUsage, prev: MonthlyUsage, diff: Double, pct: Double)? {
        let sorted = activeMonths.sorted { $0.month < $1.month }
        guard sorted.count >= 2 else { return nil }
        let last = sorted[sorted.count - 1], prev = sorted[sorted.count - 2]
        let lastCombined = last.total + claudeCostForMonth(last.id)
        let prevCombined = prev.total + claudeCostForMonth(prev.id)
        let diff = lastCombined - prevCombined
        return (last, prev, diff, prevCombined > 0 ? abs(diff) / prevCombined * 100 : 0)
    }

    private var adherenceData: (under: Int, total: Int, rate: Double)? {
        guard state.settings.budget > 0, !activeMonths.isEmpty else { return nil }
        let under = activeMonths.filter { $0.total <= state.settings.budget }.count
        return (under, activeMonths.count, Double(under) / Double(activeMonths.count))
    }

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader


            if state.isLoadingHistory {
                ProgressView().scaleEffect(0.85).tint(accentColor)
                    .frame(maxWidth: .infinity).padding(24).mirrorCard()
            } else if activeMonths.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 28)).foregroundStyle(theme.tertiaryText)
                    Text("Keine Verlaufsdaten für \(String(selectedYear))")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity).padding(24).mirrorCard()
            } else {
                EqualHeightHStack(spacing: 14) {
                    // Linke Spalte: Summary + Chart (taller — sets the shared height)
                    VStack(alignment: .leading, spacing: 14) {
                        financialSummaryCard
                        yearChartCard
                    }

                    // Rechte Spalte: single combined card spanning full height
                    combinedRightCard
                }
            }
        }
        .task(id: selectedYear) {
            await state.loadHistory(year: selectedYear)
        }
    }

    // MARK: Section Header

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("Statistiken")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(availableYears, id: \.self) { y in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedYear = y }
                    } label: {
                        Text(String(y))
                            .font(.system(size: 13, weight: selectedYear == y ? .semibold : .regular))
                            .foregroundStyle(selectedYear == y ? .white : theme.secondaryText)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedYear == y ? accentColor : theme.cardSurface)
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(selectedYear == y ? accentColor : theme.cardBorder, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Financial Summary Card

    private var financialSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("JAHRESÜBERSICHT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText).kerning(0.8)
                    Text("Überblick \(String(selectedYear))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }
                Spacer()
                if claudeConfigured {
                    Text("Copilot + Claude")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                } else {
                    Text("Nur Copilot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
                if overBudgetCount > 0 {
                    Label("\(overBudgetCount)× über Budget", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            }

            HStack(spacing: 0) {
                summaryMetric(label: "GESAMT", value: fmt(yearTotal), valueColor: accentColor, icon: nil)
                Divider().frame(height: 36).opacity(0.25)
                summaryMetric(label: "Ø/MONAT", value: fmt(avgMonthly), valueColor: theme.secondaryText, icon: nil)
                Divider().frame(height: 36).opacity(0.25)
                summaryMetric(label: "HÖCHSTER MONAT", value: peakMonth.map(\.shortName) ?? "–",
                              valueColor: .orange, icon: "arrow.up.right")
                Divider().frame(height: 36).opacity(0.25)
                summaryMetric(label: "GÜNSTIGSTER", value: cheapestMonth.map(\.shortName) ?? "–",
                              valueColor: .green, icon: "arrow.down.right")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))
    }

    private func summaryMetric(label: String, value: String, valueColor: Color, icon: String?) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.8)
            HStack(spacing: 3) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.6)
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(valueColor) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Year Chart Card

    private var yearChartCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Monatsvergleich", systemImage: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.primaryText)
                    Text(claudeConfigured ? "Copilot + Claude kombiniert" : "Nur GitHub Copilot")
                        .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                if let hov = hoveredValue {
                    HStack(spacing: 4) {
                        Text(hov.label).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                        Text(fmt(hov.amount)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(accentColor)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if state.settings.budget > 0 {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.red.opacity(0.55)).frame(width: 12, height: 2)
                        Text("Budget \(fmt(state.settings.budget))").font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: hoveredValue?.label)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Chart {
                ForEach(months) { m in
                    let combined = m.total + claudeCostForMonth(m.id)
                    BarMark(x: .value("Monat", m.shortName), y: .value("Kosten", combined))
                        .foregroundStyle(hoveredValue?.label == m.shortName
                                         ? AnyShapeStyle(accentColor.opacity(0.95))
                                         : AnyShapeStyle(barGradient(for: m, combined: combined)))
                        .cornerRadius(5)
                }
                if avgMonthly > 0 {
                    RuleMark(y: .value("Ø", avgMonthly))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(accentColor.opacity(0.4))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("Ø \(fmtShort(avgMonthly))").font(.system(size: 11, weight: .medium)).foregroundStyle(accentColor.opacity(0.65))
                        }
                }
                if state.settings.budget > 0 {
                    RuleMark(y: .value("Budget", state.settings.budget))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundStyle(Color.red.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let d = val.as(Double.self) { Text(fmtShort(d)).font(.system(size: 12)).foregroundStyle(theme.secondaryText) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) { Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.secondaryText) }
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
                                if let name: String = proxy.value(atX: x, as: String.self),
                                   let m = months.first(where: { $0.shortName == name }) {
                                    hoveredValue = (name, m.total + claudeCostForMonth(m.id))
                                }
                            case .ended: hoveredValue = nil
                            }
                        }
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))
    }

    // MARK: Combined Right Card (Trend + Budget-Einhaltung in one card)

    @ViewBuilder
    private var combinedRightCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Trend section
            if let td = trendData {
                let isUp = td.diff > 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("MONATS-TREND").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.8)
                        if claudeConfigured {
                            Text("Copilot + Claude")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("\(td.prev.shortName) → \(td.last.shortName) Shift").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(isUp ? "+" : "")\(fmt(td.diff))").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(isUp ? .red : .green).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        let recent = Array(activeMonths.sorted { $0.month < $1.month }.suffix(4))
                        let maxV = recent.map { $0.total + claudeCostForMonth($0.id) }.max() ?? 1
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(recent) { m in
                                let combinedM = m.total + claudeCostForMonth(m.id)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(m.id == td.last.id ? accentColor : accentColor.opacity(0.3))
                                    .frame(width: 6, height: max(4, CGFloat(combinedM/maxV) * 28))
                            }
                        }.frame(height: 28, alignment: .bottom)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up" : "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(isUp ? .red : .green)
                        Text(String(format: "%.0f%% %@", td.pct, isUp ? "Anstieg" : "Rückgang")).font(.system(size: 12, weight: .medium)).foregroundStyle(isUp ? .red : .green)
                    }
                }
                .padding(14)
            }

            // Divider between sections
            if trendData != nil && adherenceData != nil {
                Divider().opacity(0.25).padding(.horizontal, 14)
            }

            // Adherence section
            if let ad = adherenceData {
                let rateColor: Color = ad.rate >= 0.8 ? .green : ad.rate >= 0.5 ? .orange : .red
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUDGET-EINHALTUNG").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.8)
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(theme.cardBorder, lineWidth: 8)
                            Circle().trim(from: 0, to: ad.rate)
                                .stroke(AngularGradient(
                                    colors: ad.rate >= 0.8 ? [.green, .teal] : ad.rate >= 0.5 ? [.orange, .yellow] : [.red, .orange],
                                    center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: ad.rate)
                            Text("\(Int(ad.rate * 100))%").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(rateColor)
                        }
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ad.under) von \(ad.total) Monaten im Budget").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.primaryText)
                            if state.settings.budget > 0 {
                                Text("Limit: \(fmt(state.settings.budget))/Monat").font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.cardBorder)
                            Capsule().fill(rateColor).frame(width: geo.size.width * ad.rate)
                                .animation(.spring(response: 0.5), value: ad.rate)
                        }
                    }.frame(height: 3)
                }
                .padding(14)
            }

            // Spacer fills the remaining height so card stretches to match left column
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))
    }

    // MARK: Helpers

    private func barGradient(for month: MonthlyUsage, combined: Double) -> LinearGradient {
        let over = state.settings.budget > 0 && combined > state.settings.budget
        return over
            ? LinearGradient(colors: [.red.opacity(0.45), .orange.opacity(0.85)],   startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [.purple.opacity(0.45), .indigo.opacity(0.9)], startPoint: .bottom, endPoint: .top)
    }

    private func fmt(_ v: Double) -> String { state.fmt(v) }
    private func fmtShort(_ v: Double) -> String {
        let s = state.currencySymbol
        let val = state.settings.currency == "EUR" ? v * state.settings.eurRate : v
        return val >= 100 ? s + String(format: "%.0f", val)
             : val >= 1   ? s + String(format: "%.1f", val)
             :               s + String(format: "%.2f", val)
    }
}
