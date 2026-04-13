import SwiftUI
import Charts

/// Cascading drill-down bar chart: Months -> Weeks -> Days
/// Tap a bar to zoom in; use back button to go up.
struct DrilldownChartCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    /// Sorted monthly totals, e.g. [(id: "2026-03", label: "Mar", value: 22.52)]
    let monthlyData: [(id: String, label: String, value: Double)]
    /// All daily costs, keyed "yyyy-MM-dd"
    let dailyData: [String: Double]
    let fmtFn: (Double) -> String
    var isLoading: Bool = false
    var errorMsg: String? = nil

    @State private var selectedMonth: String? = nil   // "yyyy-MM"
    @State private var selectedWeek: String? = nil    // "yyyy-Www"
    @State private var hoveredBar: String? = nil
    @Environment(\.appTheme) var theme

    private enum DrillLevel {
        case months
        case weeks(monthId: String)
        case days(weekId: String, monthId: String)
    }

    private var drillLevel: DrillLevel {
        if let w = selectedWeek, let m = selectedMonth { return .days(weekId: w, monthId: m) }
        if let m = selectedMonth { return .weeks(monthId: m) }
        return .months
    }

    // MARK: - Chart data

    private var chartItems: [(id: String, label: String, value: Double)] {
        switch drillLevel {
        case .months:                       return monthlyData
        case .weeks(let m):                 return weeksForMonth(m)
        case .days(let w, let m):           return daysForWeek(w, in: m)
        }
    }

    private var levelTitle: String {
        switch drillLevel {
        case .months:                       return "Jahresuebersicht"
        case .weeks(let m):                 return monthLongLabel(for: m)
        case .days(let w, _):              return weekLabel(for: w)
        }
    }

    private var hint: String? {
        switch drillLevel {
        case .months:                       return chartItems.isEmpty ? nil : "Monat antippen fuer Wochendetails"
        case .weeks:                        return chartItems.isEmpty ? nil : "Woche antippen fuer Tagesdetails"
        case .days:                         return nil
        }
    }

    private var canGoBack: Bool {
        switch drillLevel { case .months: return false; default: return true }
    }

    private var backLabel: String {
        switch drillLevel {
        case .weeks:     return "Jahresuebersicht"
        case .days:      return weekLabel(for: selectedWeek ?? "")
        default:         return "Zurueck"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // -- Header --
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                if canGoBack {
                    Button {
                        withAnimation(.spring(response: 0.3)) { goBack() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(backLabel)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(accentColor.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            // -- Level label + hovered value --
            HStack {
                Text(levelTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let hov = hoveredBar,
                   let item = chartItems.first(where: { $0.id == hov }) {
                    Text(fmtFn(item.value))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 6)

            // -- Chart or placeholder --
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else if let err = errorMsg {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.system(size: 13))
                    Text(err).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14).padding(.bottom, 12)
            } else if chartItems.isEmpty {
                Text("Keine Daten")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else {
                Chart {
                    ForEach(chartItems, id: \.id) { item in
                        BarMark(
                            x: .value("Label", item.label),
                            y: .value("Kosten", item.value)
                        )
                        .foregroundStyle(
                            hoveredBar == item.id
                                ? AnyShapeStyle(accentColor.opacity(0.95))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.45), accentColor.opacity(0.85)],
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
                            if let d = val.as(Double.self) {
                                Text(fmtFn(d))
                                    .font(.system(size: 11))
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
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
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
                                        hoveredBar = chartItems.first(where: { $0.label == lbl })?.id
                                    }
                                case .ended:
                                    hoveredBar = nil
                                }
                            }
                            .onTapGesture { location in
                                let x = location.x - (proxy.plotFrame.map { geo[$0].origin.x } ?? 0)
                                if let lbl: String = proxy.value(atX: x, as: String.self),
                                   let item = chartItems.first(where: { $0.label == lbl }) {
                                    withAnimation(.spring(response: 0.3)) { drill(into: item.id) }
                                }
                            }
                    }
                }
                .frame(height: 150)
                .padding(.horizontal, 12).padding(.bottom, 8)
            }

            // -- Hint text --
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 10)
            }
        }
        .mirrorCard()
    }

    // MARK: - Navigation

    private func goBack() {
        switch drillLevel {
        case .days:  selectedWeek = nil
        case .weeks: selectedMonth = nil
        default:     break
        }
        hoveredBar = nil
    }

    private func drill(into id: String) {
        switch drillLevel {
        case .months: selectedMonth = id
        case .weeks:  selectedWeek  = id
        case .days:   break
        }
        hoveredBar = nil
    }

    // MARK: - Data computation

    private func weeksForMonth(_ monthId: String) -> [(id: String, label: String, value: Double)] {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var weekTotals: [String: Double] = [:]

        for (dateStr, amount) in dailyData {
            guard dateStr.hasPrefix(monthId) else { continue }
            guard let date = df.date(from: dateStr) else { continue }
            let weekOfYear  = cal.component(.weekOfYear,        from: date)
            let yearForWeek = cal.component(.yearForWeekOfYear, from: date)
            let weekId = "\(yearForWeek)-W\(String(format: "%02d", weekOfYear))"
            weekTotals[weekId, default: 0] += amount
        }

        return weekTotals
            .map { (id: $0.key, label: weekLabel(for: $0.key), value: $0.value) }
            .sorted { $0.id < $1.id }
    }

    private func daysForWeek(_ weekId: String, in monthId: String) -> [(id: String, label: String, value: Double)] {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let parts = weekId.split(separator: "-")
        guard parts.count == 2,
              let year    = Int(parts[0]),
              let weekNum = Int(String(parts[1]).dropFirst()) else { return [] }

        var result: [(id: String, label: String, value: Double)] = []

        for (dateStr, amount) in dailyData {
            guard dateStr.hasPrefix(monthId) else { continue }
            guard let date = df.date(from: dateStr) else { continue }
            guard cal.component(.weekOfYear,        from: date) == weekNum,
                  cal.component(.yearForWeekOfYear, from: date) == year else { continue }
            let du = DayUsage(id: dateStr, date: date, amount: amount)
            result.append((id: dateStr, label: du.weekdayShort + " " + du.dateShort, value: amount))
        }

        return result.sorted { $0.id < $1.id }
    }

    // MARK: - Label helpers

    private func weekLabel(for weekId: String) -> String {
        let parts = weekId.split(separator: "-")
        guard parts.count == 2,
              let weekNum = Int(String(parts[1]).dropFirst()) else { return weekId }
        return "KW \(weekNum)"
    }

    private func monthLongLabel(for monthId: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale     = Locale(identifier: "de_DE")
        guard let date = df.date(from: monthId) else { return monthId }
        let out = DateFormatter()
        out.dateFormat = "MMMM yyyy"
        out.locale     = Locale(identifier: "de_DE")
        return out.string(from: date)
    }
}
