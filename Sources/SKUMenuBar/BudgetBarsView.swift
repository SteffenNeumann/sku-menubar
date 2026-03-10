import SwiftUI

struct BudgetBarsView: View {
    @EnvironmentObject var state: AppState

    private var budget: Double { state.settings.budget }

    private var dailyRef: Double {
        guard budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return budget / Double(days)
    }

    private var todayPct:  Double { dailyRef > 0 ? min(1, state.todayCost / dailyRef) : 0 }
    private var todayFree: Double { max(0, dailyRef - state.todayCost) }

    var body: some View {
        VStack(spacing: 10) {

            // ── Top row: Heute + Monat ────────────────────────────────
            HStack(spacing: 10) {
                statCard(
                    icon:      "sun.max.fill",
                    iconColor: .orange,
                    title:     "Heute",
                    amount:    state.todayCost,
                    subtitle:  "Limit \(fmt(dailyRef))",
                    pct:       todayPct,
                    tint:      consumedColor(todayPct)
                )
                statCard(
                    icon:      "calendar",
                    iconColor: .blue,
                    title:     "Dieser Monat",
                    amount:    state.monthCost,
                    subtitle:  budget > 0 ? "von \(fmt(budget))" : "kein Limit",
                    pct:       state.monthPct,
                    tint:      consumedColor(state.monthPct)
                )
            }

            // ── Full-width: Noch verfügbar ────────────────────────────
            remainCard
        }
    }

    // MARK: - Stat Card (half-width)

    private func statCard(
        icon: String, iconColor: Color,
        title: String, amount: Double, subtitle: String,
        pct: Double, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(fmt(amount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 5) {
                progressBar(pct: pct, tint: tint)

                HStack {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.9))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Remain Card (full-width)

    private var remainCard: some View {
        HStack(spacing: 14) {

            // Circular progress gauge
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: state.remainPct)
                    .stroke(
                        remainColor(state.remainPct).gradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: state.remainPct)

                Text("\(Int(state.remainPct * 100))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(remainColor(state.remainPct))
            }
            .frame(width: 52, height: 52)

            // Labels + value
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Noch verfügbar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(budget > 0 ? fmt(state.remain) : "–")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(remainColor(state.remainPct))

                    if budget > 0 {
                        Text("im Budget")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Trend: today vs. daily limit
            if dailyRef > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: todayPct < 0.75 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(todayPct < 0.75 ? .green : .orange)
                    Text(todayPct < 0.75 ? "unter Limit" : "über Limit")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Progress Bar

    private func progressBar(pct: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.7), tint],
                            startPoint: .leading,
                            endPoint:   .trailing
                        )
                    )
                    .frame(width: geo.size.width * max(0, min(1, pct)))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: pct)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Color helpers

    private func consumedColor(_ pct: Double) -> Color {
        pct > 0.9 ? .red : pct > 0.75 ? .orange : .blue
    }

    private func remainColor(_ pct: Double) -> Color {
        pct < 0.2 ? .red : pct < 0.4 ? .orange : .green
    }

    private func fmt(_ v: Double) -> String { state.fmt(v) }
}
