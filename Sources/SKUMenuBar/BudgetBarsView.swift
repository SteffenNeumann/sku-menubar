import SwiftUI

struct BudgetBarsView: View {
    @EnvironmentObject var state: AppState

    private var budget: Double { state.settings.budget }

    private var dailyRef: Double {
        guard budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return budget / Double(days)
    }

    private var todayPct:   Double { dailyRef > 0 ? min(1, state.todayCost / dailyRef) : 0 }
    private var todayFree:  Double { max(0, dailyRef - state.todayCost) }

    var body: some View {
        VStack(spacing: 14) {

            // ── Heute ────────────────────────────────────────────────────
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .frame(width: 14)
                    Text("Heute")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(fmt(state.todayCost))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 10))
                    Text("\(fmt(todayFree)) frei")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                // Zweigeteilter Balken: verbraucht (blau) + frei (grün)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if todayPct > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.gradient)
                                .frame(width: geo.size.width * todayPct)
                                .animation(.spring(duration: 0.5), value: todayPct)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 6)
                // Legende unter dem Balken
                HStack {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text("verbraucht")
                    Circle().fill(.green.opacity(0.6)).frame(width: 6, height: 6)
                        .padding(.leading, 4)
                    Text("frei")
                    Spacer()
                    Text("Limit \(fmt(dailyRef))")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            // ── Dieser Monat ─────────────────────────────────────────────
            budgetRow(
                icon:    "calendar",
                label:   "Dieser Monat",
                left:    fmt(state.monthCost),
                right:   budget > 0 ? "von \(fmt(budget))" : "",
                caption: nil,
                pct:     state.monthPct,
                tint:    consumedColor(state.monthPct)
            )

            // ── Noch verfügbar ───────────────────────────────────────────
            budgetRow(
                icon:    "gauge.with.dots.needle.33percent",
                label:   "Noch verfügbar",
                left:    budget > 0 ? fmt(state.remain) : "–",
                right:   budget > 0 ? "\(Int(state.remainPct * 100))%" : "",
                caption: nil,
                pct:     state.remainPct,
                tint:    remainColor(state.remainPct)
            )
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func budgetRow(
        icon: String, label: String,
        left: String, right: String, caption: String?,
        pct: Double, tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            // Title + values on one line
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(left)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                if !right.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 10))
                    Text(right)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.gradient)
                        .frame(width: geo.size.width * max(0, min(1, pct)))
                        .animation(.spring(duration: 0.5), value: pct)
                }
            }
            .frame(height: 6)

            // Caption (only for "Heute")
            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Colors

    /// For consumed bars: neutral until high usage
    private func consumedColor(_ pct: Double) -> Color {
        pct > 0.9 ? .red : pct > 0.75 ? .orange : .blue
    }

    /// For "Noch verfügbar": stays green until critically low
    private func remainColor(_ pct: Double) -> Color {
        pct < 0.2 ? .red : pct < 0.4 ? .orange : .green
    }

    private func fmt(_ v: Double) -> String {
        String(format: "€%.2f", v)
    }
}
