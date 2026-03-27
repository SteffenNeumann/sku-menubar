import SwiftUI

/// Mirrors the layout of claude.ai/settings/usage:
/// Current Session (Today) · Weekly Limits · Day / Month / Year totals
struct UsageOverviewCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    // MARK: - Derived

    private var claudeMode: Bool {
        state.settings.claudeWeeklyCostLimit > 0
    }

    // GitHub mode
    private var dailyBudget: Double {
        guard state.settings.budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.settings.budget / Double(days)
    }
    private var todayPct:   Double { dailyBudget > 0 ? min(1, state.todayCost / dailyBudget) : 0 }
    private var weekPct:    Double { state.weekPct }
    private var weekBudget: Double { state.weekBudget }

    // Claude mode
    private var claudeDailyLimit:  Double { state.settings.claudeWeeklyCostLimit / 7 }
    private var claudeWeeklyLimit: Double { state.settings.claudeWeeklyCostLimit }
    private var claudeTodayPct:    Double { claudeDailyLimit  > 0 ? min(1, state.claudeTodayCost / claudeDailyLimit)  : 0 }
    private var claudeWeekPct:     Double { claudeWeeklyLimit > 0 ? min(1, state.claudeWeekCost  / claudeWeeklyLimit) : 0 }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Title ────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text("Verbrauchsübersicht")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if claudeMode {
                    Text("Claude")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.purple.opacity(0.12), in: Capsule())
                }
            }

            // ── Current Session (Today) ───────────────────────────────
            usageRow(
                label:  "Heute",
                icon:   "sun.max.fill",
                tint:   .orange,
                amount: claudeMode ? state.claudeTodayCost : state.todayCost,
                limit:  claudeMode ? claudeDailyLimit      : dailyBudget,
                pct:    claudeMode ? claudeTodayPct        : todayPct
            )

            // ── Weekly Limits ─────────────────────────────────────────
            usageRow(
                label:  "Diese Woche (Di–Mo)",
                icon:   "calendar.badge.clock",
                tint:   .blue,
                amount: claudeMode ? state.claudeWeekCost : state.weekCost,
                limit:  claudeMode ? claudeWeeklyLimit    : weekBudget,
                pct:    claudeMode ? claudeWeekPct        : weekPct
            )

        }
        .padding(14)
        .mirrorCard()
    }

    // MARK: - Usage Row (label + amount + bar + limit)

    private func usageRow(
        label: String, icon: String, tint: Color,
        amount: Double, limit: Double, pct: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(fmt(amount))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [barTint(pct, tint).opacity(0.65), barTint(pct, tint)],
                            startPoint: .leading,
                            endPoint:   .trailing
                        ))
                        .frame(width: geo.size.width * max(0, min(1, pct)))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 5)

            HStack {
                if limit > 0 {
                    Text("Limit \(fmt(limit))  ·  verbleibend \(fmt(max(0, limit - amount)))")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    Text("Kein Limit konfiguriert")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barTint(pct, tint).opacity(0.85))
            }
        }
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String { state.fmt(v) }

    private func barTint(_ pct: Double, _ base: Color) -> Color {
        pct > 0.9 ? .red : pct > 0.75 ? .orange : base
    }
}
