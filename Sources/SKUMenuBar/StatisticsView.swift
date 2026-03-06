import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var availableYears: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((max(2024, y - 2)...y).reversed())
    }

    private var months: [MonthlyUsage] { state.historicalMonths }

    private var yearTotal: Double   { months.reduce(0) { $0 + $1.total } }
    private var activeMonths: [MonthlyUsage] { months.filter { $0.total > 0 } }
    private var avgMonthly: Double  { activeMonths.isEmpty ? 0 : yearTotal / Double(activeMonths.count) }
    private var peakMonth: MonthlyUsage?  { months.max(by: { $0.total < $1.total }) }
    private var cheapestMonth: MonthlyUsage? { activeMonths.min(by: { $0.total < $1.total }) }
    private var overBudgetCount: Int {
        guard state.settings.budget > 0 else { return 0 }
        return activeMonths.filter { $0.total > state.settings.budget }.count
    }

    private var allProducts: [(name: String, amount: Double)] {
        var combined: [String: Double] = [:]
        for m in months {
            for (p, v) in m.byProduct { combined[p, default: 0] += v }
        }
        return combined.map { (name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // Trend data (last 2 active months)
    private var trendData: (last: MonthlyUsage, prev: MonthlyUsage, diff: Double, pct: Double)? {
        let sorted = months.filter { $0.total > 0 }.sorted { $0.month < $1.month }
        guard sorted.count >= 2 else { return nil }
        let last = sorted[sorted.count - 1]
        let prev = sorted[sorted.count - 2]
        let diff = last.total - prev.total
        let pct  = prev.total > 0 ? abs(diff) / prev.total * 100 : 0
        return (last, prev, diff, pct)
    }

    // Budget adherence data
    private var adherenceData: (under: Int, total: Int, rate: Double)? {
        guard state.settings.budget > 0, !activeMonths.isEmpty else { return nil }
        let under = activeMonths.filter { $0.total <= state.settings.budget }.count
        let rate  = Double(under) / Double(activeMonths.count)
        return (under, activeMonths.count, rate)
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
                    monthlyChartCard
                    if let td = trendData { trendCard(td) }
                    if !allProducts.isEmpty { productBreakdownCard }
                    if let ad = adherenceData { budgetAdherenceCard(ad) }
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.isLoadingHistory)
        }
        .frame(width: 360)
        .frame(minHeight: 220, maxHeight: 740)
        .background(VisualEffectBackground())
        .task(id: selectedYear) {
            await state.loadHistory(year: selectedYear)
        }
    }

    // MARK: - Header

    private var statsHeader: some View {
        HStack(spacing: 10) {
            // Back
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

            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 34, height: 34)
                    .shadow(color: .purple.opacity(0.45), radius: 6, y: 3)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Statistiken")
                    .font(.system(size: 14, weight: .semibold))
                Text("Verbrauchsanalyse")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Year picker chips
            HStack(spacing: 4) {
                ForEach(availableYears, id: \.self) { y in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedYear = y
                        }
                    } label: {
                        Text(String(y))
                            .font(.system(size: 10, weight: selectedYear == y ? .semibold : .regular))
                            .foregroundStyle(selectedYear == y ? .white : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(selectedYear == y
                                          ? AnyShapeStyle(Color.purple.opacity(0.75))
                                          : AnyShapeStyle(Color.primary.opacity(0.07)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.purple)
            Text("Lade \(selectedYear)…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .glassCard()
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Keine Daten für \(selectedYear)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Stelle sicher, dass Token und Account korrekt konfiguriert sind.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassCard()
    }

    // MARK: - Year Summary KPI Cards

    private var yearSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Jahresübersicht \(selectedYear)", systemImage: "calendar.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if overBudgetCount > 0 {
                    Label("\(overBudgetCount)× über Budget", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 6) {
                kpiTile(icon: "dollarsign.circle.fill",       color: .purple, label: "Gesamt",   value: fmt(yearTotal))
                kpiTile(icon: "chart.line.flattrend.xyaxis",  color: .indigo, label: "Ø/Monat",  value: fmt(avgMonthly))
                kpiTile(icon: "flame.fill",                   color: .orange, label: "Spitze",   value: peakMonth.map { $0.shortName } ?? "–")
                kpiTile(icon: "leaf.fill",                    color: .green,  label: "Günstig",  value: cheapestMonth.map { $0.shortName } ?? "–")
            }
        }
        .padding(14)
        .glassCard()
    }

    private func kpiTile(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: - Monthly Bar Chart

    private var monthlyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Monatsvergleich", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if state.settings.budget > 0 {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.red.opacity(0.55))
                            .frame(width: 14, height: 2)
                        Text("Budget \(fmt(state.settings.budget))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Chart {
                // Bars
                ForEach(months) { m in
                    BarMark(
                        x: .value("Monat", m.shortName),
                        y: .value("Kosten", m.total)
                    )
                    .foregroundStyle(barGradient(for: m))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 2) {
                        if m.total > 0 {
                            Text(fmtShort(m.total))
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Average rule
                if avgMonthly > 0 {
                    RuleMark(y: .value("Durchschnitt", avgMonthly))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.purple.opacity(0.45))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("Ø")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.purple.opacity(0.7))
                        }
                }

                // Budget rule
                if state.settings.budget > 0 {
                    RuleMark(y: .value("Budget", state.settings.budget))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundStyle(Color.red.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let d = val.as(Double.self) {
                            Text(fmtShort(d))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 165)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .glassCard()
    }

    private func barGradient(for month: MonthlyUsage) -> LinearGradient {
        let over = state.settings.budget > 0 && month.total > state.settings.budget
        return over
            ? LinearGradient(colors: [.red.opacity(0.45), .orange.opacity(0.85)],   startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [.purple.opacity(0.45), .indigo.opacity(0.9)], startPoint: .bottom, endPoint: .top)
    }

    // MARK: - Trend Card

    private func trendCard(_ td: (last: MonthlyUsage, prev: MonthlyUsage, diff: Double, pct: Double)) -> some View {
        let isUp = td.diff > 0
        let recentSorted = months.filter { $0.total > 0 }.sorted { $0.month < $1.month }

        return HStack(spacing: 14) {
            // Direction icon
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(isUp ? "+" : "")\(fmt(td.diff))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isUp ? .red : .green)
                    Text("(\(String(format: "%.0f", td.pct))%)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text("\(td.prev.monthName) → \(td.last.monthName)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Mini sparkline (last ≤5 active months)
            if recentSorted.count >= 2 {
                let recent  = Array(recentSorted.suffix(5))
                let maxVal  = recent.map(\.total).max() ?? 1
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
        .padding(14)
        .glassCard()
    }

    // MARK: - Product Breakdown

    private var productBreakdownCard: some View {
        let top      = Array(allProducts.prefix(6))
        let topTotal = top.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Top Produkte", systemImage: "square.3.layers.3d.top.filled")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("Jahrestotal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 9) {
                ForEach(Array(top.enumerated()), id: \.offset) { i, pair in
                    productRow(name: pair.name, amount: pair.amount, total: topTotal, colorIndex: i)
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    private let productColors: [Color] = [.purple, .blue, .cyan, .indigo, .teal, .mint]

    private func productRow(name: String, amount: Double, total: Double, colorIndex: Int) -> some View {
        let pct   = total > 0 ? amount / total : 0
        let color = productColors[colorIndex % productColors.count]

        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: 14)
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                Text(fmt(amount))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.5), color.opacity(0.9)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * pct)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Budget Adherence Donut

    private func budgetAdherenceCard(_ ad: (under: Int, total: Int, rate: Double)) -> some View {
        let rateColor: Color = ad.rate >= 0.8 ? .green : ad.rate >= 0.5 ? .orange : .red

        return HStack(spacing: 16) {
            // Donut gauge
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: ad.rate)
                    .stroke(
                        AngularGradient(
                            colors: ad.rate >= 0.8 ? [.green, .teal]
                                  : ad.rate >= 0.5 ? [.orange, .yellow]
                                  : [.red, .orange],
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
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(rateColor)
                    Text("Budget-Einhaltung")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(ad.under) von \(ad.total) Monaten im Budget")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Limit: \(fmt(state.settings.budget)) / Monat")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String      { String(format: "$%.2f", v) }
    private func fmtShort(_ v: Double) -> String {
        v >= 100 ? String(format: "$%.0f", v)
               : v >= 1 ? String(format: "$%.1f", v)
               : String(format: "$%.2f", v)
    }
}
