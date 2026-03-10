import SwiftUI
import Charts

// MARK: - Drill navigation state

private enum DrillLevel: Equatable, Hashable {
    case year
    case month(String)       // monthId "yyyy-MM"
    case week(String, Int)   // monthId + weekOfYear
}

// MARK: - StatisticsView

struct StatisticsView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedYear: Int  = Calendar.current.component(.year, from: Date())
    @State private var drillLevel: DrillLevel = .year
    @State private var hoveredValue: (label: String, amount: Double)?

    // MARK: Convenience accessors

    private var availableYears: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((max(2024, y - 2)...y))
    }

    private var months: [MonthlyUsage] { state.historicalMonths }

    private var yearTotal:     Double { months.reduce(0) { $0 + $1.total } }
    private var activeMonths:  [MonthlyUsage] { months.filter { $0.total > 0 } }
    private var avgMonthly:    Double { activeMonths.isEmpty ? 0 : yearTotal / Double(activeMonths.count) }
    private var peakMonth:     MonthlyUsage? { months.max(by: { $0.total < $1.total }) }
    private var cheapestMonth: MonthlyUsage? { activeMonths.min(by: { $0.total < $1.total }) }

    private var overBudgetCount: Int {
        guard state.settings.budget > 0 else { return 0 }
        return activeMonths.filter { $0.total > state.settings.budget }.count
    }

    private var allProducts: [(name: String, amount: Double)] {
        var combined: [String: Double] = [:]
        for m in months { for (p, v) in m.byProduct { combined[p, default: 0] += v } }
        return combined.map { (name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    private var trendData: (last: MonthlyUsage, prev: MonthlyUsage, diff: Double, pct: Double)? {
        let sorted = activeMonths.sorted { $0.month < $1.month }
        guard sorted.count >= 2 else { return nil }
        let last = sorted[sorted.count - 1], prev = sorted[sorted.count - 2]
        let diff = last.total - prev.total
        return (last, prev, diff, prev.total > 0 ? abs(diff) / prev.total * 100 : 0)
    }

    private var adherenceData: (under: Int, total: Int, rate: Double)? {
        guard state.settings.budget > 0, !activeMonths.isEmpty else { return nil }
        let under = activeMonths.filter { $0.total <= state.settings.budget }.count
        return (under, activeMonths.count, Double(under) / Double(activeMonths.count))
    }

    // MARK: Drill helpers

    private var drillMonthId: String? {
        if case .month(let id)    = drillLevel { return id }
        if case .week(let id, _)  = drillLevel { return id }
        return nil
    }
    private var drillWeek: Int? {
        if case .week(_, let w) = drillLevel { return w }
        return nil
    }
    private var isYearLevel:  Bool { drillLevel == .year }
    private var isMonthLevel: Bool { if case .month = drillLevel { return true }; return false }
    private var isWeekLevel:  Bool { if case .week  = drillLevel { return true }; return false }

    private func weeklyBreakdown(for m: MonthlyUsage) -> [WeeklyUsage] {
        let df  = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        var buckets: [Int: Double] = [:]
        for (dateStr, amount) in m.byDay {
            guard let date = df.date(from: dateStr) else { continue }
            buckets[cal.component(.weekOfYear, from: date), default: 0] += amount
        }
        return buckets.sorted { $0.key < $1.key }
                      .map { WeeklyUsage(id: $0.key, weekOfYear: $0.key, total: $0.value) }
    }

    private func dailyBreakdown(for m: MonthlyUsage, weekOfYear: Int) -> [DayUsage] {
        let df  = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        return m.byDay.compactMap { (dateStr, amount) -> DayUsage? in
            guard let date = df.date(from: dateStr) else { return nil }
            guard cal.component(.weekOfYear, from: date) == weekOfYear else { return nil }
            return DayUsage(id: dateStr, date: date, amount: amount)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                statsHeader

                if state.isLoadingHistory {
                    loadingView
                } else if activeMonths.isEmpty {
                    emptyView
                } else {
                    yearSummaryCard
                    drillableChartCard
                    if let td = trendData, isYearLevel { trendCard(td) }
                    if !allProducts.isEmpty, isYearLevel { productBreakdownCard }
                    if let ad = adherenceData, isYearLevel { budgetAdherenceCard(ad) }
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.isLoadingHistory)
        }
        .frame(width: 380)
        .frame(minHeight: 220, maxHeight: 880)
        .background(VisualEffectBackground())
        .task(id: selectedYear) {
            drillLevel   = .year
            hoveredValue = nil
            await state.loadHistory(year: selectedYear)
        }
    }

    // MARK: - Header

    private var statsHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        state.showStats = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Zurück zum Dashboard")

                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [.purple, .indigo],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                        .shadow(color: .purple.opacity(0.45), radius: 6, y: 3)
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Statistiken")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Verbrauchsanalyse")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            yearSegmentedControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }

    private var yearSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(availableYears, id: \.self) { y in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedYear = y
                    }
                } label: {
                    Text(String(y))
                        .font(.system(size: 11, weight: selectedYear == y ? .semibold : .regular))
                        .foregroundStyle(selectedYear == y ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selectedYear == y
                                      ? AnyShapeStyle(Color.purple.opacity(0.75))
                                      : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)

                if y != availableYears.last {
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(3)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(0.9).tint(.purple)
            Text("Lade \(String(selectedYear))…").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(32).glassCard()
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("Keine Daten für \(String(selectedYear))")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("Stelle sicher, dass Token und Account korrekt konfiguriert sind.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(28).glassCard()
    }

    // MARK: - Year Summary

    private var yearSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Jahresübersicht \(String(selectedYear))", systemImage: "calendar.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if overBudgetCount > 0 {
                    Label("\(overBudgetCount)× über Budget", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                kpiTile(icon: "dollarsign.circle.fill",      color: .purple, label: "Gesamt",  value: fmt(yearTotal))
                kpiTile(icon: "chart.line.flattrend.xyaxis", color: .indigo, label: "Ø/Monat", value: fmt(avgMonthly))
                kpiTile(icon: "flame.fill",  color: .orange, label: "Spitze",  value: peakMonth.map(\.shortName) ?? "–")
                kpiTile(icon: "leaf.fill",   color: .green,  label: "Günstig", value: cheapestMonth.map(\.shortName) ?? "–")
            }
        }
        .padding(14).glassCard()
    }

    private func kpiTile(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.system(size: 8)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: - Drillable Chart Card

    private var drillableChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            drillHeader

            Group {
                if isYearLevel {
                    yearBarChart
                } else if isMonthLevel, let mid = drillMonthId,
                          let m = months.first(where: { $0.id == mid }) {
                    let weeks = weeklyBreakdown(for: m)
                    monthBarChart(weeks: weeks, monthData: m)
                } else if isWeekLevel, let mid = drillMonthId, let wk = drillWeek,
                          let m = months.first(where: { $0.id == mid }) {
                    let days = dailyBreakdown(for: m, weekOfYear: wk)
                    weekBarChart(days: days)
                }
            }
            .frame(height: 180)
            .id(drillLevel)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: drillLevel)
        }
        .padding(14)
        .glassCard()
    }

    // MARK: Drill header (breadcrumb + hover value)

    private var drillHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            // Breadcrumb navigation
            if isYearLevel {
                Label("Monatsvergleich", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
            } else if isMonthLevel, let mid = drillMonthId {
                let mName = months.first(where: { $0.id == mid })?.monthName ?? ""
                backChip(label: String(selectedYear)) { drillLevel = .year }
                Text("›").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(mName).font(.system(size: 11, weight: .semibold))
            } else if isWeekLevel, let mid = drillMonthId, let wk = drillWeek {
                let mName = months.first(where: { $0.id == mid })?.monthName ?? ""
                backChip(label: mName) { drillLevel = .month(mid) }
                Text("›").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("KW \(wk)").font(.system(size: 11, weight: .semibold))
            }

            Spacer()

            // Live hover value
            if let hov = hoveredValue {
                HStack(spacing: 4) {
                    Text(hov.label).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(fmt(hov.amount))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isYearLevel, state.settings.budget > 0 {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.red.opacity(0.55)).frame(width: 12, height: 2)
                    Text("Budget \(fmt(state.settings.budget))")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredValue?.label)
    }

    private func backChip(label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                action()
                hoveredValue = nil
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(Color.purple.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    // MARK: Year Bar Chart (12 months, click → month)

    private var yearBarChart: some View {
        Chart {
            ForEach(months) { m in
                BarMark(x: .value("Monat", m.shortName), y: .value("Kosten", m.total))
                    .foregroundStyle(hoveredValue?.label == m.shortName
                                     ? AnyShapeStyle(Color.purple.opacity(0.95))
                                     : AnyShapeStyle(barGradient(for: m)))
                    .cornerRadius(5)
            }
            if avgMonthly > 0 {
                RuleMark(y: .value("Ø", avgMonthly))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.purple.opacity(0.4))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Ø \(fmtShort(avgMonthly))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.purple.opacity(0.65))
                    }
            }
            if state.settings.budget > 0 {
                RuleMark(y: .value("Budget", state.settings.budget))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .foregroundStyle(Color.red.opacity(0.5))
            }
        }
        .chartYAxis { standardYAxis }
        .chartXAxis { standardXAxis }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let x = loc.x - geo[proxy.plotAreaFrame].origin.x
                            if let name: String = proxy.value(atX: x, as: String.self),
                               let m = months.first(where: { $0.shortName == name }) {
                                hoveredValue = (name, m.total)
                            }
                        case .ended: hoveredValue = nil
                        }
                    }
                    .onTapGesture { loc in
                        let x = loc.x - geo[proxy.plotAreaFrame].origin.x
                        if let name: String = proxy.value(atX: x, as: String.self),
                           let m = months.first(where: { $0.shortName == name }), m.total > 0 {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                drillLevel   = .month(m.id)
                                hoveredValue = nil
                            }
                        }
                    }
            }
        }
    }

    // MARK: Month Bar Chart (weekly, click → week)

    private func monthBarChart(weeks: [WeeklyUsage], monthData: MonthlyUsage) -> some View {
        let maxVal = weeks.map(\.total).max() ?? 0
        return Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Woche", w.label), y: .value("Kosten", w.total))
                    .foregroundStyle(hoveredValue?.label == w.label
                                     ? AnyShapeStyle(Color.indigo.opacity(0.95))
                                     : AnyShapeStyle(LinearGradient(
                                            colors: [.indigo.opacity(0.45), .purple.opacity(0.9)],
                                            startPoint: .bottom, endPoint: .top)))
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 3) {
                        if w.total > 0 {
                            Text(fmtShort(w.total))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .chartYAxis { standardYAxis }
        .chartXAxis { standardXAxis }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let x = loc.x - geo[proxy.plotAreaFrame].origin.x
                            if let lbl: String = proxy.value(atX: x, as: String.self),
                               let w = weeks.first(where: { $0.label == lbl }) {
                                hoveredValue = (lbl, w.total)
                            }
                        case .ended: hoveredValue = nil
                        }
                    }
                    .onTapGesture { loc in
                        let x = loc.x - geo[proxy.plotAreaFrame].origin.x
                        if let lbl: String = proxy.value(atX: x, as: String.self),
                           let w = weeks.first(where: { $0.label == lbl }), w.total > 0 {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                drillLevel   = .week(monthData.id, w.weekOfYear)
                                hoveredValue = nil
                            }
                        }
                    }
            }
        }
        // suppress unused warning
        .onChange(of: maxVal) { _ in }
    }

    // MARK: Week Bar Chart (daily, no further drill)

    private func weekBarChart(days: [DayUsage]) -> some View {
        Chart {
            ForEach(days) { d in
                BarMark(x: .value("Tag", d.id), y: .value("Kosten", d.amount))
                    .foregroundStyle(hoveredValue?.label == d.weekdayShort
                                     ? AnyShapeStyle(Color.cyan.opacity(0.95))
                                     : AnyShapeStyle(LinearGradient(
                                            colors: [.teal.opacity(0.45), .cyan.opacity(0.9)],
                                            startPoint: .bottom, endPoint: .top)))
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 3) {
                        if d.amount > 0 {
                            Text(fmtShort(d.amount))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .chartYAxis { standardYAxis }
        .chartXAxis {
            AxisMarks(values: days.map(\.id)) { val in
                AxisValueLabel {
                    if let dateStr = val.as(String.self),
                       let day = days.first(where: { $0.id == dateStr }) {
                        VStack(spacing: 1) {
                            Text(day.weekdayShort)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(day.dateShort)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
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
                            let x = loc.x - geo[proxy.plotAreaFrame].origin.x
                            if let dateStr: String = proxy.value(atX: x, as: String.self),
                               let d = days.first(where: { $0.id == dateStr }) {
                                hoveredValue = (d.weekdayShort, d.amount)
                            }
                        case .ended: hoveredValue = nil
                        }
                    }
            }
        }
    }

    // MARK: Shared axis styles

    @AxisContentBuilder
    private var standardYAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary.opacity(0.08))
            AxisValueLabel {
                if let d = val.as(Double.self) {
                    Text(fmtShort(d)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @AxisContentBuilder
    private var standardXAxis: some AxisContent {
        AxisMarks { val in
            AxisValueLabel {
                if let s = val.as(String.self) {
                    Text(s).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Bar colour (year chart)

    private func barGradient(for month: MonthlyUsage) -> LinearGradient {
        let over = state.settings.budget > 0 && month.total > state.settings.budget
        return over
            ? LinearGradient(colors: [.red.opacity(0.45), .orange.opacity(0.85)],   startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [.purple.opacity(0.45), .indigo.opacity(0.9)], startPoint: .bottom, endPoint: .top)
    }

    // MARK: - Trend Card

    private func trendCard(_ td: (last: MonthlyUsage, prev: MonthlyUsage, diff: Double, pct: Double)) -> some View {
        let isUp = td.diff > 0
        let recentSorted = activeMonths.sorted { $0.month < $1.month }

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isUp ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: isUp ? "arrow.up.forward" : "arrow.down.forward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isUp ? .red : .green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Monat-zu-Monat Trend")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(isUp ? "+" : "")\(fmt(td.diff))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isUp ? .red : .green)
                    Text("(\(String(format: "%.0f", td.pct))%)")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text("\(td.prev.monthName) → \(td.last.monthName)")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }

            Spacer()

            if recentSorted.count >= 2 {
                let recent = Array(recentSorted.suffix(5))
                let maxVal = recent.map(\.total).max() ?? 1
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(recent) { m in
                        let h = CGFloat(m.total / maxVal) * 30
                        RoundedRectangle(cornerRadius: 2)
                            .fill(m.id == td.last.id
                                  ? AnyShapeStyle(Color.purple)
                                  : AnyShapeStyle(Color.purple.opacity(0.3)))
                            .frame(width: 6, height: max(3, h))
                    }
                }
                .frame(height: 30, alignment: .bottom)
            }
        }
        .padding(14).glassCard()
    }

    // MARK: - Product Breakdown

    private var productBreakdownCard: some View {
        let top = Array(allProducts.prefix(6))
        let topTotal = top.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Top Produkte", systemImage: "square.3.layers.3d.top.filled")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmt(yearTotal))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("Jahrestotal").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            VStack(spacing: 9) {
                ForEach(Array(top.enumerated()), id: \.offset) { i, pair in
                    productRow(name: pair.name, amount: pair.amount, total: topTotal, colorIndex: i)
                }
            }
        }
        .padding(14).glassCard()
    }

    private let productColors: [Color] = [.purple, .blue, .cyan, .indigo, .teal, .mint]

    private func productRow(name: String, amount: Double, total: Double, colorIndex: Int) -> some View {
        let pct   = total > 0 ? amount / total : 0
        let color = productColors[colorIndex % productColors.count]

        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Image(systemName: productIcon(for: name))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color)
                }
                Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                Spacer()
                Text(fmt(amount))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.9)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * pct)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Budget Adherence

    private func budgetAdherenceCard(_ ad: (under: Int, total: Int, rate: Double)) -> some View {
        let rateColor: Color = ad.rate >= 0.8 ? .green : ad.rate >= 0.5 ? .orange : .red

        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: ad.rate)
                    .stroke(
                        AngularGradient(
                            colors: ad.rate >= 0.8 ? [.green, .teal]
                                  : ad.rate >= 0.5 ? [.orange, .yellow] : [.red, .orange],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: ad.rate)
                Text("\(Int(ad.rate * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(rateColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(rateColor)
                    Text("Budget-Einhaltung").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Text("\(ad.under) von \(ad.total) Monaten im Budget")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text("Limit: \(fmt(state.settings.budget)) / Monat")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14).glassCard()
    }

    // MARK: - Helpers

    private func productIcon(for product: String) -> String {
        switch product.lowercased() {
        case let p where p.contains("copilot"):   return "sparkles"
        case let p where p.contains("action"):    return "bolt.fill"
        case let p where p.contains("package"):   return "shippingbox.fill"
        case let p where p.contains("codespace"): return "desktopcomputer"
        case let p where p.contains("storage"):   return "internaldrive.fill"
        default:                                  return "square.grid.2x2.fill"
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "$%.2f", v) }
    private func fmtShort(_ v: Double) -> String {
        v >= 100 ? String(format: "$%.0f", v) : v >= 1 ? String(format: "$%.1f", v) : String(format: "$%.2f", v)
    }
}
